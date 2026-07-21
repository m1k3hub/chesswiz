"""Security primitives for the scidb-beta runtime adapter.

This module centralizes the hardening logic introduced in Phase 2:

  - Bearer-token verification (RS256 JWT via OIDC JWKS, opaque-token
    introspection, and a strictly gated dummy-JWT development fallback).
  - Startup configuration validation (fail closed in production).
  - Upload filename sanitization (path-traversal guard) and storage-key
    component validation.
  - Local-storage containment checks (defense in depth for object keys).
  - Client-IP resolution with configurable trusted proxy hops.

The functions here take explicit parameters so they are trivially testable;
``runtime_adapter.py`` keeps thin module-level wrappers (preserving its
public names) that forward its environment-derived globals.
"""

from __future__ import annotations

import base64
import json
import os
import re
from typing import Any

import config


class SecurityConfigError(RuntimeError):
    """Raised at startup when the security configuration is unsafe."""


# ---------------------------------------------------------------------------
# JWT verification (RS256 via OIDC JWKS)
# ---------------------------------------------------------------------------


def pyjwt_available() -> bool:
    """Return True when PyJWT (with crypto support) is importable."""
    try:
        import jwt  # noqa: F401
        return True
    except ImportError:
        return False


def create_jwks_client(jwks_uri: str, cache_lifespan: int = 300) -> Any | None:
    """Create a PyJWT ``PyJWKClient`` for *jwks_uri*, or None if unavailable.

    Returns None (with a loud stderr message) when PyJWT is not installed;
    callers must treat that as "verification unavailable" and fail closed.

    Key caching is enabled so every request does not hit the IdP's JWKS
    endpoint. ``cache_lifespan`` is in seconds.
    """
    try:
        from jwt import PyJWKClient  # type: ignore
    except ImportError:
        print(
            "ERROR: OIDC_JWKS_URI is set but PyJWT is not installed; "
            "RS256 token verification is unavailable. Requests will be rejected.",
            flush=True,
        )
        return None
    try:
        return PyJWKClient(jwks_uri, cache_keys=True, lifespan=cache_lifespan)
    except TypeError:
        # Older PyJWT without cache_keys/lifespan support.
        return PyJWKClient(jwks_uri)


def verify_rs256(
    token: str,
    jwks_client: Any,
    issuer: str | None = None,
    audience: str | None = None,
    leeway: float = 30.0,
) -> dict[str, Any] | None:
    """Verify an RS256 JWT against the OIDC provider's JWKS.

    Returns the decoded payload on success, None on any failure
    (expired, bad signature, wrong issuer/audience, malformed, ...).

    ``exp`` and ``sub`` are required claims: a token without an expiry or a
    subject is useless to the adapter and is rejected.
    """
    try:
        from jwt import decode, ExpiredSignatureError, InvalidTokenError  # type: ignore
    except ImportError:
        return None
    try:
        signing_key = jwks_client.get_signing_key_from_jwt(token)
        options: dict[str, Any] = {
            "verify_aud": bool(audience),
            "verify_iss": bool(issuer),
            "require": ["exp", "sub"],
        }
        payload = decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            issuer=issuer or None,
            audience=audience or None,
            options=options,
            leeway=leeway,
        )
        return payload  # type: ignore
    except ExpiredSignatureError:
        return None
    except InvalidTokenError:
        return None
    except Exception:
        # JWKS fetch failures, key-format problems, etc. — fail closed.
        return None


async def introspect_token(
    token: str,
    introspection_uri: str,
    timeout: float = 10.0,
) -> dict[str, Any] | None:
    """Introspect an opaque token via the OIDC introspection endpoint.

    Returns the introspection response when ``active`` is true, else None.
    """
    if not introspection_uri:
        return None
    try:
        import httpx2 as httpx
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.post(
                introspection_uri,
                data={"token": token},
                headers={"Accept": "application/json"},
            )
            if resp.status_code != 200:
                return None
            data = resp.json()
            if not isinstance(data, dict) or not data.get("active", False):
                return None
            return data
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Dummy JWT (development only — gated by config.allow_insecure_dev_auth)
# ---------------------------------------------------------------------------


def decode_dummy_jwt(token: str) -> dict[str, Any] | None:
    """Permissive unsigned-JWT decode for local development and tests.

    Only reachable when :func:`config.allow_insecure_dev_auth` returns True.
    Accepts any three-part token whose payload is a JSON object with a
    ``sub`` claim. No signature verification is performed — this must never
    be enabled outside development.
    """
    parts = token.split(".")
    if len(parts) != 3:
        return None
    try:
        payload_b64 = parts[1] + "==="  # pad to a multiple of 4
        payload_json = base64.urlsafe_b64decode(payload_b64)
        payload = json.loads(payload_json)
    except Exception:
        return None
    if not isinstance(payload, dict) or "sub" not in payload:
        return None
    return payload


# ---------------------------------------------------------------------------
# Startup validation (fail closed)
# ---------------------------------------------------------------------------


