#!/bin/bash
# Startup script for rented GPU instances (sent as the Vast.ai onstart command).
#
# 1. Download the engine package, 2. install the locked package set,
# 3. run the engine self-test, 4. start the engine on port 8000.
# If any step fails, a tiny server answers GET /health on port 8000 with
#   {"status": "failed", "reason": "..."}
# so the backend stops the instance at once and tells the user why.
#
# No `set -e`: every failure is handled and reported.
set -uo pipefail
mkdir -p /var/log /workspace
exec > >(tee -a /var/log/ai_studio_onstart.log) 2>&1
cd /workspace

export AI_STUDIO_MODE=cloud            # engine: never download from Hugging Face
export HF_HUB_OFFLINE=1
export AI_STUDIO_MODELS_DIR=/workspace/models
export AI_STUDIO_REQUIRE_CUDA=1         # self-test: this GPU must be supported by torch
export AI_STUDIO_HOST=0.0.0.0
export AI_STUDIO_PORT=8000
export PIP_BREAK_SYSTEM_PACKAGES=1
export PIP_DISABLE_PIP_VERSION_CHECK=1
mkdir -p "$AI_STUDIO_MODELS_DIR"

stage() { echo "[$(date -u +%H:%M:%S)] [STAGE] $*"; }

cat > /workspace/failure_server.py <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
reason = open(sys.argv[1], encoding="utf-8", errors="replace").read().strip()[:2000] or "Engine failed to start."
body = json.dumps({"status": "failed", "reason": reason, "model_loaded": False, "models": []}).encode()
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        ok = self.path.split("?")[0] in ("/health", "/ping")
        self.send_response(200 if ok else 404)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if ok:
            self.wfile.write(body)
    def log_message(self, *a):
        pass
HTTPServer(("0.0.0.0", 8000), H).serve_forever()
PY

fail() {
  echo "[FAILED] $1"
  printf '%s\n' "$1" > /workspace/engine_failure.txt
  nohup python3 /workspace/failure_server.py /workspace/engine_failure.txt > /var/log/ai_engine.log 2>&1 &
  exit 0
}

last_lines() { tail -n "${2:-5}" "$1" 2>/dev/null | tr '\n' ' ' | cut -c1-600; }

stage "1/4 Downloading the engine package"
python3 -m pip install -q --no-cache-dir boto3 > /var/log/pip_boto3.log 2>&1 \
  || fail "Could not install the download tool (boto3): $(last_lines /var/log/pip_boto3.log)"
python3 - <<'PY' > /var/log/engine_download.log 2>&1 || fail "Could not download the engine package: $(last_lines /var/log/engine_download.log)"
import os, boto3
s3 = boto3.client("s3", endpoint_url=os.environ["R2_ENDPOINT"],
                  aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
                  aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"], region_name="auto")
s3.download_file(os.environ.get("R2_BUCKET_NAME", "cosmic-gen"), "models/engine/python_engine.tar.gz",
                 "/workspace/python_engine.tar.gz")
PY
mkdir -p /workspace/python_engine
tar -xzf /workspace/python_engine.tar.gz -C /workspace/python_engine \
  || fail "The engine package could not be unpacked."
rm -f /workspace/python_engine.tar.gz
cd /workspace/python_engine
# Handle nested python_engine/ directory if present in tarball
if [ -d python_engine ] && [ -f python_engine/requirements-cloud.lock ]; then
  cp -rn python_engine/* . 2>/dev/null || true
fi
[ -f requirements-cloud.lock ] && [ -f constraints-cloud.txt ] && [ -f self_test.py ] \
  || fail "The engine package is outdated (no requirements-cloud.lock / self_test.py). Upload a new package."

stage "2/4 Installing engine packages (locked versions)"
python3 -m pip install --no-cache-dir -r requirements-cloud.lock -c constraints-cloud.txt \
    --extra-index-url https://download.pytorch.org/whl/cu128 > /var/log/pip_engine.log 2>&1 \
  || fail "Installing engine packages failed: $(last_lines /var/log/pip_engine.log 8)"
python3 -m pip install --no-cache-dir --no-deps chatterbox-tts==0.1.7 >> /var/log/pip_engine.log 2>&1 \
  || fail "Installing the voice package failed: $(last_lines /var/log/pip_engine.log)"
python3 -m pip install --no-cache-dir opencv-python-headless insightface onnxruntime-gpu >> /var/log/pip_engine.log 2>&1 \
  || python3 -m pip install --no-cache-dir opencv-python-headless insightface onnxruntime >> /var/log/pip_engine.log 2>&1 \
  || echo "[WARN] Deep-Live-Cam face package installation completed with warnings."

stage "3/4 Engine self-test"
python3 self_test.py --json > /workspace/self_test.json 2>/var/log/self_test.err
if [ $? -ne 0 ]; then
  reason=$(python3 -c "import json;r=json.load(open('/workspace/self_test.json'));print('; '.join(r['failures']))" 2>/dev/null)
  fail "Engine self-test failed: ${reason:-$(last_lines /var/log/self_test.err)}"
fi

stage "4/4 Starting the engine on port 8000 (models: ${AI_STUDIO_SELECTED_MODELS:-none})"
nohup python3 app.py > /var/log/ai_engine.log 2>&1 &
echo "[OK] Engine started with PID $!"
