#!/usr/bin/env python3
"""Automated Vast.ai execution harness for InstantID + DeepFace standalone proof.

1. Identifies and rents a cheap RTX 3090 / A5000 / RTX 4090 instance.
2. Injects custom onstart script to:
   - Pull python_engine.tar.gz from R2
   - Install requirements (insightface, deepface, diffusers, etc.)
   - Download sdxl-base-1.0 and instantid from R2
   - Run test_instantid_deepface.py
   - Upload results and logs back to R2 models/instantid_proof_outputs/
3. Polls until completion.
4. Downloads all artifacts locally to /root/instantid_test_outputs/.
5. Destroys the Vast.ai instance immediately to prevent unnecessary spend.
"""

import os
import sys
import time
import json
import requests
from pathlib import Path
import boto3

# Parse .env
ENV_PATH = Path("/root/projects/ai_image_studio/cloud_backend/.env")
env_vars = {}
with open(ENV_PATH) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env_vars[k.strip()] = v.strip().strip("\"'")

VASTAI_API_KEY = env_vars.get("VASTAI_API_KEY")
R2_ENDPOINT = env_vars.get("R2_ENDPOINT")
R2_ACCESS_KEY_ID = env_vars.get("R2_ACCESS_KEY_ID")
R2_SECRET_ACCESS_KEY = env_vars.get("R2_SECRET_ACCESS_KEY")
R2_BUCKET_NAME = env_vars.get("R2_BUCKET_NAME", "cosmic-gen")

LOCAL_OUTPUT_DIR = Path("/root/instantid_test_outputs")
LOCAL_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

s3 = boto3.client(
    "s3",
    endpoint_url=R2_ENDPOINT,
    aws_access_key_id=R2_ACCESS_KEY_ID,
    aws_secret_access_key=R2_SECRET_ACCESS_KEY,
)

HEADERS = {"Authorization": f"Bearer {VASTAI_API_KEY}"}


def find_best_offer():
    print("[*] Searching for suitable Vast.ai GPU offers (24GB+ VRAM, >600 Mbps down)...")
    q = {
        "verified": {"eq": True},
        "rentable": {"eq": True},
        "num_gpus": {"eq": 1},
        "gpu_ram": {"gte": 23000},
        "inet_down": {"gte": 600},
        "disk_space": {"gte": 80},
        "order": [["dph_total", "asc"]],
    }
    resp = requests.get(
        "https://console.vast.ai/api/v0/bundles",
        params={"q": json.dumps(q)},
        headers=HEADERS,
        timeout=15,
    )
    offers = resp.json().get("offers", [])
    # Filter for RTX 3090, RTX 4090, RTX A5000, RTX PRO 4000
    candidate_gpus = ["RTX 3090", "RTX 4090", "RTX A5000", "RTX PRO 4000", "RTX 3090 Ti"]
    for o in offers:
        gpu = o.get("gpu_name", "")
        if any(c.lower() in gpu.lower() for c in candidate_gpus):
            print(f"[+] Selected offer {o['id']}: {gpu} ({round(o['gpu_ram']/1024, 1)}GB VRAM) @ ${round(o['dph_total'], 3)}/hr in {o.get('geolocation')} (Inet down: {round(o['inet_down'])} Mbps)")
            return o
    if offers:
        top = offers[0]
        print(f"[+] Fallback to top offer {top['id']}: {top.get('gpu_name')} @ ${round(top['dph_total'], 3)}/hr")
        return top
    raise RuntimeError("No suitable GPU offers found on Vast.ai!")


