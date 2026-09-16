"""Model catalog: family + generation defaults per checkpoint.

SDXL and FLUX need different pipelines and defaults, so the engine
looks up every model_id here instead of hardcoding SDXL assumptions.
"""
from __future__ import annotations

from typing import Dict, Optional

# family: "sdxl" | "flux" | "zimage"
MODELS: Dict[str, dict] = {
    "Tongyi-MAI/Z-Image-Turbo": {
        "family": "zimage",
        "label": "Z-Image Turbo",
        "default_steps": 9,
        "default_guidance": 0.0,
        "gated": False,
        "note": "Z-Image Turbo 6B single-stream DiT. 8 NFE, sub-second on H800, fits 16GB VRAM.",
    },
    "black-forest-labs/FLUX.1-Kontext-dev": {
        "family": "flux",
        "label": "FLUX.1 Kontext [dev]",
        "default_steps": 28,
        "default_guidance": 3.5,
        "gated": True,
        "note": "Instruction-guided image-to-image editing (12B). Active on RTX 3090.",
    },
    "stabilityai/stable-diffusion-xl-base-1.0": {
        "family": "sdxl",
        "label": "SDXL Base 1.0",
        "default_steps": 30,
        "default_guidance": 7.0,
        "gated": False,
        "note": "SDXL base foundation model (6.6GB). Cached on GPU.",
    },
    "ResembleAI/chatterbox": {
        "family": "chatterbox",
        "label": "Chatterbox TTS",
        "default_steps": 1,
        "default_guidance": 0.5,
        "gated": False,
        "note": "Resemble AI Chatterbox 500M TTS with exaggeration & voice cloning.",
    },
    "ResembleAI/chatterbox-multilingual": {
        "family": "chatterbox",
        "label": "Chatterbox Multilingual V3",
        "default_steps": 1,
        "default_guidance": 0.5,
        "gated": False,
        "note": "Chatterbox Multilingual V3 (23+ languages) with cross-lingual voice cloning.",
    },
    "fashn-ai/fashn-vton-1.5": {
        "family": "tryon",
        "label": "FASHN VTON 1.5",
        "default_steps": 30,
        "default_guidance": 1.5,
        "gated": False,
        "note": "FASHN VTON v1.5 pixel-space virtual try-on MMDiT (972M). Tops, bottoms, and one-pieces.",
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
