"""Central configuration for the Python engine."""
from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass
class Settings:
    host: str = os.environ.get("AI_STUDIO_HOST", "127.0.0.1")
    port: int = int(os.environ.get("AI_STUDIO_PORT", "8000"))
    # HuggingFace model id for SDXL. Override without code changes:
    #   AI_STUDIO_MODEL_ID="stabilityai/stable-diffusion-xl-base-1.0"
    model_id: str = os.environ.get(
        "AI_STUDIO_MODEL_ID", "stabilityai/stable-diffusion-xl-base-1.0"
    )
    # Force mock mode even if diffusers/torch are installed. Useful for UI dev.
    # Set AI_STUDIO_MOCK=1 to force, =0 to try real weights.
    force_mock: bool = os.environ.get("AI_STUDIO_MOCK", "").strip() == "1"
    # Where to cache HF weights (optional).
    hf_cache_dir: str | None = os.environ.get("HF_HUB_CACHE") or None


settings = Settings()