def generate_onstart():
    return f"""#!/bin/bash
set -e
LOG_FILE="/var/log/instantid_test_onstart.log"
mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================================="
echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] Starting InstantID + DeepFace Standalone Run"
echo "=========================================================="

# 1. SSH setup
mkdir -p /root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINn4+UfzKdI4sp6f/NnYCCpn5ZbpRzQTvaA9TOSGBs6l contabo-server@nass-works.com" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
chmod 700 /root/.ssh

# 2. Workspace & System libraries
mkdir -p /workspace
cd /workspace
apt-get update -qq && apt-get install -y -qq --no-install-recommends libgl1 libglib2.0-0 curl > /dev/null 2>&1 || true

# 3. Install boto3
export PIP_BREAK_SYSTEM_PACKAGES=1
python3 -m pip install --no-cache-dir --break-system-packages boto3 botocore

# 4. Fetch python_engine package from R2
echo "[Step 1/5] Fetching python_engine.tar.gz from R2..."
python3 -c "
import os, boto3
s3 = boto3.client('s3',
    endpoint_url=os.environ.get('R2_ENDPOINT'),
    aws_access_key_id=os.environ.get('R2_ACCESS_KEY_ID'),
    aws_secret_access_key=os.environ.get('R2_SECRET_ACCESS_KEY'))
s3.download_file(os.environ.get('R2_BUCKET_NAME', 'cosmic-gen'), 'models/engine/python_engine.tar.gz', '/workspace/python_engine.tar.gz')
"
mkdir -p /workspace/python_engine
tar -xzf /workspace/python_engine.tar.gz -C /workspace/python_engine/
cd /workspace/python_engine

# 5. Install requirements
echo "[Step 2/5] Installing dependencies..."
python3 -m pip install --no-cache-dir --break-system-packages -r requirements.txt tf-keras keras onnxruntime-gpu || python3 -m pip install --no-cache-dir --break-system-packages -r requirements.txt tf-keras keras onnxruntime

# 6. Download models: sdxl-base-1.0 and instantid
echo "[Step 3/5] Downloading models (sdxl-base-1.0, instantid) from R2..."
python3 download_model.py sdxl-base-1.0 instantid

# 7. Run standalone test script
echo "[Step 4/5] Executing test_instantid_deepface.py..."
mkdir -p /workspace/outputs
python3 test_instantid_deepface.py --output_dir /workspace/outputs > /var/log/instantid_test.log 2>&1 || true

echo "=== Test script finished. Dumping tail of instantid_test.log: ==="
tail -n 40 /var/log/instantid_test.log || true

# 8. Upload results & logs back to R2
echo "[Step 5/5] Uploading artifacts back to Cloudflare R2..."
python3 -c "
import os, boto3
s3 = boto3.client('s3',
    endpoint_url=os.environ.get('R2_ENDPOINT'),
    aws_access_key_id=os.environ.get('R2_ACCESS_KEY_ID'),
    aws_secret_access_key=os.environ.get('R2_SECRET_ACCESS_KEY'))
bucket = os.environ.get('R2_BUCKET_NAME', 'cosmic-gen')

for root, dirs, files in os.walk('/workspace/outputs'):
    for f in files:
        full = os.path.join(root, f)
        rel = os.path.relpath(full, '/workspace/outputs')
        key = f'models/instantid_proof_outputs/{{rel}}'
        print(f'Uploading {{rel}} -> {{key}}')
        s3.upload_file(full, bucket, key)

if os.path.exists('/var/log/instantid_test.log'):
    s3.upload_file('/var/log/instantid_test.log', bucket, 'models/instantid_proof_outputs/instantid_test.log')
if os.path.exists('/var/log/instantid_test_onstart.log'):
    s3.upload_file('/var/log/instantid_test_onstart.log', bucket, 'models/instantid_proof_outputs/instantid_test_onstart.log')

# Write completion flag
s3.put_object(Bucket=bucket, Key='models/instantid_proof_outputs/COMPLETE', Body=b'DONE')
print('Upload complete and COMPLETE marker written.')
"

echo "=========================================================="
echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] Execution Completed Successfully"
echo "=========================================================="
"""


def rent_instance(offer_id, onstart_script):
    print(f"[*] Provisioning Vast.ai instance for offer {offer_id}...")
    payload = {
        "client_id": "me",
        "image": "pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime",
        "disk": 80,
        "env": {
            "R2_ENDPOINT": R2_ENDPOINT,
            "R2_BUCKET_NAME": R2_BUCKET_NAME,
            "R2_ACCESS_KEY_ID": R2_ACCESS_KEY_ID,
            "R2_SECRET_ACCESS_KEY": R2_SECRET_ACCESS_KEY,
            "AI_STUDIO_MODE": "cloud",
        },
        "onstart": onstart_script,
        "runtype": "ssh",
        "label": "instantid-deepface-proof",
    }
    resp = requests.put(
        f"https://console.vast.ai/api/v0/asks/{offer_id}/",
        json=payload,
        headers=HEADERS,
        timeout=20,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"Failed to create instance: {resp.status_code} {resp.text}")
    data = resp.json()
    contract_id = data.get("new_contract")
    print(f"[+] Rented contract #{contract_id} successfully.")
    return contract_id


def destroy_instance(contract_id):
    print(f"[*] Destroying Vast.ai instance contract #{contract_id}...")
    try:
        resp = requests.delete(
            f"https://console.vast.ai/api/v0/instances/{contract_id}/",
            headers=HEADERS,
            timeout=15,
        )
        print(f"[+] Instance #{contract_id} destroyed: {resp.status_code}")
    except Exception as e:
        print(f"[!] Error destroying instance: {e}")


