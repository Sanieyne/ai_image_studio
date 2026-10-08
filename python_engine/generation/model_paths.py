"""Where model weights live, for every pipeline.

Model ids arrive in two spellings: catalog ids used by the backend and the
app ("sdxl-base-1.0") and Hugging Face repo ids used by the registry
("stabilityai/stable-diffusion-xl-base-1.0"). Both resolve to the same
downloaded folder:

    <models root>/<catalog id>/

The models root is AI_STUDIO_MODELS_DIR when set (the app and the cloud
instance set it), else the first existing of /workspace/models, /root/models,
~/models, ./models.

Weights are loaded from that folder. Downloading from the Hugging Face hub is a
fallback only where allowed: never on cloud instances (AI_STUDIO_MODE=cloud) or
when HF_HUB_OFFLINE=1.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Optional

# catalog id -> Hugging Face repo id (the registry's key)
CATALOG_TO_HF = {
    "sdxl-base-1.0": "stabilityai/stable-diffusion-xl-base-1.0",
    "flux-kontext-dev": "black-forest-labs/FLUX.1-Kontext-dev",
    "z-image-turbo": "Tongyi-MAI/Z-Image-Turbo",
    "qwen-image-2.1": "Qwen/Qwen-Image-2.1",
    "wan-2.1-t2v-1.3b": "Wan-AI/Wan2.1-T2V-1.3B-Diffusers",
    "wan-2.1-i2v-14b": "Wan-AI/Wan2.1-I2V-14B-480P-Diffusers",
    "wan-2.2-animate-14b": "Wan-AI/Wan2.2-Animate-14B-Diffusers",
    "chatterbox-tts": "ResembleAI/chatterbox",
}
HF_TO_CATALOG = {hf.lower(): cid for cid, hf in CATALOG_TO_HF.items()}

_DEFAULT_ROOTS = (
    Path("/workspace/models"),
    Path("/root/models"),
    Path.home() / "models",
    Path("./models"),
)


def models_root() -> Path:
    env = os.environ.get("AI_STUDIO_MODELS_DIR", "").strip()
    if env:
        return Path(env).expanduser()
    for p in _DEFAULT_ROOTS:
        if p.exists():
            return p
    return _DEFAULT_ROOTS[0]


def catalog_id(model_id: str) -> str:
    """'stabilityai/stable-diffusion-xl-base-1.0' -> 'sdxl-base-1.0'; catalog ids unchanged."""
    clean = model_id.strip()
    return HF_TO_CATALOG.get(clean.lower(), clean)


def registry_id(model_id: str) -> str:
    """The id generation/model_registry.py knows (Hugging Face repo id when there is one)."""
    clean = model_id.strip()
    return CATALOG_TO_HF.get(clean, clean)


def model_dir(model_id: str) -> Optional[Path]:
    """The downloaded folder for a model, or None if it is not there (or empty)."""
    path = models_root() / catalog_id(model_id)
    try:
        if path.is_dir() and any(path.iterdir()):
            return path
    except OSError:
        pass
    return None


def hub_downloads_allowed() -> bool:
    if os.environ.get("AI_STUDIO_MODE", "").strip().lower() == "cloud":
        return False
    return os.environ.get("HF_HUB_OFFLINE", "").strip() not in ("1", "true", "True")


class ModelNotDownloadedError(FileNotFoundError):
    pass


def load_source(model_id: str) -> str:
    """What to pass to from_pretrained(): the local folder, or the hub id where allowed.

    Raises ModelNotDownloadedError when the model is not downloaded and the hub
    may not be used.
    """
    if os.path.exists(model_id):
        return model_id  # an explicit file or folder path
    local = model_dir(model_id)
    if local is not None:
        return str(local)
    if hub_downloads_allowed():
        return registry_id(model_id)
    raise ModelNotDownloadedError(
        f"Model '{catalog_id(model_id)}' is not downloaded (expected in {models_root() / catalog_id(model_id)})."
    )
