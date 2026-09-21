import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import base64
import io
import pytest
from PIL import Image
from fastapi.testclient import TestClient

from app import app
from generation.enhancer_pipeline import get_enhancer_engine


@pytest.fixture
def client():
    return TestClient(app)


def _create_test_image_b64(width=80, height=80, color=(140, 180, 220)):
    img = Image.new("RGB", (width, height), color=color)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def test_enhancer_engine_mock_generation():
    engine = get_enhancer_engine()
    test_b64 = _create_test_image_b64(64, 64, (100, 150, 200))
    img_bytes = base64.b64decode(test_b64)

    out_bytes, w, h, orig_w, orig_h = engine.enhance(
        image_bytes=img_bytes,
        scale=4,
        model_name="amd/realesrgan-x4plus",
        face_enhance=True,
    )
    assert len(out_bytes) > 0
    assert orig_w == 64
    assert orig_h == 64
    assert w == 64 * 4
    assert h == 64 * 4
    out_img = Image.open(io.BytesIO(out_bytes))
    assert out_img.size == (256, 256)


def test_enhancer_endpoint_success(client):
    test_b64 = _create_test_image_b64(50, 50, (220, 100, 80))

    response = client.post(
        "/enhance",
        json={
            "image_base64": test_b64,
            "scale": 4,
            "model_name": "amd/realesrgan-x4plus",
            "face_enhance": False,
            "denoise_strength": 0.5,
        },
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["success"] is True
    assert data["scale"] == 4
    assert data["width"] == 200
    assert data["height"] == 200
    assert data["original_width"] == 50
    assert data["original_height"] == 50
    assert data["image_base64"].startswith("data:image/png;base64,")


def test_enhancer_endpoint_scale_2x(client):
    test_b64 = _create_test_image_b64(100, 80, (50, 200, 100))

    response = client.post(
        "/enhance",
        json={
            "image_base64": test_b64,
            "scale": 2,
            "model_name": "amd/realesrgan-x4plus",
            "face_enhance": True,
        },
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["success"] is True
    assert data["scale"] == 2
    assert data["width"] == 200
    assert data["height"] == 160
