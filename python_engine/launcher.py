"""
Launcher entrypoint for AI Image Studio Python Engine.
Freezes multiprocessing support and launches Uvicorn server.
"""
import os
import sys
import multiprocessing

# Add parent directory to sys.path so imports work properly
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

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

import uvicorn
from app import app

if __name__ == '__main__':
    multiprocessing.freeze_support()
    
    port = int(os.environ.get("ENGINE_PORT", 8000))
    host = os.environ.get("ENGINE_HOST", "127.0.0.1")
    
    print(f"=== Starting AI Image Studio Engine on http://{host}:{port} ===")
    uvicorn.run(app, host=host, port=port, log_level="info")
