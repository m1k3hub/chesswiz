"""Security hardening tests (Phase 2).

Covers:
  - Auth lockdown: dummy JWT only in dev with explicit opt-in; production
    fails closed without OIDC; OIDC-configured deployments never fall back
    to the dummy decoder.
  - CORS allowlist parsing, wildcard/credential rules.
  - Streaming multipart upload validation: early 413, streaming cap,
    filename sanitization, path-traversal and storage-key guards.
  - Client-IP resolution with trusted proxy hops (X-Forwarded-For).
  - Rate limiting delegated to the store (shared state).

Run with:  pytest tests/test_security.py -v
"""

import base64
import json
import os
import time

import pytest
from fastapi.testclient import TestClient

import config
import security
import runtime_adapter as ra
from runtime_adapter import app, DATA_DIR, _rate_buckets

if os.environ.get("TCL_INTERP"):
    pytest.skip(
        "Security tests expect the mock/sample-bridge adapter; "
        "unset TCL_INTERP/TCL_BRIDGE_PATH/SCIDB_DATABASE to run them",
        allow_module_level=True,
    )

client = TestClient(app)

os.makedirs(DATA_DIR, exist_ok=True)

_PGN = b'[Event "T"]\n[White "A"]\n[Black "B"]\n1. e4 e5 1-0\n\n'


@pytest.fixture(autouse=True)
def _reset_rate_limits():
    """Keep rate-limit state from leaking between tests (in both directions)."""
    _rate_buckets.clear()
    yield
    _rate_buckets.clear()


def _make_dummy_jwt(sub: str = "user-123", name: str = "Test User", email: str = "test@example.com") -> str:
    header = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').rstrip(b"=").decode()
    payload = base64.urlsafe_b64encode(
        json.dumps({"sub": sub, "name": name, "email": email}).encode()
    ).rstrip(b"=").decode()
    signature = base64.urlsafe_b64encode(b"sig").rstrip(b"=").decode()
    return f"{header}.{payload}.{signature}"


# ---------------------------------------------------------------------------
# Auth lockdown
# ---------------------------------------------------------------------------

def test_dummy_auth_rejected_in_production(monkeypatch):
    """A dummy JWT is rejected when SCIDB_ENV=production, even with the dev flag set."""
    monkeypatch.setattr(config, "SCIDB_ENV", "production")
    monkeypatch.setenv("SCIDB_ALLOW_INSECURE_DEV_AUTH", "1")  # flag alone must not help
    monkeypatch.setattr(ra, "OIDC_JWKS_URI", "")
    token = _make_dummy_jwt()
    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401


def test_dummy_auth_rejected_without_dev_flag(monkeypatch):
    """A dummy JWT is rejected in development when the opt-in flag is missing."""
    monkeypatch.setattr(config, "SCIDB_ENV", "development")
    monkeypatch.delenv("SCIDB_ALLOW_INSECURE_DEV_AUTH", raising=False)
    monkeypatch.setattr(ra, "OIDC_JWKS_URI", "")
    token = _make_dummy_jwt()
    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401


def test_dummy_auth_allowed_with_dev_flag(monkeypatch):
    """Sanity: with the flag set in development, the dummy path still works."""
    monkeypatch.setattr(config, "SCIDB_ENV", "development")
    monkeypatch.setenv("SCIDB_ALLOW_INSECURE_DEV_AUTH", "1")
    monkeypatch.setattr(ra, "OIDC_JWKS_URI", "")
    token = _make_dummy_jwt()
    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    assert resp.json()["id"] == "user-123"


def test_oidc_configured_never_falls_back_to_dummy(monkeypatch):
    """When OIDC_JWKS_URI is set, an unverifiable token is rejected even in dev."""
    monkeypatch.setattr(config, "SCIDB_ENV", "development")
    monkeypatch.setenv("SCIDB_ALLOW_INSECURE_DEV_AUTH", "1")
    monkeypatch.setattr(ra, "OIDC_JWKS_URI", "https://idp.example/.well-known/jwks.json")
    monkeypatch.setattr(ra, "_jwks_client", None)
    # Simulate verification being unavailable/failing.
    monkeypatch.setattr(ra, "_verify_jwt_rs256", lambda t: None)
    token = _make_dummy_jwt()
    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401


