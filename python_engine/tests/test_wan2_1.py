import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import base64
import io
import pytest
from PIL import Image
from fastapi.testclient import TestClient

from app import app
from generation.video_pipeline import get_wan2_1_engine


@pytest.fixture
def client():
    return TestClient(app)


def _create_test_image_b64(width=120, height=120, color=(100, 150, 200)):
    img = Image.new("RGB", (width, height), color=color)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def test_wan2_1_engine_t2v():
    engine = get_wan2_1_engine()
    mp4_bytes, seed = engine.generate(
        prompt="A serene sunset over a mountain lake, cinematic lighting",
        task="t2v-1.3B",
        width=832,
        height=480,
        num_frames=16,
        fps=8,
        seed=12345,
    )
    assert len(mp4_bytes) > 0
    assert seed == 12345


def test_wan2_1_engine_i2v():
    engine = get_wan2_1_engine()
    img_b64 = _create_test_image_b64()
    img_bytes = base64.b64decode(img_b64)

    mp4_bytes, seed = engine.generate(
        prompt="The water ripples gently and clouds drift by",
        init_image_bytes=img_bytes,
        task="i2v-14B",
        width=832,
        height=480,
        num_frames=16,
        fps=8,
        seed=999,
    )
    assert len(mp4_bytes) > 0
    assert seed == 999


def test_wan2_1_endpoint_t2v_success(client):
    response = client.post(
        "/wan2_1",
        json={
            "prompt": "Futuristic flying cars above a neon city",
            "task": "t2v-1.3B",
            "width": 832,
            "height": 480,
            "num_frames": 16,
            "fps": 8,
            "seed": 42,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["seed"] == 42
    assert len(data["video_base64"]) > 0


def test_wan2_1_endpoint_i2v_success(client):
    img_b64 = _create_test_image_b64()
    response = client.post(
        "/wan2_1",
        json={
            "prompt": "The subject smiles warmly and waves hand",
            "image_base64": img_b64,
            "task": "i2v-14B",
            "width": 832,
            "height": 480,
            "num_frames": 16,
            "fps": 8,
            "seed": 777,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["seed"] == 777
    assert len(data["video_base64"]) > 0


def test_wan2_1_endpoint_invalid_b64(client):
    response = client.post(
        "/wan2_1",
        json={
            "prompt": "Invalid base64 check",
            "image_base64": "!!!NOT_VALID_BASE64@@@",
            "task": "i2v-14B",
        },
    )
    assert response.status_code == 400


def test_wan2_1_endpoint_flf2v_success(client):
    start_b64 = _create_test_image_b64(color=(200, 100, 100))
    end_b64 = _create_test_image_b64(color=(100, 200, 100))
    response = client.post(
        "/wan2_1",
        json={
            "prompt": "Morph from dawn into midday sunshine",
            "image_base64": start_b64,
            "end_image_base64": end_b64,
            "task": "flf2v-14B",
            "width": 832,
            "height": 480,
            "num_frames": 16,
            "fps": 8,
            "seed": 888,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["seed"] == 888
    assert len(data["video_base64"]) > 0


def test_prompt_enhancer():
    from generation.prompt_enhancer import enhance_video_prompt
    short_p = "a sports car driving"
    enhanced = enhance_video_prompt(short_p, task="t2v")
    assert len(enhanced) > len(short_p)
    assert "sports car driving" in enhanced
    assert any(w in enhanced.lower() for w in ["cinematic", "lighting", "shot", "motion", "dolly", "camera"])

