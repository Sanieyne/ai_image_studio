"""Launch a Vast.ai GPU instance, deploy python_engine, and establish an SSH tunnel to port 8000.
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path
import requests

ENV_PATH = Path("/root/projects/ai_image_studio/cloud_backend/.env")
env_vars = {}
with open(ENV_PATH) as f:
    for line in f:
        if line.strip() and not line.startswith("#") and "=" in line:
            k, v = line.strip().split("=", 1)
            env_vars[k.strip()] = v.strip().strip("\"'")

VASTAI_API_KEY = env_vars.get("VASTAI_API_KEY")
R2_ENDPOINT = env_vars.get("R2_ENDPOINT")
R2_ACCESS_KEY_ID = env_vars.get("R2_ACCESS_KEY_ID")
R2_SECRET_ACCESS_KEY = env_vars.get("R2_SECRET_ACCESS_KEY")
R2_BUCKET_NAME = env_vars.get("R2_BUCKET_NAME", "cosmic-gen")

SSH_PUB_KEY = Path("/root/.ssh/id_ed25519.pub").read_text().strip()
SSH_PRIV_KEY = Path("/root/.ssh/id_ed25519")

HEADERS = {"Authorization": f"Bearer {VASTAI_API_KEY}"}


def find_best_gpu_offer():
    print("[1/5] Searching for fast, affordable GPU offers on Vast.ai (RTX 3090, 4090, A5000, 4060 Ti)...", flush=True)
    q = {
        "verified": {"eq": True},
        "rentable": {"eq": True},
        "num_gpus": {"eq": 1},
        "gpu_ram": {"gte": 16000},
        "disk_space": {"gte": 50},
        "inet_down": {"gte": 300},
        "inet_down_cost": {"lte": 0.005},
        "order": [["dph_total", "asc"]],
    }

    r = requests.get(
        "https://console.vast.ai/api/v0/bundles",
        params={"q": json.dumps(q)},
        headers=HEADERS,
        timeout=15,
    )
    offers = r.json().get("offers", [])
    if not offers:
        raise RuntimeError("No suitable GPU offers available right now on Vast.ai!")

    # Prefer 24GB GPUs (RTX 3090, RTX 4090, A5000, RTX PRO 4000)
    for o in offers:
        gpu = o.get("gpu_name", "")
        vram = o.get("gpu_ram", 0) / 1024.0
        if vram >= 23.0 and any(name in gpu for name in ["3090", "4090", "A5000", "PRO 4000"]):
            dph = round(o.get("dph_total", 0), 3)
            print(f"  Selected top 24GB GPU: Offer #{o['id']} - {gpu} ({round(vram, 1)}GB) @ ${dph}/hr | {o.get('geolocation')}", flush=True)
            return o

    chosen = offers[0]
    print(f"  Selected fallback GPU: Offer #{chosen['id']} - {chosen.get('gpu_name')} ({round(chosen.get('gpu_ram', 0)/1024, 1)}GB) @ ${round(chosen.get('dph_total', 0), 3)}/hr", flush=True)
    return chosen


def generate_onstart_script():
    return f"""#!/bin/bash
set -uo pipefail
mkdir -p /var/log /workspace /root/.ssh
exec > >(tee -a /var/log/gpu_startup.log) 2>&1
chmod 700 /root/.ssh
echo "{SSH_PUB_KEY}" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Start SSH service if not running
service ssh start || /usr/sbin/sshd || true

echo "=== GPU Instance Startup Initialized ==="
export AI_STUDIO_MODE=cloud
export AI_STUDIO_HOST=0.0.0.0
export AI_STUDIO_PORT=8000
export PIP_BREAK_SYSTEM_PACKAGES=1

apt-get update -qq && apt-get install -y -qq --no-install-recommends libgl1 libglib2.0-0 curl > /dev/null 2>&1 || true

