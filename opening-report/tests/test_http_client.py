"""Shared HTTP client + retry transport tests (Phase 2).

Run with:  pytest tests/test_http_client.py -v
"""

import pytest
import httpx2 as httpx

from http_client import (
    RetryTransport,
    close_http_client,
    get_http_client,
    reset_http_client_for_tests,
)


class _ScriptedTransport(httpx.AsyncBaseTransport):
    """Returns scripted statuses/exceptions in order, then 200."""

    def __init__(self, script):
        self.script = list(script)
        self.calls = 0

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        self.calls += 1
        item = self.script.pop(0) if self.script else 200
        if isinstance(item, Exception):
            raise item
        return httpx.Response(item, json={"status": item})

    async def aclose(self) -> None:
        pass


async def _no_sleep(delay: float) -> None:
    pass


@pytest.mark.asyncio
async def test_retries_on_503_then_succeeds():
    inner = _ScriptedTransport([503, 503, 200])
    transport = RetryTransport(inner, max_retries=3, sleep=_no_sleep)
    async with httpx.AsyncClient(transport=transport) as client:
        resp = await client.get("https://example.com/x")
    assert resp.status_code == 200
    assert inner.calls == 3


@pytest.mark.asyncio
async def test_returns_last_response_when_retries_exhausted():
    inner = _ScriptedTransport([503, 503, 503, 503])
    transport = RetryTransport(inner, max_retries=2, sleep=_no_sleep)
    async with httpx.AsyncClient(transport=transport) as client:
        resp = await client.get("https://example.com/x")
    assert resp.status_code == 503
    assert inner.calls == 3  # 1 initial + 2 retries


@pytest.mark.asyncio
async def test_no_retry_on_client_error():
    inner = _ScriptedTransport([400, 200])
    transport = RetryTransport(inner, max_retries=3, sleep=_no_sleep)
    async with httpx.AsyncClient(transport=transport) as client:
        resp = await client.get("https://example.com/x")
    assert resp.status_code == 400
    assert inner.calls == 1


@pytest.mark.asyncio
async def test_retries_on_transport_error():
    inner = _ScriptedTransport([httpx.ConnectError("boom"), 200])
    transport = RetryTransport(inner, max_retries=2, sleep=_no_sleep)
    async with httpx.AsyncClient(transport=transport) as client:
        resp = await client.get("https://example.com/x")
    assert resp.status_code == 200
    assert inner.calls == 2


@pytest.mark.asyncio
async def test_raises_after_transport_error_exhaustion():
    inner = _ScriptedTransport([httpx.ConnectError("boom"), httpx.ConnectError("boom")])
    transport = RetryTransport(inner, max_retries=1, sleep=_no_sleep)
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(httpx.ConnectError):
            await client.get("https://example.com/x")
    assert inner.calls == 2


@pytest.mark.asyncio
async def test_post_not_retried_by_default():
    inner = _ScriptedTransport([503, 200])
    transport = RetryTransport(inner, max_retries=3, sleep=_no_sleep)
    async with httpx.AsyncClient(transport=transport) as client:
        resp = await client.post("https://example.com/x", json={})
    assert resp.status_code == 503
    assert inner.calls == 1


@pytest.mark.asyncio
async def test_retry_after_header_extends_backoff():
    recorded = []

    async def _recorder(delay: float) -> None:
        recorded.append(delay)

    inner = _ScriptedTransport([429, 200])

    # Inject Retry-After via a wrapper transport
    class _WithRetryAfter(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request):
            resp = await inner.handle_async_request(request)
            if resp.status_code == 429:
                resp.headers["retry-after"] = "2"
            return resp

    transport = RetryTransport(_WithRetryAfter(), max_retries=2, sleep=_recorder)
    async with httpx.AsyncClient(transport=transport) as client:
        resp = await client.get("https://example.com/x")
    assert resp.status_code == 200
    assert len(recorded) == 1
    assert recorded[0] >= 2.0  # Retry-After honoured (plus jitter)


@pytest.mark.asyncio
async def test_shared_client_singleton():
    reset_http_client_for_tests()
    try:
        c1 = get_http_client()
        c2 = get_http_client()
        assert c1 is c2
    finally:
        await close_http_client()
        reset_http_client_for_tests()


@pytest.mark.asyncio
async def test_close_resets_singleton():
    reset_http_client_for_tests()
    c1 = get_http_client()
    await close_http_client()
    c2 = get_http_client()
    assert c2 is not c1
    await close_http_client()
    reset_http_client_for_tests()


def test_default_headers_include_user_agent():
    reset_http_client_for_tests()
    client = get_http_client()
    assert client.headers["user-agent"].startswith("scidb-beta-runtime/")
    reset_http_client_for_tests()
