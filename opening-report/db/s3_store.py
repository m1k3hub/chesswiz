"""Object storage backends for the scidb-beta runtime adapter.

Two implementations behind one small interface:
  - S3Store        — S3 or S3-compatible storage (Cloudflare R2, MinIO)
  - LocalDiskStore — local filesystem (development fallback)

``S3Store`` wraps the synchronous boto3 client; blocking calls run via
``asyncio.to_thread`` so the FastAPI event loop is never blocked. Presigned
URL generation performs no I/O in boto3 and stays synchronous — the adapter
hands the URLs to browsers for direct upload/download, keeping large PGN
payloads off the API workers.

Configuration (see also ``config.Settings``):
  S3_BUCKET    bucket name; empty disables S3 (LocalDiskStore is used)
  S3_ENDPOINT  custom endpoint URL (e.g. https://<acct>.r2.cloudflarestorage.com)
  S3_KEY       access key id
  S3_SECRET    secret access key
  S3_REGION    region (default: us-east-1; use "auto" for Cloudflare R2)
  S3_PREFIX    optional key prefix applied to every object
  DATA_DIR     local disk root when S3 is disabled (default: ./data)
"""

from __future__ import annotations

import asyncio
import os
from typing import Any, Mapping

_DEFAULT_REGION = "us-east-1"
_DEFAULT_PRESIGN_EXPIRES = 3600  # seconds


class ObjectKeyError(ValueError):
    """Raised when a storage key is empty, absolute, or contains traversal."""


def sanitize_key(key: str) -> str:
    """Normalize an object key and reject unsafe values.

    Backslashes become forward slashes, empty and ``.`` segments collapse,
    and any ``..`` segment (or an otherwise empty result) raises
    ``ObjectKeyError``. The returned key is always relative with no leading
    or trailing slash.
    """
    if not key or not isinstance(key, str):
        raise ObjectKeyError(f"invalid storage key: {key!r}")
    if key != key.strip() or "\x00" in key:
        raise ObjectKeyError(f"invalid storage key: {key!r}")
    parts: list[str] = []
    for part in key.replace("\\", "/").split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            raise ObjectKeyError(f"path traversal not allowed in storage key: {key!r}")
        parts.append(part)
    if not parts:
        raise ObjectKeyError(f"empty storage key: {key!r}")
    return "/".join(parts)