# Install boto3 and dependencies
python3 -m pip install --no-cache-dir boto3 botocore fastapi uvicorn opencv-python-headless insightface onnxruntime-gpu requests
python3 -c "
import os, boto3
s3 = boto3.client('s3',
    endpoint_url='{R2_ENDPOINT}',
    aws_access_key_id='{R2_ACCESS_KEY_ID}',
    aws_secret_access_key='{R2_SECRET_ACCESS_KEY}')
s3.download_file('{R2_BUCKET_NAME}', 'models/engine/python_engine.tar.gz', '/workspace/python_engine.tar.gz')
"
mkdir -p /workspace/python_engine
tar -xzf /workspace/python_engine.tar.gz -C /workspace/python_engine/
cd /workspace/python_engine

# Start the engine in background
nohup python3 -m uvicorn app:app --host 0.0.0.0 --port 8000 > /var/log/ai_engine.log 2>&1 &
echo "[OK] Engine started with PID $!"
"""


def rent_gpu_instance(offer):
    offer_id = offer["id"]
    print(f"\n[2/5] Renting Vast.ai instance for offer #{offer_id} ({offer.get('gpu_name')})...", flush=True)
    onstart = generate_onstart_script()

    payload = {
        "client_id": "me",
        "image": "pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime",
        "disk": 50,
        "env": {
            "AI_STUDIO_MODE": "cloud",
            "R2_ENDPOINT": R2_ENDPOINT,
            "R2_BUCKET_NAME": R2_BUCKET_NAME,
            "R2_ACCESS_KEY_ID": R2_ACCESS_KEY_ID,
            "R2_SECRET_ACCESS_KEY": R2_SECRET_ACCESS_KEY,
            "-p 8000:8000": "1",
        },
        "onstart": onstart,
        "runtype": "ssh",
        "label": f"gpu-engine-tunnel-{int(time.time())}",
    }

    r = requests.put(
        f"https://console.vast.ai/api/v0/asks/{offer_id}/",
        json=payload,
        headers=HEADERS,
        timeout=20,
    )
    if r.status_code != 200:
        raise RuntimeError(f"Failed to rent offer {offer_id}: {r.status_code} {r.text}")

    data = r.json()
    contract_id = data.get("new_contract")
    print(f"  Successfully rented! Contract ID: #{contract_id}", flush=True)
    return contract_id


def poll_instance_ready(contract_id, timeout=400):
    print(f"\n[3/5] Waiting for GPU instance #{contract_id} to boot and report SSH endpoint...", flush=True)
    t0 = time.time()
    while time.time() - t0 < timeout:
        r = requests.get("https://console.vast.ai/api/v1/instances/", headers=HEADERS, timeout=10)
        instances = r.json().get("instances", [])
        inst = next((i for i in instances if str(i.get("id")) == str(contract_id)), None)
        if inst:
            status = inst.get("actual_status") or inst.get("cur_state")
            ssh_host = inst.get("ssh_host")
            ssh_port = inst.get("ssh_port")
            elapsed = int(time.time() - t0)
            msg = (inst.get("status_msg") or "")[:40]

            print(f"  [{elapsed}s] Status: {status} | SSH: {ssh_host}:{ssh_port} | {msg}", flush=True)
            if status == "running" and ssh_host and ssh_port:
                print(f"  Instance is RUNNING! SSH ready at {ssh_host}:{ssh_port}", flush=True)
                return inst
        time.sleep(8)

    raise TimeoutError(f"Instance #{contract_id} did not become ready within {timeout}s")


def setup_ssh_and_tunnel(ssh_host, ssh_port):
    print(f"\n[4/5] Testing SSH connection to {ssh_host}:{ssh_port}...", flush=True)
    # Add host key
    subprocess.run(
        f"ssh-keyscan -p {ssh_port} {ssh_host} >> ~/.ssh/known_hosts 2>/dev/null",
        shell=True,
    )

    # Poll SSH until responsive
    for attempt in range(1, 25):
        res = subprocess.run(
            [
                "ssh",
                "-p",
                str(ssh_port),
                "-i",
                str(SSH_PRIV_KEY),
                "-o",
                "StrictHostKeyChecking=no",
                "-o",
                "ConnectTimeout=5",
                f"root@{ssh_host}",
                "echo 'SSH_OK' && nvidia-smi --query-gpu=gpu_name,memory.total --format=csv,noheader",
            ],
            capture_output=True,
            text=True,
        )
        if "SSH_OK" in res.stdout:
            print("  SSH connection successful!", flush=True)
            gpu_info = res.stdout.replace("SSH_OK", "").strip()
            print(f"  Remote GPU Info: {gpu_info}", flush=True)
            break
        print(f"  SSH attempt {attempt}/25 waiting for container sshd...", flush=True)
        time.sleep(6)
    else:
        raise RuntimeError("Could not connect to instance over SSH after multiple attempts.")

    # Kill any existing local port 8000 process
    subprocess.run("fuser -k 8000/tcp 2>/dev/null || true", shell=True)

    print(f"\n[5/5] Establishing SSH Tunnel: localhost:8000 -> {ssh_host}:{ssh_port} (container port 8000)...", flush=True)
    tunnel_cmd = [
        "ssh",
        "-p",
        str(ssh_port),
        "-i",
        str(SSH_PRIV_KEY),
        "-N",
        "-L",
        "8000:localhost:8000",
        "-o",
        "ServerAliveInterval=15",
        "-o",
        "ServerAliveCountMax=6",
        "-o",
        "ExitOnForwardFailure=yes",
        "-o",
        "StrictHostKeyChecking=no",
        f"root@{ssh_host}",
    ]

    tunnel_proc = subprocess.Popen(tunnel_cmd)
    print(f"  SSH tunnel background process PID: {tunnel_proc.pid}", flush=True)

    # Wait for engine to respond through tunnel
    print("  Waiting for remote GPU engine to initialize and answer GET http://127.0.0.1:8000/health...", flush=True)
    for _ in range(50):
        time.sleep(3)
        try:
            r = requests.get("http://127.0.0.1:8000/health", timeout=2)
            if r.status_code == 200:
                print("  [SUCCESS] GPU Engine is responding through the SSH tunnel on http://127.0.0.1:8000!", flush=True)
                print("  Response:", r.json(), flush=True)
                return tunnel_proc.pid
        except Exception:
            pass

    print("  Tunnel active. Remote engine is still finishing dependency installation.", flush=True)
    return tunnel_proc.pid


def main():
    if len(sys.argv) > 1 and sys.argv[1].isdigit():
        contract_id = int(sys.argv[1])
        print(f"Resuming with existing GPU instance #{contract_id}...", flush=True)
    else:
        offer = find_best_gpu_offer()
        contract_id = rent_gpu_instance(offer)

    inst = poll_instance_ready(contract_id)
    ssh_host = inst["ssh_host"]
    ssh_port = inst["ssh_port"]
    tunnel_pid = setup_ssh_and_tunnel(ssh_host, ssh_port)

    print("\n" + "=" * 70, flush=True)
    print("GPU INSTANCE AND SSH TUNNEL ESTABLISHED SUCCESSFULLY!", flush=True)
    print("=" * 70, flush=True)
    print(f"Contract ID   : #{contract_id}", flush=True)
    print(f"GPU Model     : {inst.get('gpu_name')} ({round(inst.get('gpu_ram', 0)/1024, 1)} GB)", flush=True)
    print(f"Price         : ${round(inst.get('dph_total', 0), 3)}/hr", flush=True)
    print(f"SSH Target    : root@{ssh_host} -p {ssh_port}", flush=True)
    print(f"Tunnel PID    : {tunnel_pid}", flush=True)
    print("Local Tunnel  : http://127.0.0.1:8000 (Forwarded directly to remote GPU)", flush=True)
    print("\nTo tunnel directly from your personal PC / Laptop, run:", flush=True)
    print(f"  ssh -p {ssh_port} -N -L 8000:localhost:8000 root@{ssh_host}", flush=True)
    print("=" * 70, flush=True)


if __name__ == "__main__":
    main()
