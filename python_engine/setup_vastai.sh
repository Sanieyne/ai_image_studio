#!/usr/bin/env bash
# setup_vastai.sh - Quickstart script for Vast.ai GPU instances
set -e

echo "=== AI Image Studio - Vast.ai GPU Engine Setup ==="

# 1. Update pip and install requirements
echo "[1/3] Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# 2. Verify CUDA availability
echo "[2/3] Checking PyTorch CUDA status..."
python3 -c "import torch; print(f'PyTorch: {torch.__version__}, CUDA available: {torch.cuda.is_available()}, Device: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"None\"}')"

# 3. Start engine
echo "[3/3] Starting FastAPI engine on 0.0.0.0:8000..."
export AI_STUDIO_HOST="0.0.0.0"
export AI_STUDIO_PORT="8000"
export AI_STUDIO_MOCK="0"

if [ -n "$HF_TOKEN" ]; then
    echo "Hugging Face token detected in environment."
fi

python3 app.py
