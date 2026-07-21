"""Tests for the centralized configuration module (config.Settings)."""

from __future__ import annotations

from config import Settings, get_settings, reset_settings


class TestFromEnv:
    def test_defaults(self):
        s = Settings.from_env({})
        assert s.env == "development"
        assert not s.is_production
        assert s.s3_region == "us-east-1"
        assert s.max_upload_bytes == 256 * 1024 * 1024
        assert s.job_ttl_seconds == 86400
        assert s.analysis_ttl_seconds == 86400
        assert s.cache_ttl_seconds == 300
        assert s.trust_proxy_hops == 0
        assert "http://localhost:8765" in s.allowed_origins
        assert s.data_dir  # defaults to ./data next to config.py

    def test_parses_scalars(self):
        s = Settings.from_env({
            "SCIDB_ENV": "production",
            "DATABASE_URL": "postgresql://u:p@h/db",
            "REDIS_URL": "redis://h:6379/0",
            "SCIDB_TRUST_PROXY_HOPS": "2",
            "SCIDB_MAX_UPLOAD_BYTES": "1024",
            "SCIDB_JOB_TTL_SECONDS": "60",
        })
        assert s.is_production
        assert s.database_url == "postgresql://u:p@h/db"
        assert s.redis_url == "redis://h:6379/0"
        assert s.trust_proxy_hops == 2
        assert s.max_upload_bytes == 1024
        assert s.job_ttl_seconds == 60

    def test_allowed_origins_csv(self):
        s = Settings.from_env({"SCIDB_ALLOWED_ORIGINS": "https://a.example, https://b.example ,"})
        assert s.allowed_origins == ("https://a.example", "https://b.example")

    def test_invalid_int_falls_back_to_default(self):
        s = Settings.from_env({"SCIDB_JOB_TTL_SECONDS": "not-a-number"})
        assert s.job_ttl_seconds == 86400

    def test_bool_parsing(self):
        assert Settings.from_env({"SCIDB_ALLOW_INSECURE_DEV_AUTH": "1"}).allow_insecure_dev_auth
        assert Settings.from_env({"SCIDB_ALLOW_INSECURE_DEV_AUTH": "true"}).allow_insecure_dev_auth
        assert not Settings.from_env({"SCIDB_ALLOW_INSECURE_DEV_AUTH": "0"}).allow_insecure_dev_auth
        assert not Settings.from_env({}).allow_insecure_dev_auth

    def test_oidc_configured(self):
        assert not Settings.from_env({}).oidc_configured
        assert Settings.from_env({"OIDC_JWKS_URI": "https://idp/jwks"}).oidc_configured
        assert Settings.from_env({"OIDC_INTROSPECTION_URI": "https://idp/introspect"}).oidc_configured


class TestProductionValidation:
    def test_production_requires_oidc_and_db(self):
        s = Settings.from_env({"SCIDB_ENV": "production"})
        problems = s.validate_for_production()
        assert any("OIDC" in p for p in problems)
        assert any("DATABASE_URL" in p for p in problems)

    def test_production_rejects_insecure_dev_auth(self):
        s = Settings.from_env({
            "SCIDB_ENV": "production",
            "OIDC_JWKS_URI": "https://idp/jwks",
            "DATABASE_URL": "postgresql://u:p@h/db",
            "SCIDB_ALLOW_INSECURE_DEV_AUTH": "1",
        })
        problems = s.validate_for_production()
        assert any("INSECURE" in p for p in problems)

    def test_production_rejects_wildcard_origin(self):
        s = Settings.from_env({
            "SCIDB_ENV": "production",
            "OIDC_JWKS_URI": "https://idp/jwks",
            "DATABASE_URL": "postgresql://u:p@h/db",
            "SCIDB_ALLOWED_ORIGINS": "*",
        })
        problems = s.validate_for_production()
        assert any("wildcard" in p.lower() or "'*'" in p for p in problems)

    def test_production_clean_config_passes(self):
        s = Settings.from_env({
            "SCIDB_ENV": "production",
            "OIDC_JWKS_URI": "https://idp/jwks",
            "DATABASE_URL": "postgresql://u:p@h/db",
            "SCIDB_ALLOWED_ORIGINS": "https://scidb.example.com",
        })
        assert s.validate_for_production() == []


class TestSingleton:
    def test_get_settings_caches(self, monkeypatch):
        reset_settings()
        monkeypatch.setenv("SCIDB_ENV", "production")
        s1 = get_settings()
        monkeypatch.setenv("SCIDB_ENV", "development")
        s2 = get_settings()
        assert s1 is s2
        assert s2.env == "production"  # cached from first call
        reset_settings()

    def test_reset_settings(self, monkeypatch):
        reset_settings()
        monkeypatch.setenv("SCIDB_ENV", "production")
        get_settings()
        reset_settings()
        monkeypatch.setenv("SCIDB_ENV", "development")
        assert get_settings().env == "development"
        reset_settings()