def clean_r2_proof_outputs():
    print("[*] Cleaning previous test artifacts in R2 models/instantid_proof_outputs/...")
    objs = s3.list_objects_v2(Bucket=R2_BUCKET_NAME, Prefix="models/instantid_proof_outputs/")
    delete_keys = [{"Key": o["Key"]} for o in objs.get("Contents", [])]
    if delete_keys:
        s3.delete_objects(Bucket=R2_BUCKET_NAME, Delete={"Objects": delete_keys})
        print(f"[+] Cleaned {len(delete_keys)} old objects from R2.")


def check_r2_complete():
    try:
        s3.head_object(Bucket=R2_BUCKET_NAME, Key="models/instantid_proof_outputs/COMPLETE")
        return True
    except Exception:
        return False


def download_r2_artifacts():
    print(f"[*] Downloading test artifacts from R2 to {LOCAL_OUTPUT_DIR}...")
    objs = s3.list_objects_v2(Bucket=R2_BUCKET_NAME, Prefix="models/instantid_proof_outputs/")
    for o in objs.get("Contents", []):
        key = o["Key"]
        filename = key.replace("models/instantid_proof_outputs/", "")
        if not filename or filename == "COMPLETE":
            continue
        dest_file = LOCAL_OUTPUT_DIR / filename
        dest_file.parent.mkdir(parents=True, exist_ok=True)
        print(f"    Downloading {key} -> {dest_file} ({round(o['Size']/1024, 1)} KB)")
        s3.download_file(R2_BUCKET_NAME, key, str(dest_file))


def main():
    clean_r2_proof_outputs()
    offer = find_best_offer()
    offer_id = offer["id"]
    onstart = generate_onstart()

    contract_id = rent_instance(offer_id, onstart)

    start_time = time.time()
    max_wait_seconds = 1800  # 30 minutes max
    poll_interval = 15

    print(f"[*] Monitoring execution for contract #{contract_id}...")

    try:
        while time.time() - start_time < max_wait_seconds:
            elapsed = int(time.time() - start_time)

            # Check if COMPLETE in R2
            if check_r2_complete():
                print(f"\n[🎉] COMPLETE flag detected in R2 after {elapsed}s!")
                break

            # Poll Vast.ai instance status
            try:
                inst_resp = requests.get(
                    f"https://console.vast.ai/api/v0/instances/{contract_id}/",
                    headers=HEADERS,
                    timeout=10,
                )
                inst_data = inst_resp.json().get("instances", [{}])[0]
                status = inst_data.get("actual_status") or inst_data.get("cur_state")
                status_msg = inst_data.get("status_msg", "")
                print(f"[{elapsed}s] Instance #{contract_id}: {status} ({status_msg})", flush=True)

                if elapsed % 45 == 0 and elapsed > 0:
                    try:
                        log_resp = requests.get(
                            f"https://console.vast.ai/api/v0/instances/{contract_id}/logs/",
                            headers=HEADERS,
                            timeout=10,
                        )
                        logs = log_resp.json().get("logs", "")
                        if logs:
                            print("  [Remote Logs Tail]:")
                            for line in logs.strip().split("\n")[-6:]:
                                print(f"    {line}")
                    except Exception:
                        pass

                if status == "stopped" or status == "exited":
                    print(f"[!] Instance stopped prematurely. Status: {status}")
                    break
            except Exception as e:
                print(f"[{elapsed}s] Polling note: {e}")

            time.sleep(poll_interval)
        else:
            print("[!] Timeout reached while waiting for test run completion.")

    finally:
        # Download results if available
        download_r2_artifacts()

        # Destroy instance immediately
        destroy_instance(contract_id)

    print("\n==========================================================")
    print("Execution harness finished. Inspecting local results...")
    print("==========================================================")

    res_json = LOCAL_OUTPUT_DIR / "instantid_deepface_results.json"
    if res_json.exists():
        with open(res_json) as f:
            data = json.load(f)
        print(json.dumps(data, indent=2))
    else:
        print("[!] No instantid_deepface_results.json found.")
        log_file = LOCAL_OUTPUT_DIR / "instantid_test.log"
        if log_file.exists():
            print("\n--- instantid_test.log ---")
            print(log_file.read_text()[-2000:])
        onstart_log = LOCAL_OUTPUT_DIR / "instantid_test_onstart.log"
        if onstart_log.exists():
            print("\n--- instantid_test_onstart.log ---")
            print(onstart_log.read_text()[-2000:])


if __name__ == "__main__":
    main()
