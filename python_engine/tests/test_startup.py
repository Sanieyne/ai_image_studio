"""Startup behaviour: /health answers at once, only selected models load, the
model resolver, the self-test and the failure server. No GPU or weights needed."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import urllib.request
from http.server import HTTPServer
from pathlib import Path

import pytest

ENGINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ENGINE))
os.environ["AI_STUDIO_MOCK"] = "1"


@pytest.fixture()
def fresh_engine(monkeypatch):
    """The app with a clean pipeline singleton and model store, worker start recorded."""
    import generation.pipeline as pipeline
    from generation import model_status

    monkeypatch.setattr(pipeline, "_singleton", None)
    store = model_status.ModelStatusManager()
    started = []
    monkeypatch.setattr(store, "start_lifecycle_worker", lambda ids=None: started.append(list(ids or [])))
    monkeypatch.setattr(model_status, "model_status_manager", store)
    import app as app_module

    return app_module.app, store, started, pipeline


def test_health_answers_without_creating_a_pipeline(fresh_engine, monkeypatch):
    from fastapi.testclient import TestClient

    app, store, started, pipeline = fresh_engine
    monkeypatch.delenv("AI_STUDIO_SELECTED_MODELS", raising=False)
    with TestClient(app) as client:
        res = client.get("/health")
    assert res.status_code == 200
    assert res.json()["models"] == []
    assert pipeline.peek_pipeline() is None, "/health must never create or load a pipeline"
    assert started == [], "nothing selected: nothing is loaded"


def test_only_selected_models_are_queued(fresh_engine, monkeypatch):
    from fastapi.testclient import TestClient

    app, store, started, pipeline = fresh_engine
    monkeypatch.setenv("AI_STUDIO_SELECTED_MODELS", "realesrgan-x4plus")
    with TestClient(app) as client:
        body = client.get("/health").json()
    assert started == [["realesrgan-x4plus"]]
    assert [m["modelId"] for m in body["models"]] == ["realesrgan-x4plus"]
    assert body["models"][0]["status"] == "queued"
    assert pipeline.peek_pipeline() is None, "SDXL must not be loaded for a Real-ESRGAN rental"


def test_get_pipeline_creates_with_the_requested_model(monkeypatch):
    import generation.pipeline as pipeline

    monkeypatch.setattr(pipeline, "_singleton", None)
    pipe = pipeline.get_pipeline("z-image-turbo")
    assert pipe.current_model == "z-image-turbo"
    assert pipeline.peek_pipeline() is pipe


class TestModelPaths:
    def test_ids_map_both_ways(self):
        from generation import model_paths as mp

        assert mp.catalog_id("stabilityai/stable-diffusion-xl-base-1.0") == "sdxl-base-1.0"
        assert mp.catalog_id("sdxl-base-1.0") == "sdxl-base-1.0"
        assert mp.registry_id("flux-kontext-dev") == "black-forest-labs/FLUX.1-Kontext-dev"
        assert mp.registry_id("realesrgan-x4plus") == "realesrgan-x4plus"

    def test_loads_from_the_downloaded_folder(self, tmp_path, monkeypatch):
        from generation import model_paths as mp

        monkeypatch.setenv("AI_STUDIO_MODELS_DIR", str(tmp_path))
        (tmp_path / "sdxl-base-1.0").mkdir()
        (tmp_path / "sdxl-base-1.0" / "model_index.json").write_text("{}")
        expected = str(tmp_path / "sdxl-base-1.0")
        assert mp.load_source("sdxl-base-1.0") == expected
        assert mp.load_source("stabilityai/stable-diffusion-xl-base-1.0") == expected

    def test_never_uses_the_hub_on_cloud_instances(self, tmp_path, monkeypatch):
        from generation import model_paths as mp

        monkeypatch.setenv("AI_STUDIO_MODELS_DIR", str(tmp_path))
        monkeypatch.setenv("AI_STUDIO_MODE", "cloud")
        with pytest.raises(mp.ModelNotDownloadedError, match="not downloaded"):
            mp.load_source("sdxl-base-1.0")
        (tmp_path / "flux-kontext-dev").mkdir()  # empty folder = not downloaded
        with pytest.raises(mp.ModelNotDownloadedError):
            mp.load_source("flux-kontext-dev")

    def test_hub_fallback_where_allowed(self, tmp_path, monkeypatch):
        from generation import model_paths as mp

        monkeypatch.setenv("AI_STUDIO_MODELS_DIR", str(tmp_path))
        monkeypatch.delenv("AI_STUDIO_MODE", raising=False)
        monkeypatch.delenv("HF_HUB_OFFLINE", raising=False)
        assert mp.load_source("sdxl-base-1.0") == "stabilityai/stable-diffusion-xl-base-1.0"
        monkeypatch.setenv("HF_HUB_OFFLINE", "1")
        with pytest.raises(mp.ModelNotDownloadedError):
            mp.load_source("sdxl-base-1.0")


class TestSelfTest:
    def test_passes_with_the_installed_packages(self):
        import self_test

        result = self_test.run()
        assert result["ok"], result["failures"]

    def test_reports_a_missing_required_module(self, monkeypatch):
        import self_test

        monkeypatch.setattr(self_test, "REQUIRED", self_test.REQUIRED + [("not_a_real_module_xyz", None)])
        result = self_test.run()
        assert not result["ok"]
        assert any("not_a_real_module_xyz" in f for f in result["failures"])
        assert self_test.main(["--json"]) == 1

    def test_requires_a_gpu_when_asked(self, monkeypatch):
        import self_test

        monkeypatch.setenv("AI_STUDIO_REQUIRE_CUDA", "1")
        monkeypatch.setattr(self_test, "_check_cuda", lambda: "GPU RTX 9999 (sm_999) is not supported")
        result = self_test.run()
        assert not result["ok"]
        assert "sm_999" in result["failures"][-1]


def test_failure_server_reports_the_reason(tmp_path):
    import failure_server

    server = HTTPServer(("127.0.0.1", 0), failure_server.make_handler("diffusers: ImportError: boom"))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        port = server.server_address[1]
        body = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=5))
        assert body == {"status": "failed", "reason": "diffusers: ImportError: boom", "model_loaded": False, "models": []}
    finally:
        server.shutdown()


def test_download_model_imports_without_boto3():
    code = "import sys; sys.modules['boto3'] = None; import download_model; print('imported')"
    out = subprocess.run([sys.executable, "-c", code], cwd=ENGINE, capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stderr
    assert "imported" in out.stdout