def test_allow_insecure_dev_auth_matrix():
    """Unit-level matrix for config.allow_insecure_dev_auth."""
    assert config.allow_insecure_dev_auth(env="development", flag="1") is True
    assert config.allow_insecure_dev_auth(env="development", flag="true") is True
    assert config.allow_insecure_dev_auth(env="development", flag="") is False
    assert config.allow_insecure_dev_auth(env="development", flag="0") is False
    assert config.allow_insecure_dev_auth(env="production", flag="1") is False
    assert config.allow_insecure_dev_auth(env="production", flag="") is False
    assert config.allow_insecure_dev_auth(env="prod", flag="yes") is False


# ---------------------------------------------------------------------------
# Startup validation (fail closed)
# ---------------------------------------------------------------------------

def test_validate_config_ok_in_development_without_oidc(monkeypatch):
    monkeypatch.setattr(config, "SCIDB_ENV", "development")
    monkeypatch.setattr(config, "OIDC_JWKS_URI", "")
    monkeypatch.setattr(config, "OIDC_INTROSPECTION_URI", "")
    security.validate_security_config()  # must not raise


def test_validate_config_fails_in_production_without_oidc(monkeypatch):
    monkeypatch.setattr(config, "SCIDB_ENV", "production")
    monkeypatch.setattr(config, "OIDC_JWKS_URI", "")
    monkeypatch.setattr(config, "OIDC_INTROSPECTION_URI", "")
    with pytest.raises(security.SecurityConfigError) as excinfo:
        security.validate_security_config()
    assert "OIDC" in str(excinfo.value)


def test_validate_config_fails_in_production_with_dev_flag(monkeypatch):
    monkeypatch.setattr(config, "SCIDB_ENV", "production")
    monkeypatch.setattr(config, "OIDC_JWKS_URI", "https://idp.example/jwks.json")
    monkeypatch.setattr(security, "pyjwt_available", lambda: True)
    monkeypatch.setenv("SCIDB_ALLOW_INSECURE_DEV_AUTH", "1")
    with pytest.raises(security.SecurityConfigError) as excinfo:
        security.validate_security_config()
    assert "SCIDB_ALLOW_INSECURE_DEV_AUTH" in str(excinfo.value)


def test_validate_config_fails_in_production_without_pyjwt(monkeypatch):
    monkeypatch.setattr(config, "SCIDB_ENV", "production")
    monkeypatch.setattr(config, "OIDC_JWKS_URI", "https://idp.example/jwks.json")
    monkeypatch.delenv("SCIDB_ALLOW_INSECURE_DEV_AUTH", raising=False)
    monkeypatch.setattr(security, "pyjwt_available", lambda: False)
    with pytest.raises(security.SecurityConfigError) as excinfo:
        security.validate_security_config()
    assert "PyJWT" in str(excinfo.value)


def test_validate_config_ok_in_production_with_oidc(monkeypatch):
    monkeypatch.setattr(config, "SCIDB_ENV", "production")
    monkeypatch.setattr(config, "OIDC_JWKS_URI", "https://idp.example/jwks.json")
    monkeypatch.delenv("SCIDB_ALLOW_INSECURE_DEV_AUTH", raising=False)
    monkeypatch.setattr(security, "pyjwt_available", lambda: True)
    security.validate_security_config()  # must not raise


