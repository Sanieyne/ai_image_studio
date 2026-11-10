"""FastAPI entrypoint. Run with: uvicorn app:app --host 127.0.0.1 --port 8000"""
from __future__ import annotations

import logging
import sys
import os

os.environ["PYTORCH_CUDA_ALLOC_CONF"] = "expandable_segments:True"

# Hydrate environment variables from container PID 1 or /etc/environment if running in Docker / Vast.ai
for _env_path in ("/proc/1/environ", "/etc/environment"):
    try:
        if os.path.exists(_env_path):
            with open(_env_path, "rb") as _f:
                _content = _f.read()
            _chunks = _content.split(b"\0") if b"\0" in _content else _content.split(b"\n")
            for _chunk in _chunks:
                try:
                    _line = _chunk.decode("utf-8", errors="ignore").strip()
                    if not _line or _line.startswith("#") or "=" not in _line:
                        continue
                    _k, _v = _line.split("=", 1)
                    _k = _k.strip()
                    _v = _v.strip().strip("'\"")
                    if _k and _k not in os.environ:
                        os.environ[_k] = _v
                except Exception:
                    pass
    except Exception:
        pass

# Allow running as `python app.py` or `uvicorn app:app` from python_engine/.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


# PyInstaller frozen app compatibility for packages that inspect metadata (diffusers, transformers)
if getattr(sys, "frozen", False):
    try:
        import importlib.metadata
        _orig_metadata_version = importlib.metadata.version

        def _safe_metadata_version(distribution_name: str) -> str:
            try:
                return _orig_metadata_version(distribution_name)
            except (importlib.metadata.PackageNotFoundError, Exception):
                _fallbacks = {
                    "requests": "2.34.0",
                    "transformers": "5.17.0",
                    "diffusers": "0.41.0.dev0",
                    "torch": "2.11.0",
                    "torchaudio": "2.11.0",
                    "torchvision": "0.26.0",
                    "accelerate": "1.4.0",
                    "safetensors": "0.8.0",
                    "pillow": "12.0.0",
                    "timm": "1.0.15",
                    "huggingface_hub": "1.32.0",
                    "tokenizers": "0.22.0",
                    "sentencepiece": "0.2.0",
                    "filelock": "3.32.0",
                    "numpy": "2.5.0",
                    "packaging": "26.0",
                    "regex": "2026.9.10",
                }
                key = distribution_name.lower()
                if key in _fallbacks:
                    return _fallbacks[key]
                # Unknown packages stay "not installed": claiming a version for an
                # absent package (e.g. optree) makes torch/transformers import it and fail.
                raise

        importlib.metadata.version = _safe_metadata_version
    except Exception:
        pass

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.routes import router

logging.basicConfig(level=logging.INFO)

# Released together with the app (flutter_app/lib/app_version.dart).
ENGINE_VERSION = "0.4.1"


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Answer /health immediately; load only the models the user selected, in the background."""
    from generation.model_status import model_status_manager

    selected_env = os.environ.get("AI_STUDIO_SELECTED_MODELS", "").strip()
    model_ids = [m.strip() for m in selected_env.replace(",", " ").split() if m.strip()]
    if model_ids:
        # queued -> downloading -> loading -> ready, one model at a time, off the event loop.
        model_status_manager.initialize_models(model_ids)
        model_status_manager.start_lifecycle_worker(model_ids)

    # Discover any models already downloaded on disk
    try:
        from download_model import MODEL_CATALOG, get_default_models_root
        models_root = get_default_models_root()
        for mid, cat in MODEL_CATALOG.items():
            target_sub = cat.get("target_subpath", mid)
            model_dir = models_root / target_sub
            if model_dir.exists() and any(model_dir.iterdir()):
                if not model_status_manager.get_status(mid):
                    model_status_manager.update_status(mid, "ready", progress_percent=100.0, loaded_in_vram=False)
    except Exception as e:
        logging.warning("Error discovering local models on startup: %s", e)
    # Nothing selected: nothing is loaded until a request needs it.
    yield


app = FastAPI(title="AI Image Studio Engine", version=ENGINE_VERSION, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        from self_test import main as self_test_main

        sys.exit(self_test_main([a for a in sys.argv[1:] if a != "--self-test"]))

    import uvicorn
    from config.config import settings

    uvicorn.run(app, host=settings.host, port=settings.port, timeout_keep_alive=65)

