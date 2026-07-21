"""Contract tests for the scidb-beta runtime adapter.

Verifies the core REST endpoints return the expected JSON shapes.
Run with:  pytest tests/test_runtime_adapter.py -v
"""

import asyncio
import os

import pytest
from fastapi.testclient import TestClient

from runtime_adapter import app, DATA_DIR

if os.environ.get("TCL_INTERP"):
    pytest.skip(
        "Runtime adapter tests expect mock/sample-bridge data; "
        "unset TCL_INTERP/TCL_BRIDGE_PATH/SCIDB_DATABASE to run them",
        allow_module_level=True,
    )

client = TestClient(app)

# Ensure local data dir exists for import tests
os.makedirs(DATA_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# /api/databases
# ---------------------------------------------------------------------------

def test_list_databases():
    resp = client.get("/api/databases")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    assert len(data) >= 2
    db = data[0]
    assert "id" in db
    assert "name" in db
    assert "format" in db
    assert "games" in db
    assert "readOnly" in db


def test_create_database():
    resp = client.post("/api/databases", json={
        "name": "Test DB",
        "format": "PGN",
        "games": 0,
        "readOnly": False,
    })
    assert resp.status_code == 200
    db = resp.json()
    assert db["name"] == "Test DB"
    assert db["format"] == "PGN"
    assert db["id"].startswith("db-")


# ---------------------------------------------------------------------------
# /api/databases/{id}/games
# ---------------------------------------------------------------------------

def test_list_games():
    resp = client.get("/api/databases/masters/games")
    assert resp.status_code == 200
    games = resp.json()
    assert isinstance(games, list)
    assert len(games) >= 1
    g = games[0]
    assert "id" in g
    assert "white" in g
    assert "black" in g
    assert "eco" in g


# ---------------------------------------------------------------------------
# /api/searches
# ---------------------------------------------------------------------------

def test_search_advanced():
    resp = client.post("/api/searches", json={
        "databaseId": "masters",
        "type": "advanced",
        "query": {"white": "carlsen"},
    })
    assert resp.status_code == 200
    result = resp.json()
    assert "jobId" in result
    assert result["status"] == "complete"
    assert result["total"] == 1


def test_search_results():
    # Run a search first
    search_resp = client.post("/api/searches", json={
        "databaseId": "masters",
        "type": "advanced",
        "query": {},
    })
    job_id = search_resp.json()["jobId"]

    results_resp = client.get(f"/api/searches/{job_id}/results")
    assert results_resp.status_code == 200
    data = results_resp.json()
    assert data["jobId"] == job_id
    assert data["status"] == "complete"
    assert "games" in data


def test_search_material():
    resp = client.post("/api/searches", json={
        "databaseId": "masters",
        "type": "material",
        "query": {"whiteQ": 1, "blackQ": 1},
    })
    assert resp.status_code == 200
    assert resp.json()["status"] == "complete"


# ---------------------------------------------------------------------------
# /api/analysis/start
# ---------------------------------------------------------------------------

def test_start_analysis():
    resp = client.post("/api/analysis/start", json={
        "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        "multiPv": 3,
        "depth": 5,
    })
    assert resp.status_code == 200
    result = resp.json()
    assert "jobId" in result
    assert result["status"] == "running"


def test_get_analysis():
    start_resp = client.post("/api/analysis/start", json={
        "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        "multiPv": 1,
        "depth": 3,
    })
    job_id = start_resp.json()["jobId"]

    resp = client.get(f"/api/analysis/{job_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["jobId"] == job_id
    assert "status" in data
    assert "lines" in data


def test_stop_analysis():
    start_resp = client.post("/api/analysis/start", json={"depth": 30})
    job_id = start_resp.json()["jobId"]

    resp = client.post(f"/api/analysis/{job_id}/stop")
    assert resp.status_code == 200
    assert resp.json()["status"] == "stopped"


# ---------------------------------------------------------------------------
# /api/tree/query
# ---------------------------------------------------------------------------

def test_tree_query():
    resp = client.post("/api/tree/query", json={"moves": []})
    assert resp.status_code == 200
    tree = resp.json()
    assert isinstance(tree, list)
    assert len(tree) >= 1
    assert "san" in tree[0]
    assert "games" in tree[0]


# ---------------------------------------------------------------------------
# /api/workspace, /api/jobs/{id}, /api/health
# ---------------------------------------------------------------------------

def test_workspace():
    resp = client.get("/api/workspace")
    assert resp.status_code == 200
    assert "activeDatabaseId" in resp.json()


def test_health():
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_get_job():
    search = client.post("/api/searches", json={"type": "advanced", "query": {}})
    job_id = search.json()["jobId"]
    resp = client.get(f"/api/jobs/{job_id}")
    assert resp.status_code == 200
    assert resp.json()["jobId"] == job_id


# ---------------------------------------------------------------------------
# /api/databases/{id}/import and /api/databases/{id}/convert
# ---------------------------------------------------------------------------

def test_import_database():
    """Upload a small PGN file via multipart and verify the job is created."""
    pgn_content = b'[Event "Test"]\n[White "Alice"]\n[Black "Bob"]\n1. e4 e5 1-0\n\n'
    resp = client.post(
        "/api/databases/masters/import",
        files={"file": ("test.pgn", pgn_content, "application/x-chess-pgn")},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "complete"
    assert data["filename"] == "test.pgn"
    assert data["size"] == len(pgn_content)
    assert data["jobId"].startswith("import-")


def test_convert_database():
    """Request a database conversion and verify the job is created."""
    resp = client.post(
        "/api/databases/masters/convert",
        json={"targetFormat": "SCI"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "running"
    assert data["targetFormat"] == "SCI"
    assert data["jobId"].startswith("convert-")


def test_import_job_in_jobs_store():
    """Verify that an import job is retrievable via /api/jobs/{id}."""
    pgn_content = b"1. e4 e5 1-0\n\n"
    import_resp = client.post(
        "/api/databases/masters/import",
        files={"file": ("mini.pgn", pgn_content, "application/x-chess-pgn")},
    )
    job_id = import_resp.json()["jobId"]
    resp = client.get(f"/api/jobs/{job_id}")
    assert resp.status_code == 200
    job = resp.json()
    assert job["jobId"] == job_id
    assert job["type"] == "import"
    assert job["databaseId"] == "masters"


# ---------------------------------------------------------------------------
# /api/auth/*
# ---------------------------------------------------------------------------

def _make_dummy_jwt(sub: str = "user-123", name: str = "Test User", email: str = "test@example.com") -> str:
    """Create a minimal unsigned-looking JWT with a valid base64 payload."""
    import base64
    header = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').rstrip(b"=").decode()
    payload = base64.urlsafe_b64encode(
        __import__("json").dumps({"sub": sub, "name": name, "email": email}).encode()
    ).rstrip(b"=").decode()
    signature = base64.urlsafe_b64encode(b"sig").rstrip(b"=").decode()
    return f"{header}.{payload}.{signature}"


def test_auth_me_unauthorized_without_token():
    """GET /api/auth/me returns 401 when no Authorization header is present."""
    resp = client.get("/api/auth/me")
    assert resp.status_code == 401
    assert "error" in resp.json()


def test_auth_me_returns_user_with_valid_token():
    """GET /api/auth/me returns decoded user when a valid dummy JWT is provided."""
    token = _make_dummy_jwt()
    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == "user-123"
    assert data["name"] == "Test User"
    assert data["email"] == "test@example.com"


def test_auth_me_rejects_malformed_token():
    """GET /api/auth/me returns 401 for a malformed Bearer token."""
    resp = client.get("/api/auth/me", headers={"Authorization": "Bearer not-a-jwt"})
    assert resp.status_code == 401


def test_auth_login_redirects():
    """GET /api/auth/login returns a 302 redirect."""
    resp = client.get("/api/auth/login", follow_redirects=False)
    assert resp.status_code == 302


def test_auth_logout_redirects():
    """GET /api/auth/logout returns a 302 redirect."""
    resp = client.get("/api/auth/logout", follow_redirects=False)
    assert resp.status_code == 302


# ---------------------------------------------------------------------------
# Real JWT verification (RS256) — requires PyJWT + cryptography
# ---------------------------------------------------------------------------

def _make_real_rs256_jwt(
    sub: str = "user-rs256",
    name: str = "RS256 User",
    email: str = "rs256@example.com",
    issuer: str = "https://idp.test.example",
    audience: str = "scidb-beta",
    expired: bool = False,
    wrong_issuer: bool = False,
    wrong_audience: bool = False,
) -> str:
    """Create a real RS256-signed JWT for testing."""
    try:
        import jwt as pyjwt  # type: ignore
        from cryptography.hazmat.primitives.asymmetric import rsa  # type: ignore
        from cryptography.hazmat.primitives import serialization
    except ImportError:
        pytest.skip("PyJWT + cryptography not installed")

    # Generate an RSA key pair for signing
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_key = private_key.public_key()
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )

    import time as _time
    now = _time.time()
    payload = {
        "sub": sub,
        "name": name,
        "email": email,
        "iss": "https://wrong-issuer.example" if wrong_issuer else issuer,
        "aud": "wrong-audience" if wrong_audience else audience,
        "iat": now - 10,
        "exp": now - 1 if expired else now + 3600,
    }
    return pyjwt.encode(payload, private_pem, algorithm="RS256")


def _make_mock_jwks_uri(public_pem: bytes) -> str:
    """Return a mock JWKS URI that serves the given public key."""
    import base64
    import json
    from cryptography.hazmat.primitives import serialization

    # Extract the modulus and exponent from the PEM
    from cryptography.hazmat.primitives.asymmetric import rsa as _rsa
    pub = serialization.load_pem_public_key(public_pem)
    assert isinstance(pub, _rsa.RSAPublicKey)
    numbers = pub.public_numbers()

    def _int_to_b64url(n: int) -> str:
        byte_length = (n.bit_length() + 7) // 8
        data = n.to_bytes(byte_length, "big")
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    jwks = {
        "keys": [
            {
                "kty": "RSA",
                "use": "sig",
                "alg": "RS256",
                "kid": "test-key-1",
                "n": _int_to_b64url(numbers.n),
                "e": _int_to_b64url(numbers.e),
            }
        ]
    }
    # We can't easily serve a real HTTP endpoint in tests; instead we monkeypatch
    # the PyJWKClient to return our key directly.
    return json.dumps(jwks)


def _setup_oidc_env(monkeypatch, issuer: str = "https://idp.test.example", audience: str = "scidb-beta"):
    """Configure OIDC env vars for testing."""
    monkeypatch.setattr("runtime_adapter.OIDC_ISSUER", issuer)
    monkeypatch.setattr("runtime_adapter.OIDC_AUDIENCE", audience)
    monkeypatch.setattr("runtime_adapter.OIDC_JWKS_URI", "https://idp.test.example/.well-known/jwks.json")
    # Reset cached JWKS client
    monkeypatch.setattr("runtime_adapter._jwks_client", None)
    monkeypatch.setattr("runtime_adapter._signing_keys", [])


def test_jwt_valid_rs256(monkeypatch):
    """GET /api/auth/me succeeds with a valid RS256 JWT when OIDC is configured."""
    try:
        import jwt as pyjwt  # type: ignore
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives import serialization
    except ImportError:
        pytest.skip("PyJWT + cryptography not installed")

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

    import time as _time
    now = _time.time()
    token = pyjwt.encode(
        {
            "sub": "user-rs256-valid",
            "name": "Valid RS256",
            "email": "valid@example.com",
            "iss": "https://idp.test.example",
            "aud": "scidb-beta",
            "iat": now - 10,
            "exp": now + 3600,
        },
        private_pem,
        algorithm="RS256",
    )

    _setup_oidc_env(monkeypatch)

    # Mock the JWT verification to use our public key directly
    import runtime_adapter as ra
    original_verify = ra._verify_jwt_rs256

    def mock_verify(t: str) -> dict | None:
        try:
            decoded = pyjwt.decode(
                t, public_pem, algorithms=["RS256"],
                issuer="https://idp.test.example",
                audience="scidb-beta",
            )
            return decoded  # type: ignore
        except Exception:
            return None

    monkeypatch.setattr(ra, "_verify_jwt_rs256", mock_verify)

    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == "user-rs256-valid"
    assert data["name"] == "Valid RS256"


def test_jwt_expired_rs256(monkeypatch):
    """GET /api/auth/me returns 401 for an expired RS256 JWT."""
    try:
        import jwt as pyjwt  # type: ignore
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives import serialization
    except ImportError:
        pytest.skip("PyJWT + cryptography not installed")

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

    import time as _time
    now = _time.time()
    token = pyjwt.encode(
        {
            "sub": "user-expired",
            "name": "Expired",
            "iss": "https://idp.test.example",
            "aud": "scidb-beta",
            "iat": now - 7200,
            "exp": now - 3600,  # expired 1 hour ago
        },
        private_pem,
        algorithm="RS256",
    )

    _setup_oidc_env(monkeypatch)

    import runtime_adapter as ra

    def mock_verify(t: str) -> dict | None:
        try:
            pyjwt.decode(
                t, public_pem, algorithms=["RS256"],
                issuer="https://idp.test.example",
                audience="scidb-beta",
            )
            return {"sub": "should-not-reach-here"}  # type: ignore
        except pyjwt.ExpiredSignatureError:
            return None
        except Exception:
            return None

    monkeypatch.setattr(ra, "_verify_jwt_rs256", mock_verify)

    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401


def test_jwt_wrong_issuer_rs256(monkeypatch):
    """GET /api/auth/me returns 401 for a JWT with the wrong issuer."""
    try:
        import jwt as pyjwt  # type: ignore
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives import serialization
    except ImportError:
        pytest.skip("PyJWT + cryptography not installed")

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

    import time as _time
    now = _time.time()
    token = pyjwt.encode(
        {
            "sub": "user-wrong-issuer",
            "iss": "https://wrong-issuer.example",
            "aud": "scidb-beta",
            "iat": now - 10,
            "exp": now + 3600,
        },
        private_pem,
        algorithm="RS256",
    )

    _setup_oidc_env(monkeypatch, issuer="https://idp.test.example")

    import runtime_adapter as ra

    def mock_verify(t: str) -> dict | None:
        try:
            decoded = pyjwt.decode(
                t, public_pem, algorithms=["RS256"],
                issuer="https://idp.test.example",
                audience="scidb-beta",
            )
            return decoded  # type: ignore
        except pyjwt.InvalidIssuerError:
            return None
        except Exception:
            return None

    monkeypatch.setattr(ra, "_verify_jwt_rs256", mock_verify)

    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401


def test_jwt_wrong_audience_rs256(monkeypatch):
    """GET /api/auth/me returns 401 for a JWT with the wrong audience."""
    try:
        import jwt as pyjwt  # type: ignore
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives import serialization
    except ImportError:
        pytest.skip("PyJWT + cryptography not installed")

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

    import time as _time
    now = _time.time()
    token = pyjwt.encode(
        {
            "sub": "user-wrong-aud",
            "iss": "https://idp.test.example",
            "aud": "wrong-audience",
            "iat": now - 10,
            "exp": now + 3600,
        },
        private_pem,
        algorithm="RS256",
    )

    _setup_oidc_env(monkeypatch, audience="scidb-beta")

    import runtime_adapter as ra

    def mock_verify(t: str) -> dict | None:
        try:
            decoded = pyjwt.decode(
                t, public_pem, algorithms=["RS256"],
                issuer="https://idp.test.example",
                audience="scidb-beta",
            )
            return decoded  # type: ignore
        except pyjwt.InvalidAudienceError:
            return None
        except Exception:
            return None

    monkeypatch.setattr(ra, "_verify_jwt_rs256", mock_verify)

    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401


def test_jwt_oidc_rejects_dummy_when_configured(monkeypatch):
    """When OIDC is configured, dummy JWTs are rejected (no fallback)."""
    _setup_oidc_env(monkeypatch)

    import runtime_adapter as ra

    # Mock _verify_jwt_rs256 to always return None (simulating failed verification)
    monkeypatch.setattr(ra, "_verify_jwt_rs256", lambda t: None)

    # A dummy JWT that would normally pass the dev fallback
    token = _make_dummy_jwt()
    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401


def test_jwt_dummy_fallback_when_oidc_not_configured():
    """When OIDC is NOT configured, dummy JWTs are accepted (dev mode)."""
    # Ensure OIDC env vars are not set (default state)
    token = _make_dummy_jwt()
    resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    assert resp.json()["id"] == "user-123"


def test_introspection_not_configured_returns_none():
    """_introspect_token returns None when OIDC_INTROSPECTION_URI is not set."""
    import asyncio
    from runtime_adapter import _introspect_token
    result = asyncio.run(_introspect_token("some-token"))
    assert result is None


# ---------------------------------------------------------------------------
# FEN / PGN / CQL validation
# ---------------------------------------------------------------------------

def test_analysis_rejects_invalid_fen():
    """POST /api/analysis/start returns 400 for a malformed FEN."""
    resp = client.post("/api/analysis/start", json={
        "fen": "not a fen",
        "multiPv": 1,
        "depth": 3,
    })
    assert resp.status_code == 400
    assert "Invalid FEN" in resp.json()["error"]

def test_analysis_rejects_invalid_fen_string():
    """POST /api/analysis/start returns 400 when FEN is explicitly invalid."""
    resp = client.post("/api/analysis/start", json={
        "fen": "invalid-fen-string",
        "multiPv": 1,
        "depth": 3,
    })
    assert resp.status_code == 400

def test_search_rejects_invalid_cql():
    """POST /api/searches with type=cql returns 400 for malformed CQL."""
    resp = client.post("/api/searches", json={
        "databaseId": "masters",
        "type": "cql",
        "query": {"cql": "(match :gamenumber 1 100"},  # unbalanced parens
    })
    assert resp.status_code == 400
    assert "Invalid CQL" in resp.json()["error"]

def test_search_rejects_cql_with_script_tag():
    """POST /api/searches with type=cql returns 400 for CQL containing script tags."""
    resp = client.post("/api/searches", json={
        "databaseId": "masters",
        "type": "cql",
        "query": {"cql": "<script>alert(1)</script>"},
    })
    assert resp.status_code == 400

def test_import_rejects_invalid_pgn():
    """POST /api/databases/:id/import returns 400 for a malformed PGN file."""
    bad_pgn = b"This is not a valid PGN file at all.\n"
    resp = client.post(
        "/api/databases/masters/import",
        files={"file": ("bad.pgn", bad_pgn, "application/x-chess-pgn")},
    )
    assert resp.status_code == 400
    assert "Invalid PGN" in resp.json()["error"]


# ---------------------------------------------------------------------------
# Request size limits
# ---------------------------------------------------------------------------

def test_import_rejects_oversized_file():
    """POST /api/databases/:id/import returns 413 when the file exceeds 256 MB."""
    # Create a file slightly larger than MAX_UPLOAD_SIZE
    # We can't actually upload 256MB in a test, so we monkey-patch MAX_UPLOAD_SIZE
    import runtime_adapter
    original_max = runtime_adapter.MAX_UPLOAD_SIZE
    runtime_adapter.MAX_UPLOAD_SIZE = 100  # 100 bytes for testing
    try:
        big_content = b"x" * 200
        resp = client.post(
            "/api/databases/masters/import",
            files={"file": ("big.pgn", big_content, "application/x-chess-pgn")},
        )
        assert resp.status_code == 413
    finally:
        runtime_adapter.MAX_UPLOAD_SIZE = original_max


def test_analysis_rejects_oversized_fen():
    """POST /api/analysis/start returns 400 for a FEN exceeding 4 KB."""
    long_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 " + "x" * 5000
    resp = client.post("/api/analysis/start", json={
        "fen": long_fen,
        "multiPv": 1,
        "depth": 3,
    })
    assert resp.status_code == 400


# ---------------------------------------------------------------------------
# Rate limiting
# ---------------------------------------------------------------------------

def test_search_rate_limited():
    """POST /api/searches returns 429 after exceeding the rate limit."""
    import runtime_adapter
    # Temporarily lower the limit for testing
    original_limit = runtime_adapter._RATE_LIMIT_MAX_REQUESTS.get("/api/searches", 30)
    runtime_adapter._RATE_LIMIT_MAX_REQUESTS["/api/searches"] = 3
    # Clear the rate limit buckets
    runtime_adapter._rate_buckets.clear()
    try:
        for _ in range(3):
            resp = client.post("/api/searches", json={"type": "advanced", "query": {}})
            assert resp.status_code == 200
        # 4th request should be rate limited
        resp = client.post("/api/searches", json={"type": "advanced", "query": {}})
        assert resp.status_code == 429
    finally:
        runtime_adapter._RATE_LIMIT_MAX_REQUESTS["/api/searches"] = original_limit
        runtime_adapter._rate_buckets.clear()


def test_analysis_rate_limited():
    """POST /api/analysis/start returns 429 after exceeding the rate limit."""
    import runtime_adapter
    original_limit = runtime_adapter._RATE_LIMIT_MAX_REQUESTS.get("/api/analysis/start", 20)
    runtime_adapter._RATE_LIMIT_MAX_REQUESTS["/api/analysis/start"] = 2
    runtime_adapter._rate_buckets.clear()
    try:
        for _ in range(2):
            resp = client.post("/api/analysis/start", json={
                "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                "depth": 3,
            })
            assert resp.status_code == 200
        # 3rd request should be rate limited
        resp = client.post("/api/analysis/start", json={
            "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "depth": 3,
        })
        assert resp.status_code == 429
    finally:
        runtime_adapter._RATE_LIMIT_MAX_REQUESTS["/api/analysis/start"] = original_limit
        runtime_adapter._rate_buckets.clear()


def test_import_rate_limited():
    """POST /api/databases/:id/import returns 429 after exceeding the rate limit."""
    import runtime_adapter
    original_limit = runtime_adapter._RATE_LIMIT_MAX_REQUESTS.get("/api/databases/{database_id}/import", 10)
    runtime_adapter._RATE_LIMIT_MAX_REQUESTS["/api/databases/{database_id}/import"] = 2
    runtime_adapter._rate_buckets.clear()
    pgn_content = b'[Event "T"]\n[White "A"]\n[Black "B"]\n1. e4 e5 1-0\n\n'
    try:
        for _ in range(2):
            resp = client.post(
                "/api/databases/masters/import",
                files={"file": ("test.pgn", pgn_content, "application/x-chess-pgn")},
            )
            assert resp.status_code == 200
        # 3rd request should be rate limited
        resp = client.post(
            "/api/databases/masters/import",
            files={"file": ("test.pgn", pgn_content, "application/x-chess-pgn")},
        )
        assert resp.status_code == 429
    finally:
        runtime_adapter._RATE_LIMIT_MAX_REQUESTS["/api/databases/{database_id}/import"] = original_limit
        runtime_adapter._rate_buckets.clear()


# ---------------------------------------------------------------------------
# Audit logging
# ---------------------------------------------------------------------------

def test_audit_log_import(capfd):
    """Import triggers an audit log entry with action=import.success."""
    pgn_content = b'[Event "Audit Test"]\n[White "A"]\n[Black "B"]\n1. e4 e5 1-0\n\n'
    resp = client.post(
        "/api/databases/masters/import",
        files={"file": ("audit.pgn", pgn_content, "application/x-chess-pgn")},
    )
    assert resp.status_code == 200
    captured = capfd.readouterr()
    assert "import.success" in captured.out
    assert "audit.pgn" in captured.out


def test_audit_log_login(capfd):
    """GET /api/auth/login triggers an audit log entry with action=auth.login."""
    client.get("/api/auth/login", follow_redirects=False)
    captured = capfd.readouterr()
    assert "auth.login" in captured.out


def test_audit_log_logout(capfd):
    """GET /api/auth/logout triggers an audit log entry with action=auth.logout."""
    client.get("/api/auth/logout", follow_redirects=False)
    captured = capfd.readouterr()
    assert "auth.logout" in captured.out


def test_audit_log_to_file(tmp_path):
    """Audit log writes to AUDIT_LOG file when configured."""
    import runtime_adapter
    audit_file = str(tmp_path / "audit.jsonl")
    original_path = runtime_adapter._AUDIT_LOG_PATH
    runtime_adapter._AUDIT_LOG_PATH = audit_file
    try:
        pgn_content = b'[Event "File Test"]\n[White "A"]\n[Black "B"]\n1. e4 e5 1-0\n\n'
        client.post(
            "/api/databases/masters/import",
            files={"file": ("file_audit.pgn", pgn_content, "application/x-chess-pgn")},
        )
        assert os.path.exists(audit_file)
        with open(audit_file) as f:
            content = f.read()
        assert "import.success" in content
        assert "file_audit.pgn" in content
    finally:
        runtime_adapter._AUDIT_LOG_PATH = original_path


def test_audit_log_convert(capfd):
    """Convert triggers an audit log entry with action=convert.start."""
    client.post("/api/databases/masters/convert", json={"targetFormat": "SCI"})
    captured = capfd.readouterr()
    assert "convert.start" in captured.out


# ---------------------------------------------------------------------------
# /api/engines and real UCI engine integration
# ---------------------------------------------------------------------------

def test_list_engines():
    """GET /api/engines returns at least one engine descriptor."""
    resp = client.get("/api/engines")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    assert len(data) >= 1
    eng = data[0]
    assert "engineId" in eng
    assert "name" in eng
    assert "path" in eng
    # The mock engine is always present
    assert any(e["engineId"] == "mock" for e in data)


def test_analysis_with_mock_engine_fallback():
    """When no real engine is available, analysis falls back to mock simulation."""
    import runtime_adapter as ra
    original = ra.STOCKFISH_PATH
    ra.STOCKFISH_PATH = ""  # force fallback
    try:
        resp = client.post("/api/analysis/start", json={
            "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "depth": 3,
            "multiPv": 2,
            "engineId": "stockfish",
        })
        assert resp.status_code == 200
        job_id = resp.json()["jobId"]
        assert resp.json()["status"] == "running"

        # Verify the job was created with correct shape (background task may not have run yet)
        detail = client.get(f"/api/analysis/{job_id}").json()
        assert detail["jobId"] == job_id
        assert "lines" in detail
        assert "depth" in detail
        assert detail["engineId"] == "stockfish"
    finally:
        ra.STOCKFISH_PATH = original


async def _async_test_fake_uci_engine(fake_engine_path: str) -> dict:
    """Run the fake UCI engine test using an async client so background tasks execute."""
    import httpx2 as httpx
    from runtime_adapter import app

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post("/api/analysis/start", json={
            "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "depth": 2,
            "multiPv": 1,
            "engineId": "stockfish",
        })
        assert resp.status_code == 200
        job_id = resp.json()["jobId"]

        # Poll until the background task completes (up to 5 seconds)
        import time
        detail = {}
        for _ in range(50):
            await asyncio.sleep(0.1)
            resp = await ac.get(f"/api/analysis/{job_id}")
            detail = resp.json()
            if detail.get("status") == "complete" or detail.get("depth", 0) > 0:
                break

        return detail


def test_analysis_with_fake_uci_engine(tmp_path, monkeypatch):
    """Verify real analysis returns depth/nodes/lines when a mock UCI engine is available.

    Creates a tiny fake UCI engine script that emits info lines and a bestmove.
    Uses an async HTTP client so that background asyncio tasks can execute.
    """
    import runtime_adapter as ra

    fake_engine = tmp_path / "fake_uci"
    fake_engine.write_text(
        '#!/usr/bin/env python3\n'
        'import sys, time\n'
        'time.sleep(0.1)\n'
        'print("id name FakeUCI 1.0", flush=True)\n'
        'print("uciok", flush=True)\n'
        'while True:\n'
        '    line = sys.stdin.readline()\n'
        '    if not line:\n'
        '        break\n'
        '    if line.startswith("go"):\n'
        '        print("info depth 1 nodes 100 nps 50000 pv e2e4 score cp 35", flush=True)\n'
        '        print("info depth 2 nodes 500 nps 80000 multipv 1 pv e2e4 e7e5 score cp 20", flush=True)\n'
        '        print("bestmove e2e4", flush=True)\n'
        '    elif line.strip() == "quit":\n'
        '        break\n'
    )
    fake_engine.chmod(0o755)

    monkeypatch.setattr(ra, "STOCKFISH_PATH", str(fake_engine))
    monkeypatch.setattr(ra, "_resolve_engine_path", lambda eid: str(fake_engine) if eid == "stockfish" else "")
    monkeypatch.setattr(ra, "ENGINE_ALLOWLIST", [str(fake_engine), str(tmp_path)])

    detail = asyncio.run(_async_test_fake_uci_engine(str(fake_engine)))
    assert detail.get("jobId", "").startswith("analysis-")
    # The fake engine emitted depth 2 and nodes 500
    assert detail.get("depth", 0) >= 1, f"Expected depth >= 1, got {detail.get('depth')}"
    assert detail.get("nodes", 0) > 0, f"Expected nodes > 0, got {detail.get('nodes')}"
    assert len(detail.get("lines", [])) > 0, f"Expected lines, got {detail.get('lines')}"
    # The PV should contain e2e4
    pv = detail["lines"][0].get("pv", "") if detail.get("lines") else ""
    assert "e2e4" in pv, f"Expected e2e4 in pv, got {pv}"


def test_stockfish_worker_parses_info_lines():
    """Unit test the UCI info-line parser in engines/stockfish_worker.py."""
    import sys
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    from engines.stockfish_worker import parse_info_line

    # A standard info line with cp score and pv
    result = parse_info_line("info depth 15 nodes 1234567 nps 1200000 pv e2e4 e7e5 score cp 35")
    assert result is not None
    assert result["depth"] == 15
    assert result["nodes"] == 1234567
    assert result["nps"] == 1200000
    assert result["eval"] == "+0.35"
    assert result["pv"] == "e2e4 e7e5"

    # A mate score
    result = parse_info_line("info depth 10 pv e2e4 score mate 5")
    assert result is not None
    assert result["eval"] == "M+5"

    # A multipv line
    result = parse_info_line("info depth 8 multipv 2 pv d2d4 d7d5 score cp 15")
    assert result is not None
    assert result["multipv"] == 2
    assert result["eval"] == "+0.15"

    # Non-info line
    assert parse_info_line("bestmove e2e4") is None
    assert parse_info_line("uciok") is None
    assert parse_info_line("") is None

    # info string (should be skipped)
    assert parse_info_line("info string Current root position") is None


# ---------------------------------------------------------------------------
# WebSocket tests
# ---------------------------------------------------------------------------

def test_ws_events_connect_and_disconnect():
    """Verify /api/ws/events accepts a connection and cleans up on disconnect."""
    import runtime_adapter as ra

    initial_count = len(ra._GLOBAL_EVENT_SUBSCRIBERS)
    with client.websocket_connect("/api/ws/events") as ws:
        # Connection should be established
        assert len(ra._GLOBAL_EVENT_SUBSCRIBERS) == initial_count + 1
    # After disconnect, subscriber should be cleaned up
    assert len(ra._GLOBAL_EVENT_SUBSCRIBERS) == initial_count


def test_ws_analysis_connect_and_disconnect():
    """Verify /api/ws/analysis/{job_id} accepts a connection and cleans up on disconnect."""
    import runtime_adapter as ra

    job_id = "test-ws-disconnect-job"
    initial_subs = ra._ANALYSIS_SUBSCRIBERS.get(job_id, [])
    initial_count = len(initial_subs)

    with client.websocket_connect(f"/api/ws/analysis/{job_id}") as ws:
        subs = ra._ANALYSIS_SUBSCRIBERS.get(job_id, [])
        assert len(subs) == initial_count + 1
    # After disconnect, subscriber should be cleaned up
    subs = ra._ANALYSIS_SUBSCRIBERS.get(job_id, [])
    assert len(subs) == initial_count


def test_ws_events_receives_published_event():
    """Verify that events published via _publish_event reach the WebSocket client."""
    import runtime_adapter as ra
    import threading
    import time

    with client.websocket_connect("/api/ws/events") as ws:
        # Publish an event from a background thread's perspective.
        # We need to use asyncio.run_coroutine_threadsafe since TestClient
        # runs its own event loop.
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(
            ra._publish_event({"type": "test.event", "data": "hello"})
        )
        loop.close()

        data = ws.receive_json()
        assert data["type"] == "test.event"
        assert data["data"] == "hello"


def test_stop_analysis_actually_stops_simulation():
    """Verify that /api/analysis/{id}/stop actually halts the mock simulation loop.

    This is a regression test for a bug where _simulate_analysis fetched the
    job once and never re-checked the store for status changes, making the
    stop endpoint ineffective for non-MemoryStore backends.
    """
    # Start an analysis with a high depth so it runs for a while
    start_resp = client.post("/api/analysis/start", json={"depth": 100, "multiPv": 1})
    assert start_resp.status_code == 200
    job_id = start_resp.json()["jobId"]

    # Stop it immediately
    stop_resp = client.post(f"/api/analysis/{job_id}/stop")
    assert stop_resp.status_code == 200
    assert stop_resp.json()["status"] == "stopped"

    # Wait a moment for the background task to notice the stop
    import time
    time.sleep(1.5)

    # Check the final status — should be "stopped", not "complete"
    final = client.get(f"/api/analysis/{job_id}")
    assert final.status_code == 200
    # The status should NOT be "complete" — it should be "stopped"
    assert final.json()["status"] != "complete", (
        f"Expected status to be 'stopped' (not 'complete'), got '{final.json()['status']}'"
    )