class S3Store:
    """S3 / S3-compatible object storage with presigned URL support.

    Pass ``client=`` to inject a prebuilt (or fake) boto3 client in tests;
    otherwise one is created lazily from the constructor credentials.
    """

    def __init__(
        self,
        bucket: str,
        *,
        endpoint_url: str | None = None,
        access_key: str | None = None,
        secret_key: str | None = None,
        region: str = _DEFAULT_REGION,
        prefix: str = "",
        client: Any = None,
        presign_expires: int = _DEFAULT_PRESIGN_EXPIRES,
    ) -> None:
        if not bucket:
            raise ValueError("bucket is required")
        self.bucket = bucket
        self.prefix = prefix.strip("/")
        self.presign_expires = presign_expires
        self._client = client
        self._client_kwargs = {
            "endpoint_url": endpoint_url or None,
            "aws_access_key_id": access_key or None,
            "aws_secret_access_key": secret_key or None,
            "region_name": region or _DEFAULT_REGION,
        }

    @classmethod
    def from_env(cls, environ: Mapping[str, str] | None = None) -> "S3Store | None":
        """Build an S3Store from S3_* environment variables, or None if unset."""
        env = os.environ if environ is None else environ
        bucket = env.get("S3_BUCKET", "")
        if not bucket:
            return None
        return cls(
            bucket,
            endpoint_url=env.get("S3_ENDPOINT") or None,
            access_key=env.get("S3_KEY") or None,
            secret_key=env.get("S3_SECRET") or None,
            region=env.get("S3_REGION") or _DEFAULT_REGION,
            prefix=env.get("S3_PREFIX", ""),
        )

    def _ensure_client(self) -> Any:
        if self._client is None:
            try:
                import boto3  # type: ignore
            except ImportError as exc:
                raise RuntimeError(
                    "boto3 is required for S3Store; install boto3 or unset S3_BUCKET"
                ) from exc
            self._client = boto3.client("s3", **self._client_kwargs)
        return self._client

    def _full_key(self, key: str) -> str:
        clean = sanitize_key(key)
        return f"{self.prefix}/{clean}" if self.prefix else clean

    async def put(self, key: str, data: bytes, *, content_type: str | None = None) -> str:
        """Store ``data`` under ``key``; returns the full (prefixed) key."""
        client = self._ensure_client()
        full = self._full_key(key)
        kwargs: dict[str, Any] = {"Bucket": self.bucket, "Key": full, "Body": data}
        if content_type:
            kwargs["ContentType"] = content_type
        await asyncio.to_thread(lambda: client.put_object(**kwargs))
        return full

    async def get(self, key: str) -> bytes | None:
        """Return object bytes, or None when the object does not exist."""
        client = self._ensure_client()
        full = self._full_key(key)

        def _get() -> bytes | None:
            try:
                resp = client.get_object(Bucket=self.bucket, Key=full)
            except Exception:
                return None
            return resp["Body"].read()

        return await asyncio.to_thread(_get)

    async def delete(self, key: str) -> bool:
        """Delete an object; returns True on success."""
        client = self._ensure_client()
        full = self._full_key(key)
        try:
            await asyncio.to_thread(lambda: client.delete_object(Bucket=self.bucket, Key=full))
            return True
        except Exception:
            return False

    async def exists(self, key: str) -> bool:
        """Return True when the object exists (HEAD request)."""
        client = self._ensure_client()
        full = self._full_key(key)

        def _head() -> bool:
            try:
                client.head_object(Bucket=self.bucket, Key=full)
                return True
            except Exception:
                return False

        return await asyncio.to_thread(_head)

    def presign_get(self, key: str, *, expires: int | None = None) -> str:
        """Return a presigned GET URL for direct browser download."""
        client = self._ensure_client()
        return client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": self._full_key(key)},
            ExpiresIn=expires or self.presign_expires,
        )

    def presign_put(self, key: str, *, expires: int | None = None, content_type: str | None = None) -> str:
        """Return a presigned PUT URL for direct browser upload."""
        client = self._ensure_client()
        params: dict[str, Any] = {"Bucket": self.bucket, "Key": self._full_key(key)}
        if content_type:
            params["ContentType"] = content_type
        return client.generate_presigned_url(
            "put_object",
            Params=params,
            ExpiresIn=expires or self.presign_expires,
        )

    async def close(self) -> None:
        client, self._client = self._client, None
        close = getattr(client, "close", None)
        if close is not None:
            await asyncio.to_thread(close)


class LocalDiskStore:
    """Filesystem-backed object store used when S3 is not configured."""

    def __init__(self, root: str) -> None:
        self.root = os.path.abspath(root)

    def _path_for(self, key: str) -> str:
        clean = sanitize_key(key)
        path = os.path.abspath(os.path.join(self.root, *clean.split("/")))
        if os.path.commonpath([self.root, path]) != self.root:
            raise ObjectKeyError(f"storage key escapes root: {key!r}")
        return path

    async def put(self, key: str, data: bytes, *, content_type: str | None = None) -> str:
        path = self._path_for(key)

        def _write() -> str:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
            return sanitize_key(key)

        return await asyncio.to_thread(_write)

    async def get(self, key: str) -> bytes | None:
        path = self._path_for(key)

        def _read() -> bytes | None:
            if not os.path.exists(path):
                return None
            with open(path, "rb") as f:
                return f.read()

        return await asyncio.to_thread(_read)

    async def delete(self, key: str) -> bool:
        path = self._path_for(key)

        def _delete() -> bool:
            try:
                os.remove(path)
                return True
            except OSError:
                return False

        return await asyncio.to_thread(_delete)

    async def exists(self, key: str) -> bool:
        path = self._path_for(key)
        return await asyncio.to_thread(os.path.exists, path)

    def presign_get(self, key: str, *, expires: int | None = None) -> str:
        raise RuntimeError("presigned URLs require S3-compatible storage (S3_BUCKET)")

    def presign_put(self, key: str, *, expires: int | None = None, content_type: str | None = None) -> str:
        raise RuntimeError("presigned URLs require S3-compatible storage (S3_BUCKET)")

    async def close(self) -> None:
        pass


def get_object_store(environ: Mapping[str, str] | None = None) -> S3Store | LocalDiskStore:
    """Return the configured object store: S3Store when S3_BUCKET is set,
    otherwise a LocalDiskStore rooted at DATA_DIR (default ./data)."""
    env = os.environ if environ is None else environ
    store = S3Store.from_env(env)
    if store is not None:
        return store
    data_dir = env.get("DATA_DIR") or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data"
    )
    return LocalDiskStore(data_dir)