def test_startup_lifespan_fails_closed_in_production(monkeypatch):
    """The FastAPI lifespan refuses to start the app with unsafe prod config."""
    monkeypatch.setattr(config, "SCIDB_ENV", "production")
    monkeypatch.setattr(config, "OIDC_JWKS_URI", "")
    monkeypatch.setattr(config, "OIDC_INTROSPECTION_URI", "")
    monkeypatch.delenv("SCIDB_ALLOW_INSECURE_DEV_AUTH", raising=False)
    with pytest.raises(security.SecurityConfigError):
        with TestClient(app):
            pass  # pragma: no cover - startup must raise before serving


def test_create_jwks_client_fails_closed_without_pyjwt():
    """Without PyJWT installed, no JWKS client is created (fail closed)."""
    if security.pyjwt_available():
        pytest.skip("PyJWT is installed in this environment")
    assert security.create_jwks_client("https://idp.example/jwks.json") is None


def test_verify_rs256_with_fake_jwks(monkeypatch):
    """security.verify_rs256 enforces signature, issuer, audience and required claims."""
    pyjwt = pytest.importorskip("jwt")
    pytest.importorskip("cryptography")
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives import serialization

    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_pem = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )

    class _FakeKey:
        key = public_pem

    class _FakeJWKS:
        def get_signing_key_from_jwt(self, token):
            return _FakeKey()

    now = time.time()
    good_token = pyjwt.encode(
        {"sub": "u-1", "iss": "https://idp.example", "aud": "scidb-beta",
         "iat": now - 5, "exp": now + 300},
        private_pem, algorithm="RS256",
    )
    payload = security.verify_rs256(
        good_token, _FakeJWKS(), issuer="https://idp.example", audience="scidb-beta"
    )
    assert payload is not None and payload["sub"] == "u-1"

    # Wrong issuer -> rejected
    assert security.verify_rs256(
        good_token, _FakeJWKS(), issuer="https://other.example", audience="scidb-beta"
    ) is None
    # Wrong audience -> rejected
    assert security.verify_rs256(
        good_token, _FakeJWKS(), issuer="https://idp.example", audience="other-app"
    ) is None
    # Missing exp -> rejected (required claim)
    no_exp = pyjwt.encode(
        {"sub": "u-1", "iss": "https://idp.example", "aud": "scidb-beta"},
        private_pem, algorithm="RS256",
    )
    assert security.verify_rs256(
        no_exp, _FakeJWKS(), issuer="https://idp.example", audience="scidb-beta"
    ) is None


# ---------------------------------------------------------------------------
# CORS allowlist
# ---------------------------------------------------------------------------

def test_cors_preflight_allowed_origin():
    resp = client.options(
        "/api/databases",
        headers={
            "Origin": "http://localhost:8765",
            "Access-Control-Request-Method": "POST",
        },
    )
    assert resp.status_code == 200
    assert resp.headers.get("access-control-allow-origin") == "http://localhost:8765"
    assert resp.headers.get("access-control-allow-credentials") == "true"


def test_cors_preflight_disallowed_origin():
    resp = client.options(
        "/api/databases",
        headers={
            "Origin": "https://evil.example",
            "Access-Control-Request-Method": "POST",
        },
    )
    # Starlette's CORSMiddleware answers disallowed preflights with 400 and
    # never echoes the origin.
    assert resp.status_code == 400
    assert resp.headers.get("access-control-allow-origin") != "https://evil.example"


def test_cors_simple_request_disallowed_origin_gets_no_header():
    resp = client.get("/api/databases", headers={"Origin": "https://evil.example"})
    assert resp.status_code == 200
    assert "access-control-allow-origin" not in resp.headers


def test_cors_parse_defaults_to_dev_origins():
    origins = config.parse_allowed_origins("")
    assert "http://localhost:8765" in origins
    assert "http://127.0.0.1:8766" in origins


def test_cors_parse_custom_list():
    origins = config.parse_allowed_origins("https://chess.example.com, https://staging.chess.example.com")
    assert origins == ["https://chess.example.com", "https://staging.chess.example.com"]


def test_cors_parse_rejects_origin_with_path():
    with pytest.raises(ValueError):
        config.parse_allowed_origins("https://chess.example.com/api")


