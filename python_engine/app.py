"""FastAPI entrypoint. Run with: uvicorn app:app --host 127.0.0.1 --port 8000"""
from __future__ import annotations

import logging
import sys
import os

# Allow running as `python app.py` or `uvicorn app:app` from python_engine/.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.routes import router
from generation.pipeline import get_pipeline

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Warm up pipeline (loads SDXL or falls back to mock) so /health is honest.
    get_pipeline()
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

    uvicorn.run(app, host=settings.host, port=settings.port)

