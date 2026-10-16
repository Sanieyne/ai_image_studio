#!/usr/bin/env python3
"""Automated Vast.ai execution harness for Synthetic Female Voice Generation.

1. Bundles and uploads updated python_engine.tar.gz to R2.
2. Identifies and rents a cheap, fast RTX 3090 / 4090 / A5000 / RTX 8000 GPU instance.
3. Injects custom onstart script to:
   - Install dependencies for Breeze-TTS-2 and Chatterbox-TTS
   - Download model weights from R2 via download_model.py
   - Execute run_voice_generation_worker.py to generate 6 synthetic female clips
   - Upload audio files and logs to R2 under audio-templates/
   - Write COMPLETE marker
4. Polls until completion.
5. Immediately destroys the Vast.ai instance.
6. Downloads audio clips to /var/www/instantid/audio-templates/ and /root/audio_templates/.
"""

import os
import sys
import time
import json
import tarfile
import tempfile
import requests
from pathlib import Path
import boto3

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

LOCAL_OUTPUT_DIR = Path("/root/audio_templates")
WEB_OUTPUT_DIR = Path("/var/www/instantid/audio-templates")
LOCAL_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
WEB_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

s3 = boto3.client(
    "s3",
    endpoint_url=R2_ENDPOINT,
    aws_access_key_id=R2_ACCESS_KEY_ID,
    aws_secret_access_key=R2_SECRET_ACCESS_KEY,
)

HEADERS = {"Authorization": f"Bearer {VASTAI_API_KEY}"}


def bundle_and_upload_engine():
    print("[*] Packaging python_engine into tar.gz and uploading to R2...")
    engine_dir = Path("/root/projects/ai_image_studio/python_engine")
    with tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False) as tmp:
        tmp_path = Path(tmp.name)

    try:
        with tarfile.open(tmp_path, "w:gz") as tar:
            for item in engine_dir.iterdir():
                if item.name in [".git", "__pycache__", "venv", ".venv", "models"]:
                    continue
                tar.add(item, arcname=item.name)
        size_mb = round(tmp_path.stat().st_size / (1024 * 1024), 2)
        print(f"[+] Packaged {size_mb} MB. Uploading to R2 models/engine/python_engine.tar.gz...")
        s3.upload_file(str(tmp_path), R2_BUCKET_NAME, "models/engine/python_engine.tar.gz")
        print("[+] Upload of python_engine.tar.gz complete.")
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def find_best_offer():
    print("[*] Searching for suitable Vast.ai GPU offers (20GB+ VRAM, >600 Mbps down, data cost <= $3/TB)...")
    q = {
        "verified": {"eq": True},
        "rentable": {"eq": True},
        "num_gpus": {"eq": 1},
        "gpu_ram": {"gte": 20000},
        "inet_down": {"gte": 600},
        "inet_down_cost": {"lte": 0.003},
        "disk_space": {"gte": 65},
        "order": [["dph_total", "asc"]],
    }
    resp = requests.get(
        "https://console.vast.ai/api/v0/bundles",
        params={"q": json.dumps(q)},
        headers=HEADERS,
        timeout=15,
    )
    offers = resp.json().get("offers", [])
    candidate_gpus = ["RTX 3090", "RTX 4090", "RTX A5000", "RTX 4000", "RTX 8000", "A10", "RTX 3090 Ti"]
    fast_regions = ["US", "CA", "ES", "DE", "FR", "GB", "NL", "RO", "BG", "PL", "NO", "SE", "DK", "IE"]
    for o in offers:
        geo = o.get("geolocation", "")
        if not any(r in geo for r in fast_regions):
            continue
        rel = o.get("reliability2", o.get("reliability", 0))
        if rel < 0.98:
            continue
        gpu = o.get("gpu_name", "")
        if any(c.lower() in gpu.lower() for c in candidate_gpus):
            tb_cost = round(o.get("inet_down_cost", 0) * 1024, 2)
            print(f"[+] Selected offer {o['id']}: {gpu} ({round(o['gpu_ram']/1024, 1)}GB VRAM) @ ${round(o['dph_total'], 3)}/hr | Data: ${tb_cost}/TB in {geo} (Down: {round(o['inet_down'])} Mbps)")
            return o
    if offers:
        for o in offers:
            geo = o.get("geolocation", "")
            if any(r in geo for r in fast_regions):
                tb_cost = round(o.get("inet_down_cost", 0) * 1024, 2)
                print(f"[+] Fallback to offer {o['id']}: {o.get('gpu_name')} @ ${round(o['dph_total'], 3)}/hr | Data: ${tb_cost}/TB in {geo}")
                return o
    raise RuntimeError("No suitable GPU offers found on Vast.ai!")


