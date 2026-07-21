"""Centralized configuration for the scidb-beta runtime adapter.

All settings are read from environment variables into an immutable
``Settings`` dataclass. Use ``get_settings()`` for the process-wide cached
instance and ``reset_settings()`` in tests.

This module is the single source of truth for environment parsing. Other
modules (runtime_adapter, db.store, db.s3_store, engines) should prefer
``get_settings()`` over reading ``os.environ`` directly so that validation
(e.g. production safety checks) happens in one place.

Environment variables
---------------------
SCIDB_ENV                    "development" (default) or "production".
DATABASE_URL                 PostgreSQL DSN (sync or ``+asyncpg`` form).
REDIS_URL                    Redis DSN for jobs/analysis/event bus.
S3_BUCKET / S3_ENDPOINT / S3_KEY / S3_SECRET / S3_REGION / S3_PREFIX
                             S3 or S3-compatible (R2) object storage.
DATA_DIR                     Local disk storage dir (default: ./data).
STOCKFISH_PATH               Path to the UCI engine binary.
SCIDB_ALLOWED_ORIGINS        Comma-separated CORS origins.
SCIDB_TRUST_PROXY_HOPS       Number of trusted proxy hops for X-Forwarded-For.
SCIDB_MAX_UPLOAD_BYTES       Upload size cap (default 256 MiB).
SCIDB_JOB_TTL_SECONDS        Redis TTL for job records (default 86400).
SCIDB_ANALYSIS_TTL_SECONDS   Redis TTL for analysis records (default 86400).
SCIDB_CACHE_TTL_SECONDS      TTL for the idempotent-GET cache (default 300).
OIDC_ISSUER / OIDC_AUDIENCE / OIDC_JWKS_URI / OIDC_INTROSPECTION_URI
                             OIDC/JWT verification configuration.
SCIDB_ALLOW_INSECURE_DEV_AUTH
                             "1" allows the dummy-JWT fallback in development.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Mapping

_DEFAULT_ORIGINS = (
    "http://localhost:8765",
    "http://localhost:8766",
    "http://127.0.0.1:8765",
    "http://127.0.0.1:8766",
)

_TRUE_VALUES = {"1", "true", "yes", "on"}
_PRODUCTION_NAMES = {"production", "prod"}


def _default_data_dir() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")


def _get_str(env: Mapping[str, str], name: str, default: str = "") -> str:
    value = env.get(name, "")
    return value.strip() if value else default


def _get_int(env: Mapping[str, str], name: str, default: int) -> int:
    raw = env.get(name, "")
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        print(f"WARNING: {name}={raw!r} is not an integer; using default {default}", flush=True)
        return default


def _get_bool(env: Mapping[str, str], name: str, default: bool = False) -> bool:
    raw = env.get(name, "")
    if not raw:
        return default
    return raw.strip().lower() in _TRUE_VALUES


@dataclass(frozen=True)
class Settings:
    """Immutable runtime settings parsed from the environment."""

    env: str = "development"
    database_url: str = ""
    redis_url: str = ""

    s3_bucket: str = ""
    s3_endpoint: str = ""
    s3_key: str = ""
    s3_secret: str = ""
    s3_region: str = "us-east-1"
    s3_prefix: str = ""

    data_dir: str = ""
    stockfish_path: str = ""

    allowed_origins: tuple[str, ...] = _DEFAULT_ORIGINS
    trust_proxy_hops: int = 0
    max_upload_bytes: int = 256 * 1024 * 1024

    job_ttl_seconds: int = 86400
    analysis_ttl_seconds: int = 86400
    cache_ttl_seconds: int = 300

    oidc_issuer: str = ""
    oidc_audience: str = ""
    oidc_jwks_uri: str = ""
    oidc_introspection_uri: str = ""
    allow_insecure_dev_auth: bool = False

    @property
    def is_production(self) -> bool:
        return self.env.lower() in _PRODUCTION_NAMES

    @property
    def oidc_configured(self) -> bool:
        return bool(self.oidc_jwks_uri or self.oidc_introspection_uri)

    def validate_for_production(self) -> list[str]:
        """Return a list of configuration problems that block production.

        An empty list means the configuration is safe to run in production.
        Callers should refuse to start (fail closed) when this is non-empty
        and ``is_production`` is True.
        """
        problems: list[str] = []
        if not self.oidc_configured:
            problems.append(
                "OIDC is not configured (set OIDC_JWKS_URI or OIDC_INTROSPECTION_URI); "
                "production startup without authentication is not allowed"
            )
        if self.allow_insecure_dev_auth:
            problems.append(
                "SCIDB_ALLOW_INSECURE_DEV_AUTH is enabled; the dummy JWT fallback "
                "must not be available in production"
            )
        if "*" in self.allowed_origins:
            problems.append(
                "SCIDB_ALLOWED_ORIGINS contains '*'; wildcard origins are not "
                "allowed together with credentialed requests in production"
            )
        if not self.database_url:
            problems.append(
                "DATABASE_URL is not set; production requires PostgreSQL persistence"
            )
        return problems

    @classmethod
    def from_env(cls, environ: Mapping[str, str] | None = None) -> "Settings":
        env = os.environ if environ is None else environ

        origins_raw = _get_str(env, "SCIDB_ALLOWED_ORIGINS", "")
        if origins_raw:
            origins = tuple(o.strip() for o in origins_raw.split(",") if o.strip())
        else:
            origins = _DEFAULT_ORIGINS

        return cls(
            env=_get_str(env, "SCIDB_ENV", "development"),
            database_url=_get_str(env, "DATABASE_URL"),
            redis_url=_get_str(env, "REDIS_URL"),
            s3_bucket=_get_str(env, "S3_BUCKET"),
            s3_endpoint=_get_str(env, "S3_ENDPOINT"),
            s3_key=_get_str(env, "S3_KEY"),
            s3_secret=_get_str(env, "S3_SECRET"),
            s3_region=_get_str(env, "S3_REGION", "us-east-1"),
            s3_prefix=_get_str(env, "S3_PREFIX"),
            data_dir=_get_str(env, "DATA_DIR") or _default_data_dir(),
            stockfish_path=_get_str(env, "STOCKFISH_PATH"),
            allowed_origins=origins,
            trust_proxy_hops=_get_int(env, "SCIDB_TRUST_PROXY_HOPS", 0),
            max_upload_bytes=_get_int(env, "SCIDB_MAX_UPLOAD_BYTES", 256 * 1024 * 1024),
            job_ttl_seconds=_get_int(env, "SCIDB_JOB_TTL_SECONDS", 86400),
            analysis_ttl_seconds=_get_int(env, "SCIDB_ANALYSIS_TTL_SECONDS", 86400),
            cache_ttl_seconds=_get_int(env, "SCIDB_CACHE_TTL_SECONDS", 300),
            oidc_issuer=_get_str(env, "OIDC_ISSUER"),
            oidc_audience=_get_str(env, "OIDC_AUDIENCE"),
            oidc_jwks_uri=_get_str(env, "OIDC_JWKS_URI"),
            oidc_introspection_uri=_get_str(env, "OIDC_INTROSPECTION_URI"),
            allow_insecure_dev_auth=_get_bool(env, "SCIDB_ALLOW_INSECURE_DEV_AUTH", False),
        )


_settings: Settings | None = None


def get_settings() -> Settings:
    """Return the cached process-wide settings (parsed on first call)."""
    global _settings
    if _settings is None:
        _settings = Settings.from_env()
    return _settings


def reset_settings() -> None:
    """Drop the cached settings singleton (used in tests)."""
    global _settings
    _settings = None


# ---------------------------------------------------------------------------
# Convenience module-level API (matches the security hardening subagent output)
# ---------------------------------------------------------------------------

SCIDB_ENV = os.environ.get("SCIDB_ENV", "development")
OIDC_ISSUER = os.environ.get("OIDC_ISSUER", "")
OIDC_AUDIENCE = os.environ.get("OIDC_AUDIENCE", "")
OIDC_JWKS_URI = os.environ.get("OIDC_JWKS_URI", "")
OIDC_INTROSPECTION_URI = os.environ.get("OIDC_INTROSPECTION_URI", "")


def is_production(env: str | None = None) -> bool:
    """Return True when running in a production environment."""
    return (env if env is not None else SCIDB_ENV).strip().lower() in _PRODUCTION_NAMES


def allow_insecure_dev_auth(env: str | None = None, flag: str | None = None) -> bool:
    """Return True when the permissive dummy-JWT auth path is allowed."""
    if is_production(env):
        return False
    if flag is None:
        return os.environ.get("SCIDB_ALLOW_INSECURE_DEV_AUTH", "").strip().lower() in _TRUE_VALUES
    return flag.strip().lower() in _TRUE_VALUES


def parse_allowed_origins(raw: str | None = None) -> list[str]:
    """Parse ``SCIDB_ALLOWED_ORIGINS`` into a validated origin list."""
    if raw is None:
        raw = os.environ.get("SCIDB_ALLOWED_ORIGINS", "")
    if not raw.strip():
        return list(_DEFAULT_ORIGINS)
    origins: list[str] = []
    for entry in raw.split(","):
        origin = entry.strip()
        if not origin:
            continue
        if origin == "*":
            origins.append(origin)
            continue
        lowered = origin.lower()
        if not (lowered.startswith("http://") or lowered.startswith("https://")):
            raise ValueError(f"invalid CORS origin (must be http(s)://authority): {origin!r}")
        after_scheme = origin.split("://", 1)[1]
        if "/" in after_scheme or "?" in after_scheme or "#" in after_scheme:
            raise ValueError(f"invalid CORS origin (must not contain a path): {origin!r}")
        origins.append(origin)
    if not origins:
        raise ValueError("SCIDB_ALLOWED_ORIGINS parses to an empty list")
    return origins


def cors_settings(env: str | None = None, raw_origins: str | None = None) -> dict:
    """Return kwargs for ``fastapi.middleware.cors.CORSMiddleware``."""
    origins = parse_allowed_origins(raw_origins)
    wildcard = "*" in origins
    if wildcard and is_production(env):
        raise ValueError("wildcard CORS origin '*' is not allowed in production")
    return {
        "allow_origins": origins,
        "allow_credentials": not wildcard,
        "allow_methods": ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        "allow_headers": [
            "Authorization",
            "Content-Type",
            "Accept",
            "X-Requested-With",
            "X-Request-ID",
        ],
        "max_age": 600,
    }


def trust_proxy_hops(raw: str | None = None) -> int:
    """Return the number of trusted proxy hops (>= 0)."""
    if raw is None:
        raw = os.environ.get("SCIDB_TRUST_PROXY_HOPS", "0")
    try:
        hops = int(str(raw).strip())
    except (TypeError, ValueError):
        return 0
    return max(hops, 0)


def oidc_configured(jwks_uri: str | None = None, introspection_uri: str | None = None) -> bool:
    """Return True when real token verification is configured."""
    jwks = OIDC_JWKS_URI if jwks_uri is None else jwks_uri
    introspect = OIDC_INTROSPECTION_URI if introspection_uri is None else introspection_uri
    return bool(jwks or introspect)


def max_upload_size(raw: str | None = None) -> int:
    """Return the maximum upload size in bytes (default 256 MB)."""
    if raw is None:
        raw = os.environ.get("SCIDB_MAX_UPLOAD_SIZE", "")
    if raw:
        try:
            value = int(str(raw).strip())
            if value > 0:
                return value
        except (TypeError, ValueError):
            pass
    return 256 * 1024 * 1024


# ---------------------------------------------------------------------------
# Async database URL normalizer (used by db.store and db.migrations.env)
# ---------------------------------------------------------------------------


def normalize_database_url_for_async(url: str) -> str:
    """Convert a sync PostgreSQL DSN to its ``asyncpg`` async form."""
    if not url:
        return url
    if url.startswith("postgres://"):
        return "postgresql+asyncpg://" + url[len("postgres://"):]
    if url.startswith("postgresql+asyncpg://"):
        return url
    if url.startswith("postgresql+psycopg2://"):
        return "postgresql+asyncpg://" + url[len("postgresql+psycopg2://"):]
    if url.startswith("postgresql+psycopg://"):
        return "postgresql+asyncpg://" + url[len("postgresql+psycopg://"):]
    if url.startswith("postgresql://"):
        return "postgresql+asyncpg://" + url[len("postgresql://"):]
    return url