def validate_security_config() -> None:
    """Validate the security configuration; raise on unsafe production config.

    Rules:
      - Production REQUIRES real token verification (OIDC JWKS or an
        introspection endpoint).
      - Production forbids ``SCIDB_ALLOW_INSECURE_DEV_AUTH`` entirely.
      - Production with ``OIDC_JWKS_URI`` requires PyJWT to be installed.
      - CORS origins must parse; wildcard origins are forbidden in production.
      - In development, enabling the insecure auth fallback prints a loud
        warning but is allowed.

    Raises :class:`SecurityConfigError` listing every problem found.
    """
    problems: list[str] = []

    if config.is_production():
        if not config.oidc_configured():
            problems.append(
                "production requires OIDC: set OIDC_JWKS_URI (RS256 JWT "
                "verification) and/or OIDC_INTROSPECTION_URI"
            )
        if os.environ.get("SCIDB_ALLOW_INSECURE_DEV_AUTH"):
            problems.append(
                "SCIDB_ALLOW_INSECURE_DEV_AUTH must not be set in production"
            )
        if config.OIDC_JWKS_URI and not pyjwt_available():
            problems.append(
                "OIDC_JWKS_URI is set but PyJWT is not installed "
                "(install PyJWT[crypto])"
            )

    try:
        config.cors_settings()
    except ValueError as exc:
        problems.append(f"CORS misconfigured: {exc}")

    if problems:
        raise SecurityConfigError(
            "Unsafe security configuration; refusing to start:\n  - "
            + "\n  - ".join(problems)
        )

    if config.allow_insecure_dev_auth():
        print(
            "WARNING: insecure dummy-JWT auth is ENABLED "
            "(SCIDB_ALLOW_INSECURE_DEV_AUTH=1). Never use this in production.",
            flush=True,
        )


# ---------------------------------------------------------------------------
# Upload hardening
# ---------------------------------------------------------------------------

#: Characters allowed in an uploaded filename after sanitization.
_FILENAME_DISALLOWED_RE = re.compile(r"[^A-Za-z0-9._ -]")

#: Maximum filename length (filesystem-safe).
MAX_FILENAME_LENGTH = 255

#: Pattern for identifiers used inside storage keys (database ids, etc.).
_KEY_COMPONENT_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")


def sanitize_filename(
    name: str | None,
    default: str = "upload.pgn",
    max_length: int = MAX_FILENAME_LENGTH,
) -> str:
    """Return a filesystem-safe filename derived from an upload filename.

    Defences applied, in order:
      1. None/empty -> *default*.
      2. Directory components are stripped (both ``/`` and ``\\``), which
         neutralizes absolute paths and ``../`` traversal sequences.
      3. Control characters (including NUL) cause rejection — they are an
         attack signal and can corrupt logs and multipart handling.
      4. Names consisting only of dots (``.``, ``..``, ``...``) are rejected.
      5. Remaining characters outside ``[A-Za-z0-9._ -]`` are replaced with
         ``_`` (keeps names like ``my file (final).pgn`` usable).
      6. Overlong names are rejected.

    Raises :class:`ValueError` for rejected names.
    """
    if not name:
        return default
    # 2. Strip directory components for both separator styles.
    base = name.replace("\\", "/").split("/")[-1]
    # 3. Reject control characters (NUL, newlines, DEL, ...).
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in base):
        raise ValueError("filename contains control characters")
    base = base.strip()
    # 4. Reject dot-only names (".", "..", "...", ...).
    if not base or set(base) <= {"."}:
        raise ValueError("filename is empty or dot-only")
    # 5. Replace disallowed characters.
    cleaned = _FILENAME_DISALLOWED_RE.sub("_", base)
    # A cleaned name may have become dot-only (e.g. ".." handled above, but
    # be thorough) or empty.
    if not cleaned or set(cleaned) <= {"."}:
        raise ValueError("filename has no safe characters")
    # 6. Length cap.
    if len(cleaned) > max_length:
        raise ValueError(f"filename exceeds {max_length} characters")
    return cleaned


def is_safe_key_component(value: str) -> bool:
    """Return True when *value* is safe to embed in a storage key.

    Allowed: 1–64 chars, starting alphanumeric, then alphanumerics, dots,
    underscores and dashes; the substring ``..`` is always rejected.
    """
    if not value or len(value) > 64:
        return False
    if ".." in value:
        return False
    return bool(_KEY_COMPONENT_RE.fullmatch(value))


def ensure_within_directory(base_dir: str, path: str) -> str:
    """Resolve *path* and verify it stays inside *base_dir*.

    Returns the resolved absolute path. Raises :class:`ValueError` when the
    resolved path would escape the base directory (symlink or ``..`` based).
    """
    base_real = os.path.realpath(base_dir)
    path_real = os.path.realpath(path)
    if path_real != base_real and not path_real.startswith(base_real + os.sep):
        raise ValueError(f"path escapes base directory: {path!r}")
    return path_real


# ---------------------------------------------------------------------------
# Client IP resolution with trusted proxy hops
# ---------------------------------------------------------------------------


def client_ip(peer: str, forwarded_for: str | None, trust_hops: int) -> str:
    """Return the best available client IP.

    *peer* is the direct TCP peer (``request.client.host``). The
    ``X-Forwarded-For`` header is only consulted when *trust_hops* > 0,
    i.e. when the operator declares that this many proxies in front of the
    app are trusted to append truthful entries.

    Algorithm: build ``chain + [peer]`` (each proxy appends the address it
    observed), then skip *trust_hops* trusted entries from the right; the
    next entry is the real client. Attacker-controlled entries on the left
    of the chain are never trusted. With *trust_hops* == 0 the header is
    ignored entirely, which is spoof-proof.
    """
    if trust_hops <= 0 or not forwarded_for:
        return peer
    chain = [part.strip() for part in forwarded_for.split(",") if part.strip()]
    addrs = chain + [peer]
    if len(addrs) <= trust_hops:
        # Chain shorter than the number of trusted hops — cannot verify
        # anything beyond the direct peer.
        return peer
    return addrs[-(trust_hops + 1)]
