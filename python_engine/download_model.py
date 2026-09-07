#!/usr/bin/env python3
"""Utility script to pre-download SDXL models to local cache on Vast.ai."""
import os
import sys

if len(sys.argv) < 2:
    print("Usage: python3 download_model.py <model_repo_id>")
    print("Example: python3 download_model.py stabilityai/stable-diffusion-xl-base-1.0")
    print("Example: python3 download_model.py stabilityai/stable-diffusion-xl-base-0.9")
    sys.exit(1)

model_id = sys.argv[1].strip()
print(f"[*] Downloading '{model_id}'...")

try:
    import torch
    from diffusers import StableDiffusionXLPipeline
except ImportError:
    print("[!] diffusers/torch not installed. Run: pip install -r requirements.txt")
    sys.exit(1)

hf_token = os.environ.get("HF_TOKEN") or None
try:
    pipe = StableDiffusionXLPipeline.from_pretrained(
        model_id,
        torch_dtype=torch.float16,
        use_safetensors=True,
        variant="fp16",
        token=hf_token,
    )
    print(f"[OK] Successfully downloaded and validated '{model_id}'!")
except Exception as e:
    print(f"[ERROR] Failed to download '{model_id}': {e}")
    sys.exit(1)