def generate_onstart():
    return f"""#!/bin/bash
set -e
LOG_FILE="/var/log/voice_gen_onstart.log"
mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

export R2_ENDPOINT="{R2_ENDPOINT}"
export R2_BUCKET_NAME="{R2_BUCKET_NAME}"
export R2_ACCESS_KEY_ID="{R2_ACCESS_KEY_ID}"
export R2_SECRET_ACCESS_KEY="{R2_SECRET_ACCESS_KEY}"
export PIP_BREAK_SYSTEM_PACKAGES=1

echo "=========================================================="
echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] Starting Synthetic Female Voice Generation Run"
echo "=========================================================="

# 1. Workspace & System libraries
mkdir -p /workspace
cd /workspace
apt-get update -qq && apt-get install -y -qq --no-install-recommends ffmpeg curl git > /dev/null 2>&1 || true

# 2. Install boto3
export PIP_BREAK_SYSTEM_PACKAGES=1
python3 -m pip install --no-cache-dir --break-system-packages boto3 botocore

# 3. Fetch python_engine package from R2 and cached Breeze audio templates
echo "[Step 1/5] Fetching python_engine.tar.gz and Breeze reference clips from R2..."
python3 -c "
import os, boto3
s3 = boto3.client('s3',
    endpoint_url=os.environ.get('R2_ENDPOINT'),
    aws_access_key_id=os.environ.get('R2_ACCESS_KEY_ID'),
    aws_secret_access_key=os.environ.get('R2_SECRET_ACCESS_KEY'))
bucket = os.environ.get('R2_BUCKET_NAME', 'cosmic-gen')
s3.download_file(bucket, 'models/engine/python_engine.tar.gz', '/workspace/python_engine.tar.gz')

os.makedirs('/workspace/outputs/audio-templates/breeze-tts-2', exist_ok=True)
for i in [1, 2, 3]:
    for ext in ['wav', 'mp3']:
        key = f'audio-templates/breeze-tts-2/{{i}}.{{ext}}'
        dest = f'/workspace/outputs/audio-templates/breeze-tts-2/{{i}}.{{ext}}'
        try:
            s3.download_file(bucket, key, dest)
            print(f'Cached: {{key}} -> {{dest}}')
        except Exception as e:
            print(f'Could not download {{key}}: {{e}}')
"
mkdir -p /workspace/python_engine
tar -xzf /workspace/python_engine.tar.gz -C /workspace/python_engine/
cd /workspace/python_engine

# 4. Install dependencies
echo "[Step 2/5] Installing dependencies including diffusers..."
python3 -m pip install --no-cache-dir --break-system-packages \
    qwen-tts==0.1.1 \
    transformers==4.57.3 \
    soundfile>=0.12.1 \
    accelerate>=1.0.0 \
    diffusers>=0.29.0 \
    librosa==0.11.0 \
    s3tokenizer \
    resemble-perth>=1.0.0 \
    conformer==0.3.2 \
    pyloudnorm \
    omegaconf \
    pykakasi==2.3.0 \
    spacy-pkuseg

python3 -m pip install --no-cache-dir --break-system-packages --no-deps chatterbox-tts==0.1.7

# 5. Download model weights from R2 (chatterbox-tts)
echo "[Step 3/5] Downloading chatterbox-tts model from R2..."
python3 download_model.py chatterbox-tts

# 6. Run worker generation script
echo "[Step 4/5] Executing run_voice_generation_worker.py..."
python3 run_voice_generation_worker.py > /var/log/voice_worker.log 2>&1 || true

echo "=== Generation finished. Dumping tail of voice_worker.log: ==="
tail -n 40 /var/log/voice_worker.log || true

# 7. Upload results back to Cloudflare R2
echo "[Step 5/5] Uploading artifacts back to Cloudflare R2..."
python3 -c "
import os, boto3
s3 = boto3.client('s3',
    endpoint_url=os.environ.get('R2_ENDPOINT'),
    aws_access_key_id=os.environ.get('R2_ACCESS_KEY_ID'),
    aws_secret_access_key=os.environ.get('R2_SECRET_ACCESS_KEY'))
bucket = os.environ.get('R2_BUCKET_NAME', 'cosmic-gen')

for root, dirs, files in os.walk('/workspace/outputs/audio-templates'):
    for f in files:
        full = os.path.join(root, f)
        rel = os.path.relpath(full, '/workspace/outputs/audio-templates')
        key = f'audio-templates/{{rel}}'
        print(f'Uploading {{rel}} -> {{key}}')
        s3.upload_file(full, bucket, key)

if os.path.exists('/var/log/voice_worker.log'):
    s3.upload_file('/var/log/voice_worker.log', bucket, 'audio-templates/voice_worker.log')
if os.path.exists('/var/log/voice_gen_onstart.log'):
    s3.upload_file('/var/log/voice_gen_onstart.log', bucket, 'audio-templates/voice_gen_onstart.log')

s3.put_object(Bucket=bucket, Key='audio-templates/COMPLETE', Body=b'DONE')
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
        "disk": 75,
        "env": {
            "R2_ENDPOINT": R2_ENDPOINT,
            "R2_BUCKET_NAME": R2_BUCKET_NAME,
            "R2_ACCESS_KEY_ID": R2_ACCESS_KEY_ID,
            "R2_SECRET_ACCESS_KEY": R2_SECRET_ACCESS_KEY,
            "AI_STUDIO_MODE": "cloud",
        },
        "onstart": onstart_script,
        "runtype": "ssh",
        "label": "voice-generation-templates",
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
    for attempt in range(3):
        try:
            resp = requests.delete(
                f"https://console.vast.ai/api/v0/instances/{contract_id}/",
                headers=HEADERS,
                timeout=15,
            )
            print(f"[+] Instance #{contract_id} destroy response: {resp.status_code}")
            if resp.status_code in (200, 204):
                return
        except Exception as e:
            print(f"[!] Destroy attempt {attempt+1} failed: {e}")
        time.sleep(2)


def clean_r2_templates():
    print("[*] Cleaning previous chatterbox templates in R2 audio-templates/chatterbox-tts/...")
    objs = s3.list_objects_v2(Bucket=R2_BUCKET_NAME, Prefix="audio-templates/")
    delete_keys = []
    for o in objs.get("Contents", []):
        k = o["Key"]
        if "chatterbox-tts" in k or k.endswith("COMPLETE") or "worker.log" in k:
            delete_keys.append({"Key": k})
    if delete_keys:
        s3.delete_objects(Bucket=R2_BUCKET_NAME, Delete={"Objects": delete_keys})
        print(f"[+] Cleaned {len(delete_keys)} old objects from R2.")


def check_r2_complete():
    try:
        s3.head_object(Bucket=R2_BUCKET_NAME, Key="audio-templates/COMPLETE")
        return True
    except Exception:
        return False


def download_all_artifacts():
    print("\n[*] Downloading all generated audio artifacts from R2...")
    objs = s3.list_objects_v2(Bucket=R2_BUCKET_NAME, Prefix="audio-templates/")
    contents = objs.get("Contents", [])
    downloaded = []
    for item in contents:
        key = item["Key"]
        if key.endswith("COMPLETE"):
            continue
        rel_path = key.removeprefix("audio-templates/").lstrip("/")
        local_path = LOCAL_OUTPUT_DIR / rel_path
        web_path = WEB_OUTPUT_DIR / rel_path

        local_path.parent.mkdir(parents=True, exist_ok=True)
        web_path.parent.mkdir(parents=True, exist_ok=True)

        s3.download_file(R2_BUCKET_NAME, key, str(local_path))
        s3.download_file(R2_BUCKET_NAME, key, str(web_path))
        downloaded.append((rel_path, item["Size"]))
        print(f"  Downloaded: {rel_path} ({round(item['Size']/1024, 1)} KB)")
    return downloaded


def main():
    print("=" * 70)
    print("VAST.AI SYNTHETIC FEMALE VOICE REFERENCE GENERATION HARNESS")
    print("=" * 70)

    # 1. Package and upload engine code
    bundle_and_upload_engine()

    # 2. Clean R2 output prefix
    clean_r2_templates()

    # 3. Find offer
    offer = find_best_offer()
    offer_id = offer["id"]

    # 4. Generate onstart script
    onstart_script = generate_onstart()

    # 5. Rent instance
    contract_id = rent_instance(offer_id, onstart_script)

    t0 = time.time()
    max_wait_seconds = 1200  # 20 minutes max
    poll_interval = 20

    try:
        print(f"\n[*] Polling R2 for completion (Contract #{contract_id})...")
        while time.time() - t0 < max_wait_seconds:
            if check_r2_complete():
                print(f"\n[+] COMPLETE marker detected in R2! Total elapsed: {int(time.time() - t0)}s")
                break

            # Check instance status
            try:
                inst_resp = requests.get("https://console.vast.ai/api/v1/instances", headers=HEADERS, timeout=10)
                instances = inst_resp.json().get("instances", [])
                matching = next((i for i in instances if i.get("id") == contract_id), None)
                if matching:
                    status = matching.get("actual_status", matching.get("cur_state", "unknown"))
                    print(f"  [{int(time.time() - t0)}s] Instance #{contract_id} status: {status}...")
                else:
                    print(f"  [{int(time.time() - t0)}s] Waiting for instance status...")
            except Exception as e:
                print(f"  [!] Poll warning: {e}")

            time.sleep(poll_interval)
        else:
            raise TimeoutError("Execution timed out before COMPLETE marker was written to R2!")

    finally:
        # IMMEDIATELY TERMINATE INSTANCE
        print("\n" + "=" * 70)
        print(f"TERMINATING VAST.AI INSTANCE CONTRACT #{contract_id} TO PREVENT SPEND")
        print("=" * 70)
        destroy_instance(contract_id)

    # Download artifacts
    downloaded = download_all_artifacts()

    # Check worker log
    worker_log_path = LOCAL_OUTPUT_DIR / "voice_worker.log"
    if worker_log_path.exists():
        print("\n=== Tail of voice_worker.log ===")
        with open(worker_log_path) as f:
            lines = f.readlines()
            for l in lines[-40:]:
                print(l, end="")

    print("\n[+] Done. Artifacts saved locally and published to web directory.")


if __name__ == "__main__":
    main()
