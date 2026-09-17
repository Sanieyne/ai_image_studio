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

import uvicorn
from app import app

if __name__ == '__main__':
    multiprocessing.freeze_support()
    
    port = int(os.environ.get("ENGINE_PORT", 8000))
    host = os.environ.get("ENGINE_HOST", "127.0.0.1")
    
    print(f"=== Starting AI Image Studio Engine on http://{host}:{port} ===")
    uvicorn.run(app, host=host, port=port, log_level="info")
