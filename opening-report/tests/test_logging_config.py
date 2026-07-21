"""Logging + request-id middleware tests (Phase 2).

Run with:  pytest tests/test_logging_config.py -v
"""

import json
import logging

from fastapi.testclient import TestClient

from logging_config import (
    RequestIdMiddleware,
    configure_logging,
    get_logger,
    get_request_id,
)
from runtime_adapter import app

client = TestClient(app)


def test_request_id_generated_on_response():
    resp = client.get("/api/health/live")
    assert resp.status_code == 200
    rid = resp.headers.get("x-request-id")
    assert rid
    # Generated ids are uuid4 hex (32 chars)
    assert len(rid) == 32
    int(rid, 16)  # parses as hex


def test_request_id_echoes_inbound_header():
    resp = client.get("/api/health/live", headers={"X-Request-ID": "my-test-request-123"})
    assert resp.status_code == 200
    assert resp.headers["x-request-id"] == "my-test-request-123"


def test_request_ids_unique_per_request():
    r1 = client.get("/api/health/live")
    r2 = client.get("/api/health/live")
    assert r1.headers["x-request-id"] != r2.headers["x-request-id"]


def test_request_id_available_in_context_during_request():
    """The contextvar is set while the endpoint runs."""
    from fastapi import FastAPI

    mini = FastAPI()
    mini.add_middleware(RequestIdMiddleware)

    @mini.get("/echo")
    async def echo():
        return {"rid": get_request_id()}

    c = TestClient(mini)
    resp = c.get("/echo", headers={"X-Request-ID": "ctx-check"})
    assert resp.json()["rid"] == "ctx-check"


def test_request_id_cleared_after_request():
    # After the request finished, the contextvar resets to the default.
    assert get_request_id() == ""


def test_configure_logging_idempotent():
    configure_logging()
    configure_logging()  # second call must not raise or duplicate handlers
    root = logging.getLogger()
    assert len(root.handlers) >= 1


def test_get_logger_usable(capsys, caplog):
    log = get_logger("scidb.test")
    if hasattr(log, "bind"):  # structlog -> writes JSON to stdout
        log.info("test.event", answer=42)
        out = capsys.readouterr().out
        assert "test.event" in out
        assert "42" in out
    else:  # stdlib -> captured by caplog
        with caplog.at_level(logging.INFO):
            log.info("test.event answer=42")
        assert caplog.records, "expected at least one log record"


def test_stdlib_fallback_emits_json_when_structlog_missing(monkeypatch):
    """Simulate structlog being unavailable: stdlib fallback must emit JSON."""
    import importlib
    import sys

    import logging_config as lc

    monkeypatch.setitem(sys.modules, "structlog", None)  # force ImportError
    monkeypatch.setattr(lc, "_configured", False)
    try:
        lc.configure_logging("INFO")
        assert not lc._structlog_available()
        log = lc.get_logger("scidb.fallback")
        assert isinstance(log, logging.Logger)
    finally:
        monkeypatch.undo()
        importlib.reload(lc)
