"""FastAPI entrypoint. Run with: uvicorn app:app --host 127.0.0.1 --port 8000"""
from __future__ import annotations

import logging
import sys
import os

# Allow running as `python app.py` or `uvicorn app:app` from python_engine/.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# PyInstaller frozen app compatibility for packages that inspect metadata (diffusers, transformers)
try:
    import importlib.metadata
    _orig_metadata_version = importlib.metadata.version

    def _safe_metadata_version(distribution_name: str) -> str:
        try:
            return _orig_metadata_version(distribution_name)
        except (importlib.metadata.PackageNotFoundError, Exception):
            _fallbacks = {
                "requests": "2.31.0",
                "transformers": "4.44.0",
                "diffusers": "0.32.0",
                "torch": "2.2.0",
                "torchaudio": "2.2.0",
                "torchvision": "0.17.0",
                "accelerate": "0.33.0",
                "safetensors": "0.4.0",
                "pillow": "10.2.0",
                "timm": "0.9.16",
                "huggingface_hub": "0.24.0",
                "tokenizers": "0.19.1",
                "sentencepiece": "0.2.0",
                "filelock": "3.13.0",
                "numpy": "1.26.4",
                "packaging": "24.0",
                "regex": "2024.5.15",
            }
            return _fallbacks.get(distribution_name.lower(), "1.0.0")

    importlib.metadata.version = _safe_metadata_version
except Exception:
    pass

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.routes import router
from generation.pipeline import get_pipeline

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Warm up pipeline (loads SDXL or falls back to mock) so /health is honest.
    try:
        get_pipeline()
    except Exception as e:
        logging.getLogger(__name__).warning("[!] Pipeline warmup deferred (%s). Models will load on demand.", e)
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
    import uvicorn
    from config.config import settings

    uvicorn.run(app, host=settings.host, port=settings.port, timeout_keep_alive=65)

