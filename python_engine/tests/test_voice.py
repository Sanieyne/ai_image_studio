import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import base64
import pytest
from fastapi.testclient import TestClient

from app import app
from generation.voice_pipeline import _create_mock_wav, get_voice_engine


@pytest.fixture
def client():
    return TestClient(app)


def test_mock_wav_generation():
    wav_bytes = _create_mock_wav("Hello world", language="en", sample_rate=24000, duration_secs=1.0)
    assert len(wav_bytes) > 44
    assert wav_bytes[:4] == b"RIFF"
    assert wav_bytes[8:12] == b"WAVE"


def test_voice_endpoint_default(client):
    response = client.post(
        "/voice",
        json={
            "prompt": "Hello Chatterbox TTS voice synthesis test",
            "model_name": "ResembleAI/chatterbox",
            "language": "en",
            "exaggeration": 0.5,
            "cfg_weight": 0.5,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["sample_rate"] == 24000
    assert data["language"] == "en"
    assert data["model_name"] == "ResembleAI/chatterbox"
    raw_audio = base64.b64decode(data["audio_base64"])
    assert raw_audio[:4] == b"RIFF"


def test_voice_endpoint_multilingual_and_cloning(client):
    ref_wav = _create_mock_wav("reference speaker", language="en", duration_secs=0.5)
    dummy_ref = base64.b64encode(ref_wav).decode("ascii")
    response = client.post(
        "/voice",
        json={
            "prompt": "Hola mundo desde Flutter y Python",
            "model_name": "ResembleAI/chatterbox-multilingual",
            "language": "es",
            "audio_prompt_base64": dummy_ref,
            "exaggeration": 0.7,
            "cfg_weight": 0.4,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["language"] == "es"
    assert data["model_name"] == "ResembleAI/chatterbox-multilingual"
    raw_audio = base64.b64decode(data["audio_base64"])
    assert len(raw_audio) > 44
