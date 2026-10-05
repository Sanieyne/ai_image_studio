"""FastAPI entrypoint alias for uvicorn api.main:app."""
from app import app

__all__ = ["app"]
