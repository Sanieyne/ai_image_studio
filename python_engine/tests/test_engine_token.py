"""Engine token: a rented instance answers only /health without the per-rental token;
a local install (no token set) stays open. No GPU or weights needed."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

ENGINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ENGINE))
os.environ["AI_STUDIO_MOCK"] = "1"


@pytest.fixture()
def client_with_token(monkeypatch):
    from fastapi.testclient import TestClient
    import app as app_module

    def make(token: str):
        monkeypatch.setattr(app_module, "ENGINE_TOKEN", token)
        return TestClient(app_module.app)

    return make


def test_health_needs_no_token(client_with_token):
    client = client_with_token("s3cret-token")
    assert client.get("/health").status_code == 200


@pytest.mark.parametrize("headers", [{}, {"X-Engine-Token": "wrong"}, {"X-Engine-Token": ""}])
def test_other_routes_refuse_missing_or_wrong_token(client_with_token, headers):
    client = client_with_token("s3cret-token")
    for method, path in [("get", "/models"), ("get", "/loras"), ("post", "/generate")]:
        res = getattr(client, method)(path, headers=headers)
        assert res.status_code == 401, (method, path)
        assert res.json() == {"detail": "Engine token required."}


def test_right_token_reaches_the_route(client_with_token):
    client = client_with_token("s3cret-token")
    res = client.get("/models", headers={"X-Engine-Token": "s3cret-token"})
    assert res.status_code != 401


def test_local_install_without_token_stays_open(client_with_token):
    client = client_with_token("")
    assert client.get("/models").status_code != 401
