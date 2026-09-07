"""Model catalog: family + generation defaults per checkpoint.

SDXL and FLUX need different pipelines and defaults, so the engine
looks up every model_id here instead of hardcoding SDXL assumptions.
"""
from __future__ import annotations

from typing import Dict, Optional

# family: "sdxl" | "flux"
MODELS: Dict[str, dict] = {
    # --- SDXL family (current live set) ---
    "stabilityai/stable-diffusion-xl-base-1.0": {
        "family": "sdxl",
        "label": "SDXL Base 1.0",
        "default_steps": 30,
        "default_guidance": 7.0,
        "gated": False,
    },
    "SG161222/RealVisXL_V4.0": {
        "family": "sdxl",
        "label": "RealVisXL V4.0",
        "default_steps": 30,
        "default_guidance": 7.0,
        "gated": False,
    },
    "RunDiffusion/Juggernaut-XL-v9": {
        "family": "sdxl",
        "label": "Juggernaut XL v9",
        "default_steps": 30,
        "default_guidance": 7.0,
        "gated": False,
    },
    "Lykon/dreamshaper-xl-1-0": {
        "family": "sdxl",
        "label": "DreamShaper XL",
        "default_steps": 30,
        "default_guidance": 7.0,
        "gated": False,
    },
    # --- FLUX family (new) ---
    "black-forest-labs/FLUX.1-schnell": {
        "family": "flux",
        "label": "FLUX.1-schnell",
        "default_steps": 4,
        "default_guidance": 0.0,  # distilled: guidance not used
        "gated": False,  # open weights
        "note": "Fast 4-step. Best first FLUX to download (~23GB).",
    },
    "black-forest-labs/FLUX.1-dev": {
        "family": "flux",
        "label": "FLUX.1-dev",
        "default_steps": 28,
        "default_guidance": 3.5,
        "gated": True,  # needs HF_TOKEN + license acceptance on HF
        "note": "Higher quality, slower. Accept license at the HF repo page.",
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