def test_cors_parse_rejects_non_http_origin():
    with pytest.raises(ValueError):
        config.parse_allowed_origins("ftp://chess.example.com")


def test_cors_parse_rejects_empty_result():
    with pytest.raises(ValueError):
        config.parse_allowed_origins(" , ,")


def test_cors_wildcard_disables_credentials():
    settings = config.cors_settings(env="development", raw_origins="*")
    assert settings["allow_origins"] == ["*"]
    assert settings["allow_credentials"] is False


def test_cors_wildcard_rejected_in_production():
    with pytest.raises(ValueError):
        config.cors_settings(env="production", raw_origins="*")


# ---------------------------------------------------------------------------
# Filename sanitization and path-traversal guards (unit)
# ---------------------------------------------------------------------------

def test_sanitize_filename_strips_unix_traversal():
    assert security.sanitize_filename("../../etc/passwd.pgn") == "passwd.pgn"


def test_sanitize_filename_strips_windows_traversal():
    assert security.sanitize_filename("..\\..\\evil.pgn") == "evil.pgn"


def test_sanitize_filename_strips_absolute_path():
    assert security.sanitize_filename("/etc/chess/db.pgn") == "db.pgn"


def test_sanitize_filename_rejects_dotdot_only():
    with pytest.raises(ValueError):
        security.sanitize_filename("..")


def test_sanitize_filename_rejects_dot_only_names():
    for name in (".", "..", "...", " .... "):
        with pytest.raises(ValueError):
            security.sanitize_filename(name)


def test_sanitize_filename_rejects_control_characters():
    with pytest.raises(ValueError):
        security.sanitize_filename("evil\x00.pgn")
    with pytest.raises(ValueError):
        security.sanitize_filename("evil\x07.pgn")


def test_sanitize_filename_replaces_special_characters():
    assert security.sanitize_filename("my file (final).pgn") == "my file _final_.pgn"


def test_sanitize_filename_none_uses_default():
    assert security.sanitize_filename(None) == "upload.pgn"
    assert security.sanitize_filename("") == "upload.pgn"


def test_sanitize_filename_rejects_overlong():
    with pytest.raises(ValueError):
        security.sanitize_filename("a" * 300 + ".pgn")


def test_is_safe_key_component():
    assert security.is_safe_key_component("masters")
    assert security.is_safe_key_component("db-1a2b3c4d")
    assert not security.is_safe_key_component("..")
    assert not security.is_safe_key_component("a/b")
    assert not security.is_safe_key_component("a\\b")
    assert not security.is_safe_key_component("evil db")
    assert not security.is_safe_key_component("evil$db")
    assert not security.is_safe_key_component("a..b")
    assert not security.is_safe_key_component("")
    assert not security.is_safe_key_component("x" * 65)


def test_ensure_within_directory():
    base = os.path.join(DATA_DIR, "base")
    assert security.ensure_within_directory(base, os.path.join(base, "ok.txt"))
    with pytest.raises(ValueError):
        security.ensure_within_directory(base, os.path.join(base, "..", "escape.txt"))
    with pytest.raises(ValueError):
        security.ensure_within_directory(base, "/etc/passwd")


@pytest.mark.asyncio
async def test_store_file_rejects_escaping_key():
    with pytest.raises(ValueError):
        await ra._store_file("../escape.txt", b"x")


@pytest.mark.asyncio
async def test_retrieve_file_rejects_escaping_key():
    with pytest.raises(ValueError):
        await ra._retrieve_file("../escape.txt")


# ---------------------------------------------------------------------------
# Upload hardening (integration)
# ---------------------------------------------------------------------------

