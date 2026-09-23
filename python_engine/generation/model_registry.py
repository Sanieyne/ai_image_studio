"""Model catalog: family + generation defaults per checkpoint.

SDXL and FLUX need different pipelines and defaults, so the engine
looks up every model_id here instead of hardcoding SDXL assumptions.
"""
from __future__ import annotations

from typing import Dict, Optional

import os

# family: "sdxl" | "flux" | "zimage" | "qwen_image" | "wan" | "minimax" | "ltx" | "chatterbox" | "tryon" | "enhancer"
# mode: "image" | "video" | "voice" | "tryon" | "enhancer"
MODELS: Dict[str, dict] = {
    # --- Image Models ---
    "Qwen/Qwen-Image-2.1": {
        "family": "qwen_image",
        "mode": "image",
        "label": "Qwen-Image 2.1",
        "default_steps": 40,
        "default_guidance": 1.0,
        "gated": False,
        "note": "Qwen-Image 2.1 (7B Single-Stream DiT). Native 2K, 40 steps, transparent/RGBA support.",
    },
    "stabilityai/stable-diffusion-xl-base-1.0": {
        "family": "sdxl",
        "mode": "image",
        "label": "SDXL Base 1.0",
        "default_steps": 30,
        "default_guidance": 7.0,
        "gated": False,
        "note": "SDXL base foundation model (6.6GB). High-dynamic-range open diffusion.",
    },
    "black-forest-labs/FLUX.1-Kontext-dev": {
        "family": "flux",
        "mode": "image",
        "label": "FLUX.1 Kontext [dev]",
        "default_steps": 28,
        "default_guidance": 3.5,
        "gated": True,
        "note": "Instruction-guided image-to-image editing (12B). Active on RTX 3090.",
    },
    "Tongyi-MAI/Z-Image-Turbo": {
        "family": "zimage",
        "mode": "image",
        "label": "Z-Image Turbo",
        "default_steps": 9,
        "default_guidance": 0.0,
        "gated": False,
        "note": "Z-Image Turbo 6B single-stream DiT. 8 NFE, sub-second on H800, fits 16GB VRAM.",
    },

    # --- Video Models ---
    "Wan-AI/Wan2.1-T2V-1.3B-Diffusers": {
        "family": "wan",
        "mode": "video",
        "label": "Wan 2.1 T2V 1.3B",
        "default_steps": 30,
        "default_guidance": 5.0,
        "gated": False,
        "note": "Wan 2.1 Text-to-Video 1.3B compact model.",
    },
    "Wan-AI/Wan2.1-I2V-14B-480P-Diffusers": {
        "family": "wan",
        "mode": "video",
        "label": "Wan 2.1 I2V 14B",
        "default_steps": 30,
        "default_guidance": 5.0,
        "gated": False,
        "note": "Wan 2.1 Image-to-Video 14B foundation model (480P).",
    },
    "Wan-AI/Wan2.1-FLF2V-14B-720P-Diffusers": {
        "family": "wan",
        "mode": "video",
        "label": "Wan 2.1 FLF2V 14B",
        "default_steps": 30,
        "default_guidance": 5.0,
        "gated": False,
        "note": "Wan 2.1 First & Last Frame to Video (720P).",
    },
    "Wan-AI/Wan2.2-Animate-14B": {
        "family": "wan",
        "mode": "video",
        "label": "Wan 2.2 Animate 14B",
        "default_steps": 30,
        "default_guidance": 5.0,
        "gated": False,
        "note": "Wan 2.2 Character Animation & Motion Transfer.",
    },
    "MiniMaxAI/MiniMax-H3": {
        "family": "minimax",
        "mode": "video",
        "label": "MiniMax-H3 Video+Audio",
        "default_steps": 30,
        "default_guidance": 5.0,
        "gated": False,
        "note": "MiniMax-H3 Omni Video + Synchronized Audio Generation (33B).",
    },
    "Lightricks/LTX-Video": {
        "family": "ltx",
        "mode": "video",
        "label": "Lightricks LTX-Video",
        "default_steps": 30,
        "default_guidance": 3.0,
        "gated": False,
        "note": "Low-latency real-time video diffusion (2B).",
    },

    # --- Virtual Try-On ---
    "fashn-ai/fashn-vton-1.5": {
        "family": "tryon",
        "mode": "tryon",
        "label": "FASHN VTON 1.5",
        "default_steps": 30,
        "default_guidance": 1.5,
        "gated": False,
        "note": "FASHN VTON v1.5 pixel-space virtual try-on MMDiT (972M). Tops, bottoms, and one-pieces.",
    },

    # --- Voice Studio ---
    "ResembleAI/chatterbox": {
        "family": "chatterbox",
        "mode": "voice",
        "label": "Chatterbox TTS",
        "default_steps": 1,
        "default_guidance": 0.5,
        "gated": False,
        "note": "Resemble AI Chatterbox 500M TTS with exaggeration & voice cloning.",
    },
    "ResembleAI/chatterbox-multilingual": {
        "family": "chatterbox",
        "mode": "voice",
        "label": "Chatterbox Multilingual V3",
        "default_steps": 1,
        "default_guidance": 0.5,
        "gated": False,
        "note": "Chatterbox Multilingual V3 (23+ languages) with cross-lingual voice cloning.",
    },
    "BreezeBlue/Breeze-TTS-2": {
        "family": "chatterbox",
        "mode": "voice",
        "label": "Breeze TTS 2",
        "default_steps": 1,
        "default_guidance": 0.5,
        "gated": False,
        "note": "BreezeBlue Voice Design 3.4B TTS.",
    },

    # --- AI Enhancer ---
    "amd/realesrgan-x4plus": {
        "family": "enhancer",
        "mode": "enhancer",
        "label": "Real-ESRGAN x4plus",
        "default_steps": 1,
        "default_guidance": 1.0,
        "gated": False,
        "note": "4× Photo & Digital Art Blind Super-Resolution.",
    },
    "amd/realesrgan-anime-6b": {
        "family": "enhancer",
        "mode": "enhancer",
        "label": "Real-ESRGAN Anime 6B",
        "default_steps": 1,
        "default_guidance": 1.0,
        "gated": False,
        "note": "4× Anime & 2D Illustration Super-Resolution.",
    },
}


