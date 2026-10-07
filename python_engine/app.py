"""FastAPI entrypoint. Run with: uvicorn app:app --host 127.0.0.1 --port 8000"""
from __future__ import annotations

import logging
import sys
import os

os.environ["PYTORCH_CUDA_ALLOC_CONF"] = "expandable_segments:True"

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
                return _fallbacks.get(distribution_name.lower(), "1.0.0")

        importlib.metadata.version = _safe_metadata_version
    except Exception:
        pass

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.routes import router

logging.basicConfig(level=logging.INFO)


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
    # Nothing selected: nothing is loaded until a request needs it.
    yield


app = FastAPI(title="AI Image Studio Engine", version="0.1.0", lifespan=lifespan)

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