def test_import_path_traversal_filename_is_sanitized():
    resp = client.post(
        "/api/databases/masters/import",
        files={"file": ("../../etc/trav-evil.pgn", _PGN, "application/x-chess-pgn")},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["filename"] == "trav-evil.pgn"
    stored = os.path.realpath(os.path.join(DATA_DIR, "uploads", "masters", "trav-evil.pgn"))
    assert os.path.exists(stored)
    assert stored.startswith(os.path.realpath(DATA_DIR) + os.sep)
    os.remove(stored)


def test_import_backslash_traversal_filename_is_sanitized():
    resp = client.post(
        "/api/databases/masters/import",
        files={"file": ("..\\..\\win-evil.pgn", _PGN, "application/x-chess-pgn")},
    )
    assert resp.status_code == 200
    assert resp.json()["filename"] == "win-evil.pgn"
    stored = os.path.join(DATA_DIR, "uploads", "masters", "win-evil.pgn")
    assert os.path.exists(stored)
    os.remove(stored)


def test_import_rejects_dotdot_filename():
    resp = client.post(
        "/api/databases/masters/import",
        files={"file": ("..", _PGN, "application/x-chess-pgn")},
    )
    assert resp.status_code == 400
    assert "Invalid filename" in resp.json()["error"]


def test_import_rejects_unsafe_database_id():
    resp = client.post(
        "/api/databases/evil%20db/import",
        files={"file": ("ok.pgn", _PGN, "application/x-chess-pgn")},
    )
    assert resp.status_code == 400
    assert "Invalid database id" in resp.json()["error"]


def test_import_special_char_filename_is_sanitized():
    resp = client.post(
        "/api/databases/masters/import",
        files={"file": ("my file (final).pgn", _PGN, "application/x-chess-pgn")},
    )
    assert resp.status_code == 200
    assert resp.json()["filename"] == "my file _final_.pgn"
    stored = os.path.join(DATA_DIR, "uploads", "masters", "my file _final_.pgn")
    assert os.path.exists(stored)
    os.remove(stored)


def test_import_early_413_from_content_length(monkeypatch, capfd):
    """Declared Content-Length far over the cap triggers an early 413."""
    monkeypatch.setattr(ra, "MAX_UPLOAD_SIZE", 100)
    big_content = b"x" * 70_000  # declared multipart length > 100 + 64 KiB slack
    resp = client.post(
        "/api/databases/masters/import",
        files={"file": ("big.pgn", big_content, "application/x-chess-pgn")},
    )
    assert resp.status_code == 413
    captured = capfd.readouterr()
    assert "import.too_large" in captured.out
    assert "declared_size" in captured.out


def test_import_streaming_cap_enforced(monkeypatch):
    """A body that exceeds the cap during the chunked read is rejected."""
    monkeypatch.setattr(ra, "MAX_UPLOAD_SIZE", 100)
    content = b"x" * 500  # under the early-413 threshold, over the streaming cap
    resp = client.post(
        "/api/databases/masters/import",
        files={"file": ("big.pgn", content, "application/x-chess-pgn")},
    )
    assert resp.status_code == 413


# ---------------------------------------------------------------------------
# Client IP / trusted proxy hops
# ---------------------------------------------------------------------------

def test_client_ip_ignores_xff_by_default():
    assert security.client_ip("10.0.0.1", "1.2.3.4", 0) == "10.0.0.1"


def test_client_ip_hops_1_uses_last_xff_entry():
    assert security.client_ip("10.0.0.2", "1.2.3.4", 1) == "1.2.3.4"


def test_client_ip_hops_1_ignores_spoofed_entries():
    # Attacker supplied "9.9.9.9"; our trusted proxy appended the real peer.
    assert security.client_ip("10.0.0.2", "9.9.9.9, 1.2.3.4", 1) == "1.2.3.4"


def test_client_ip_hops_2_skips_two_trusted_entries():
    assert security.client_ip("10.0.0.3", "9.9.9.9, 1.2.3.4, 10.0.0.2", 2) == "1.2.3.4"


def test_client_ip_short_chain_falls_back_to_peer():
    assert security.client_ip("10.0.0.3", "1.2.3.4", 2) == "10.0.0.3"
    assert security.client_ip("10.0.0.3", None, 2) == "10.0.0.3"


def test_trust_proxy_hops_parsing():
    assert config.trust_proxy_hops("2") == 2
    assert config.trust_proxy_hops("0") == 0
    assert config.trust_proxy_hops("-3") == 0
    assert config.trust_proxy_hops("abc") == 0
    assert config.trust_proxy_hops("") == 0


def test_rate_limit_ignores_xff_without_trusted_hops(monkeypatch):
    """With SCIDB_TRUST_PROXY_HOPS unset, spoofed XFF cannot evade limits."""
    monkeypatch.delenv("SCIDB_TRUST_PROXY_HOPS", raising=False)
    monkeypatch.setitem(ra._RATE_LIMIT_MAX_REQUESTS, "/api/searches", 1)
    resp1 = client.post("/api/searches", json={"type": "advanced", "query": {}},
                        headers={"X-Forwarded-For": "1.1.1.1"})
    assert resp1.status_code == 200
    # A different spoofed XFF must NOT get a fresh bucket.
    resp2 = client.post("/api/searches", json={"type": "advanced", "query": {}},
                        headers={"X-Forwarded-For": "2.2.2.2"})
    assert resp2.status_code == 429


def test_rate_limit_uses_xff_with_one_trusted_hop(monkeypatch):
    """With one trusted hop, distinct client IPs get distinct buckets."""
    monkeypatch.setenv("SCIDB_TRUST_PROXY_HOPS", "1")
    monkeypatch.setitem(ra._RATE_LIMIT_MAX_REQUESTS, "/api/searches", 1)
    resp1 = client.post("/api/searches", json={"type": "advanced", "query": {}},
                        headers={"X-Forwarded-For": "1.1.1.1"})
    assert resp1.status_code == 200
    resp2 = client.post("/api/searches", json={"type": "advanced", "query": {}},
                        headers={"X-Forwarded-For": "2.2.2.2"})
    assert resp2.status_code == 200
    # The first client is still limited on its own bucket.
    resp3 = client.post("/api/searches", json={"type": "advanced", "query": {}},
                        headers={"X-Forwarded-For": "1.1.1.1"})
    assert resp3.status_code == 429


# ---------------------------------------------------------------------------
# Rate limiting via the store abstraction
# ---------------------------------------------------------------------------

def test_memory_store_shares_module_buckets():
    """Any in-memory rate-limit backend must share the module-level buckets.

    This is what makes ``_rate_buckets.clear()`` an effective reset for the
    whole test suite regardless of which store backend is active.
    """
    store = ra.store
    if isinstance(store, ra.MemoryStore):
        assert store._rate_buckets is ra._rate_buckets
        return
    fallback = getattr(store, "_memory_fallback", None)
    if fallback is not None:
        assert fallback._rate_buckets is ra._rate_buckets
        return
    pytest.skip("store is fully external (Redis/Postgres); no in-memory buckets")


def test_rate_limit_delegates_to_store(monkeypatch):
    """_check_rate_limit goes through store.check_rate_limit (shared state)."""
    calls = []

    async def spy(client_ip, route_key, max_requests, window_seconds):
        calls.append((client_ip, route_key, max_requests, window_seconds))
        return True

    monkeypatch.setattr(ra.store, "check_rate_limit", spy)
    import asyncio
    ok = asyncio.run(ra._check_rate_limit("10.1.2.3", "/api/searches"))
    assert ok is True
    assert calls == [("10.1.2.3", "/api/searches", ra._RATE_LIMIT_MAX_REQUESTS["/api/searches"], 60.0)]


def test_unlimited_route_returns_true_without_store(monkeypatch):
    """Routes without a configured limit must not touch the store at all."""
    async def boom(*args):
        raise AssertionError("store must not be consulted for unlimited routes")

    monkeypatch.setattr(ra.store, "check_rate_limit", boom)
    import asyncio
    ok = asyncio.run(ra._check_rate_limit("10.1.2.3", "/api/unlimited"))
    assert ok is True
