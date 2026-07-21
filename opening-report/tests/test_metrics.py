"""Prometheus /metrics endpoint tests (Phase 2).

Run with:  pytest tests/test_metrics.py -v
"""

import importlib.util

from fastapi.testclient import TestClient

from runtime_adapter import app

client = TestClient(app)

HAVE_PROM = importlib.util.find_spec("prometheus_client") is not None


def test_metrics_endpoint_availability():
    resp = client.get("/metrics")
    if HAVE_PROM:
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("text/plain")
    else:
        assert resp.status_code == 501
        assert "error" in resp.json()


def test_http_request_counter_recorded():
    if not HAVE_PROM:
        return  # endpoint covered by test_metrics_endpoint_availability
    client.get("/api/databases")
    body = client.get("/metrics").text
    assert "scidb_http_requests_total" in body
    # Path label is present and not replaced (not an id)
    assert 'path="/api/databases"' in body


def test_id_path_segments_normalized():
    if not HAVE_PROM:
        return
    client.get("/api/games/g-001")
    body = client.get("/metrics").text
    assert 'path="/api/games/{id}"' in body
    # The raw id must not leak into a label value
    assert 'path="/api/games/g-001"' not in body


def test_metrics_endpoint_not_self_counted():
    if not HAVE_PROM:
        return
    client.get("/metrics")
    body = client.get("/metrics").text
    assert 'path="/metrics"' not in body


def test_health_probes_excluded_from_metrics():
    if not HAVE_PROM:
        return
    client.get("/api/health/live")
    client.get("/api/health/ready")
    body = client.get("/metrics").text
    assert 'path="/api/health/live"' not in body
    assert 'path="/api/health/ready"' not in body


def test_histogram_present():
    if not HAVE_PROM:
        return
    client.get("/api/databases")
    body = client.get("/metrics").text
    assert "scidb_http_request_duration_seconds_bucket" in body
