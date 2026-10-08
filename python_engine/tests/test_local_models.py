"""Every pipeline loads from <AI_STUDIO_MODELS_DIR>/<catalog id> (no GPU or weights needed)."""
from __future__ import annotations

import os
import sys
import types
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


@pytest.fixture()
def models(tmp_path, monkeypatch):
    monkeypatch.setenv("AI_STUDIO_MODELS_DIR", str(tmp_path))
    monkeypatch.setenv("AI_STUDIO_MODE", "cloud")  # never the hub
    monkeypatch.delenv("AI_STUDIO_MOCK", raising=False)

    def add(model_id: str, *files: str, size: int = 10) -> Path:
        d = tmp_path / model_id
        d.mkdir(parents=True, exist_ok=True)
        for f in files:
            (d / f).write_bytes(b"x" * size)
        return d

    return add


def test_chatterbox_loads_english_and_multilingual_from_the_downloaded_folder(models, monkeypatch):
    folder = models("chatterbox-tts", "t3_cfg.safetensors", "t3_mtl23ls_v2.safetensors")
    calls = []

    class FakeTTS:
        @classmethod
        def from_local(cls, ckpt_dir, device):
            calls.append((cls.__name__, ckpt_dir, device))
            return cls()

        @classmethod
        def from_pretrained(cls, device):  # must not be used
            raise AssertionError("hub download attempted")

    class ChatterboxTTS(FakeTTS):
        pass

    class ChatterboxMultilingualTTS(FakeTTS):
        pass

    monkeypatch.setitem(sys.modules, "chatterbox", types.ModuleType("chatterbox"))
    monkeypatch.setitem(sys.modules, "chatterbox.tts", types.SimpleNamespace(ChatterboxTTS=ChatterboxTTS))
    monkeypatch.setitem(sys.modules, "chatterbox.mtl_tts", types.SimpleNamespace(ChatterboxMultilingualTTS=ChatterboxMultilingualTTS))
    from generation import voice_pipeline

    engine = voice_pipeline.VoiceEngine() if hasattr(voice_pipeline, "VoiceEngine") else voice_pipeline.get_voice_engine()
    engine.mock_mode = False
    engine._en_model = None
    engine._mtl_model = None
    assert engine._get_model("en") is not None
    assert engine._get_model("fr") is not None
    assert calls == [
        ("ChatterboxTTS", str(folder), engine.device),
        ("ChatterboxMultilingualTTS", str(folder), engine.device),
    ]


def test_chatterbox_not_downloaded_is_reported_not_fetched(models):
    from generation import voice_pipeline
    from generation.model_paths import ModelNotDownloadedError

    with pytest.raises(ModelNotDownloadedError, match="Download it from the Voice tab"):
        voice_pipeline._chatterbox_dir()


def test_realesrgan_weights_found_in_the_downloaded_folder(models):
    folder = models("realesrgan-x4plus", "RealESRGAN_x4plus.pth", size=2_000_000)
    from generation.enhancer_pipeline import get_enhancer_engine

    engine = get_enhancer_engine()
    assert engine._get_weights_path("realesrgan-x4plus") == os.path.join(str(folder), "RealESRGAN_x4plus.pth")


def test_tryon_uses_the_downloaded_folder(models, monkeypatch):
    folder = models("fashn-vton-1.5", "model.safetensors")
    monkeypatch.delenv("FASHN_WEIGHTS_DIR", raising=False)
    monkeypatch.setenv("AI_STUDIO_MOCK", "1")  # do not load torch weights
    from generation.tryon_pipeline import TryOnEngine

    assert TryOnEngine().weights_dir == str(folder)


def test_wan_t2v_resolves_to_the_downloaded_folder(models):
    folder = models("wan-2.1-t2v-1.3b", "model_index.json")
    from generation.model_paths import load_source
    from generation.video_pipeline import WAN2_1_T2V_1_3B_REPO

    assert load_source(WAN2_1_T2V_1_3B_REPO) == str(folder)