def family_for(model_id: str) -> str:
    """Return 'sdxl' for unknown ids so old behavior is preserved."""
    info = MODELS.get(model_id.strip())
    if info is None:
        return "sdxl"
    return info["family"]


def defaults_for(model_id: str) -> dict:
    info = MODELS.get(model_id.strip())
    if info is None:
        return {"default_steps": 30, "default_guidance": 7.0}
    return info


def display_label(model_id: str) -> str:
    info = MODELS.get(model_id.strip())
    return info["label"] if info else model_id


def is_model_downloaded(model_id: str) -> bool:
    """Check if model weights exist locally in cache or filesystem without downloading."""
    model_id = model_id.strip()
    if os.path.isdir(model_id) or os.path.isfile(model_id):
        return True

    # Check common Hugging Face cache directories
    candidate_roots = [
        os.environ.get("HF_HUB_CACHE"),
        os.environ.get("HF_HOME"),
        "/workspace/.hf_home/hub",
        "/workspace/.cache/huggingface/hub",
        os.path.expanduser("~/.cache/huggingface/hub"),
    ]

    folder_name = "models--" + model_id.replace("/", "--")
    for root in candidate_roots:
        if not root or not os.path.exists(root):
            continue
        model_dir = os.path.join(root, folder_name)
        if os.path.isdir(model_dir):
            snaps = os.path.join(model_dir, "snapshots")
            if os.path.isdir(snaps) and os.listdir(snaps):
                return True

    # Try huggingface_hub fast cache inspection
    try:
        from huggingface_hub import try_to_load_from_cache
        for test_file in ("model_index.json", "config.json", "model.safetensors", "diffusion_pytorch_model.safetensors"):
            if try_to_load_from_cache(model_id, test_file) is not None:
                return True
    except Exception:
        pass

    return False


def get_available_models(active_model_id: Optional[str] = None) -> list[dict]:
    """Return list of models with their live download status and active state."""
    results = []
    active_norm = (active_model_id or "").strip().lower()

    for mid, info in MODELS.items():
        is_dl = is_model_downloaded(mid)
        is_act = (mid.lower() == active_norm) or (info["label"].lower() == active_norm)
        # If it's active in memory, it is by definition downloaded
        if is_act:
            is_dl = True

        results.append({
            "id": mid,
            "label": info["label"],
            "family": info["family"],
            "mode": info.get("mode", "image"),
            "is_active": is_act,
            "is_downloaded": is_dl,
            "default_steps": info["default_steps"],
            "default_guidance": info["default_guidance"],
            "gated": info.get("gated", False),
            "note": info.get("note", ""),
        })

    return results

