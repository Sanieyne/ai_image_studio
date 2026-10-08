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
                # Same versions as requirements-windows.txt (used only if a
                # package's metadata was not bundled).
                "requests": "2.34.2",
                "transformers": "5.19.0",
                "diffusers": "0.41.0",
                "torch": "2.11.0",
                "torchaudio": "2.11.0",
                "torchvision": "0.26.0",
                "accelerate": "1.15.0",
                "safetensors": "0.8.0",
                "pillow": "12.3.0",
                "huggingface_hub": "1.33.0",
                "tokenizers": "0.23.2",
                "sentencepiece": "0.2.2",
                "numpy": "2.5.2",
            }
            return _fallbacks.get(distribution_name.lower(), "1.0.0")

    importlib.metadata.version = _safe_metadata_version
except Exception:
    pass

if __name__ == '__main__' and '--self-test' in sys.argv:
    # engine.exe --self-test [--json]: import everything, exit 0/1 (run in CI after PyInstaller).
    from self_test import main as _self_test_main

    sys.exit(_self_test_main([a for a in sys.argv[1:] if a != '--self-test']))

import uvicorn
from app import app

if __name__ == '__main__':
    multiprocessing.freeze_support()
    
    port = int(os.environ.get("ENGINE_PORT", 8000))
    host = os.environ.get("ENGINE_HOST", "127.0.0.1")
    
    print(f"=== Starting AI Image Studio Engine on http://{host}:{port} ===")
    uvicorn.run(app, host=host, port=port, log_level="info")
