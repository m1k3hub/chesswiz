"""Health endpoint tests (Phase 2): live/ready probe split.

Run with:  pytest tests/test_health.py -v
"""

from fastapi.testclient import TestClient

from runtime_adapter import app

client = TestClient(app)


def test_health_live():
    resp = client.get("/api/health/live")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert "version" in data


def test_health_ready():
    resp = client.get("/api/health/ready")
    # MemoryStore is always reachable, no S3 configured in tests -> 200
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ready"
    components = data["components"]
    assert components["store"] == "ok"
    assert components["s3"] == "disabled"
    assert components["tclBridge"] in ("active", "disabled")
    assert components["engine"] in ("available", "mock")


def test_health_legacy_still_works():
    """The original /api/health endpoint remains for backward compatibility."""
    resp = client.get("/api/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert "redis" in data
    assert "storage" in data
    assert "tclBridge" in data
