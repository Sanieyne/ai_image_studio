import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import base64
import io
import pytest
from PIL import Image
from fastapi.testclient import TestClient

from app import app
from generation.model_registry import family_for, defaults_for, display_label
from generation.pipeline import get_pipeline


@pytest.fixture
def client():
    return TestClient(app)


def test_qwen_image_model_registry():
    model_id = "Qwen/Qwen-Image-2.1"
    assert family_for(model_id) == "qwen_image"
    defaults = defaults_for(model_id)
    assert defaults["default_steps"] == 40
    assert defaults["default_guidance"] == 1.0
    assert display_label(model_id) == "Qwen-Image 2.1"


def test_qwen_image_pipeline_mock_generation():
    pipe = get_pipeline()
    orig_mock = pipe.mock_mode
    pipe.mock_mode = True
    pipe.engine.mock_mode = True

    try:
        pipe.switch_model("Qwen/Qwen-Image-2.1")
        assert pipe.current_model == "Qwen/Qwen-Image-2.1"

        b64, seed, elapsed = pipe.generate(
            prompt="A neon sign reading Qwen Image 2.1 in a futuristic alleyway",
            steps=40,
            cfg_scale=1.0,
            width=1024,
            height=1024,
            seed=42,
        )
        assert b64 is not None
        assert len(b64) > 100
        assert seed == 42
        assert elapsed > 0

        # Decode image and verify dimensions
        img_data = base64.b64decode(b64)
        img = Image.open(io.BytesIO(img_data))
        assert img.size == (1024, 1024)
    finally:
        pipe.mock_mode = orig_mock
        pipe.engine.mock_mode = orig_mock


def test_qwen_image_generate_api_endpoint(client):
    pipe = get_pipeline()
    orig_mock = pipe.mock_mode
    orig_engine_mock = pipe.engine.mock_mode
    pipe.mock_mode = True
    pipe.engine.mock_mode = True
    try:
        res = client.post(
            "/generate",
            json={
                "prompt": "Cyberpunk city with translucent holograms and neon lights",
                "aspect_ratio": "1:1",
                "steps": 40,
                "cfg_scale": 1.0,
                "seed": 999,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert "image_base64" in data
        assert data["seed"] == 999
        assert data["aspect_ratio"] == "1:1"
    finally:
        pipe.mock_mode = orig_mock
        pipe.engine.mock_mode = orig_engine_mock
