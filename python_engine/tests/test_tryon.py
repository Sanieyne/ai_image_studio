import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import base64
import io
import pytest
from PIL import Image
from fastapi.testclient import TestClient

from app import app
from generation.tryon_pipeline import get_tryon_engine


@pytest.fixture
def client():
    return TestClient(app)


def _create_test_image_b64(width=100, height=100, color=(120, 150, 200)):
    img = Image.new("RGB", (width, height), color=color)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def test_tryon_engine_mock_generation():
    engine = get_tryon_engine()
    person_b64 = _create_test_image_b64(100, 150, (200, 180, 160))
    garment_b64 = _create_test_image_b64(100, 100, (50, 120, 200))
    
    person_bytes = base64.b64decode(person_b64)
    garment_bytes = base64.b64decode(garment_b64)

    out_bytes, seed = engine.generate(
        person_image_bytes=person_bytes,
        garment_image_bytes=garment_bytes,
        category="tops",
        garment_photo_type="model",
        steps=20,
        guidance_scale=2.0,
        seed=42,
    )
    assert len(out_bytes) > 0
    assert seed == 42
    out_img = Image.open(io.BytesIO(out_bytes))
    assert out_img.size == (576, 864)


def test_tryon_endpoint_success(client):
    person_b64 = _create_test_image_b64(100, 150, (200, 180, 160))
    garment_b64 = _create_test_image_b64(100, 100, (50, 120, 200))

    response = client.post(
        "/tryon",
        json={
            "person_image_base64": person_b64,
            "garment_image_base64": garment_b64,
            "category": "tops",
            "garment_photo_type": "flat-lay",
            "steps": 25,
            "guidance_scale": 2.5,
            "seed": 12345,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["category"] == "tops"
    assert data["seed"] == 12345
    assert data["width"] == 576
    assert data["height"] == 864
    assert "image_base64" in data
    raw_img = base64.b64decode(data["image_base64"].split(",", 1)[1] if "," in data["image_base64"] else data["image_base64"])
    assert len(raw_img) > 0


def test_tryon_endpoint_invalid_base64(client):
    response = client.post(
        "/tryon",
        json={
            "person_image_base64": "invalid_base64_!@#$",
            "garment_image_base64": _create_test_image_b64(),
            "category": "tops",
        },
    )
    assert response.status_code == 400
