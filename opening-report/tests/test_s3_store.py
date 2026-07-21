"""Tests for db.s3_store: S3Store (via an injected fake boto3 client),
LocalDiskStore, key sanitization, and the from_env / get_object_store
factories. No network access or real boto3 installation is required.
"""

from __future__ import annotations

import io

import pytest

from db.s3_store import (
    LocalDiskStore,
    ObjectKeyError,
    S3Store,
    get_object_store,
    sanitize_key,
)


# ---------------------------------------------------------------------------
# Fake boto3 client
# ---------------------------------------------------------------------------

class FakeBoto3Client:
    """In-memory stand-in for a boto3 S3 client."""

    def __init__(self) -> None:
        self.objects: dict[tuple[str, str], bytes] = {}
        self.put_calls: list[dict] = []
        self.presigned_calls: list[tuple[str, dict, int]] = []
        self.closed = False

    def put_object(self, Bucket, Key, Body, **kwargs):
        self.put_calls.append({"Bucket": Bucket, "Key": Key, "Body": Body, **kwargs})
        self.objects[(Bucket, Key)] = bytes(Body)
        return {"ETag": '"fake"'}

    def get_object(self, Bucket, Key):
        if (Bucket, Key) not in self.objects:
            raise self._not_found()
        return {"Body": io.BytesIO(self.objects[(Bucket, Key)])}

    def delete_object(self, Bucket, Key):
        self.objects.pop((Bucket, Key), None)
        return {}

    def head_object(self, Bucket, Key):
        if (Bucket, Key) not in self.objects:
            raise self._not_found()
        return {}

    def generate_presigned_url(self, operation, Params, ExpiresIn):
        self.presigned_calls.append((operation, Params, ExpiresIn))
        return (
            f"https://fake-s3.test/{Params['Bucket']}/{Params['Key']}"
            f"?op={operation}&expires={ExpiresIn}"
        )

    def close(self):
        self.closed = True

    @staticmethod
    def _not_found() -> Exception:
        return Exception("NoSuchKey")


@pytest.fixture
def fake_client():
    return FakeBoto3Client()


@pytest.fixture
def s3(fake_client):
    return S3Store("test-bucket", client=fake_client)


# ---------------------------------------------------------------------------
# S3Store data operations
# ---------------------------------------------------------------------------

class TestS3StoreDataOps:
    @pytest.mark.asyncio
    async def test_put_get_roundtrip(self, s3, fake_client):
        key = await s3.put("uploads/db1/game.pgn", b"[Event \"x\"]\n")
        assert key == "uploads/db1/game.pgn"
        assert fake_client.objects[("test-bucket", key)] == b'[Event "x"]\n'
        assert await s3.get("uploads/db1/game.pgn") == b'[Event "x"]\n'

    @pytest.mark.asyncio
    async def test_put_with_content_type(self, s3, fake_client):
        await s3.put("a/b.pgn", b"data", content_type="application/x-chess-pgn")
        assert fake_client.put_calls[0]["ContentType"] == "application/x-chess-pgn"

    @pytest.mark.asyncio
    async def test_get_missing_returns_none(self, s3):
        assert await s3.get("does/not/exist.bin") is None

    @pytest.mark.asyncio
    async def test_delete(self, s3):
        await s3.put("tmp/file.bin", b"x")
        assert await s3.delete("tmp/file.bin") is True
        assert await s3.get("tmp/file.bin") is None

    @pytest.mark.asyncio
    async def test_exists(self, s3):
        assert await s3.exists("nope.bin") is False
        await s3.put("nope.bin", b"x")
        assert await s3.exists("nope.bin") is True

    @pytest.mark.asyncio
    async def test_prefix_is_applied(self, fake_client):
        store = S3Store("bucket", prefix="tenant-1", client=fake_client)
        full = await store.put("uploads/x.pgn", b"data")
        assert full == "tenant-1/uploads/x.pgn"
        assert ("bucket", "tenant-1/uploads/x.pgn") in fake_client.objects
        # Reads resolve through the prefix too
        assert await store.get("uploads/x.pgn") == b"data"

    @pytest.mark.asyncio
    async def test_close_releases_client(self, s3, fake_client):
        await s3.close()
        assert fake_client.closed is True


# ---------------------------------------------------------------------------
# Presigned URLs
# ---------------------------------------------------------------------------

class TestPresignedUrls:
    def test_presign_get_contains_key_and_expiry(self, s3, fake_client):
        url = s3.presign_get("exports/db.pgn", expires=900)
        assert "exports/db.pgn" in url
        assert "expires=900" in url
        op, params, exp = fake_client.presigned_calls[-1]
        assert op == "get_object"
        assert params["Bucket"] == "test-bucket"
        assert exp == 900

    def test_presign_put_uses_default_expiry(self, s3, fake_client):
        url = s3.presign_put("uploads/incoming.pgn")
        assert "uploads/incoming.pgn" in url
        _, params, exp = fake_client.presigned_calls[-1]
        assert exp == 3600  # default

    def test_presign_put_with_content_type(self, s3, fake_client):
        s3.presign_put("uploads/x.pgn", content_type="application/x-chess-pgn")
        _, params, _ = fake_client.presigned_calls[-1]
        assert params["ContentType"] == "application/x-chess-pgn"

    def test_presign_respects_prefix(self, fake_client):
        store = S3Store("bucket", prefix="p", client=fake_client)
        url = store.presign_get("k.bin")
        assert "/p/k.bin" in url

    def test_presign_rejects_traversal(self, s3):
        with pytest.raises(ObjectKeyError):
            s3.presign_get("../../etc/passwd")


# ---------------------------------------------------------------------------
# Key sanitization
# ---------------------------------------------------------------------------

class TestSanitizeKey:
    @pytest.mark.parametrize("key", ["../secret", "a/../../b", "..", "uploads/../../../etc/passwd"])
    def test_rejects_traversal(self, key):
        with pytest.raises(ObjectKeyError):
            sanitize_key(key)

    @pytest.mark.parametrize("key", ["", "   ", "/", "a\x00b", " lead", "trail "])
    def test_rejects_malformed(self, key):
        with pytest.raises(ObjectKeyError):
            sanitize_key(key)

    @pytest.mark.parametrize("raw,expected", [
        ("uploads/db1/game.pgn", "uploads/db1/game.pgn"),
        ("//uploads//x.pgn/", "uploads/x.pgn"),
        ("a\\b\\c.pgn", "a/b/c.pgn"),
        ("./a/./b.pgn", "a/b.pgn"),
    ])
    def test_normalizes(self, raw, expected):
        assert sanitize_key(raw) == expected


# ---------------------------------------------------------------------------
# LocalDiskStore
# ---------------------------------------------------------------------------

class TestLocalDiskStore:
    @pytest.mark.asyncio
    async def test_roundtrip(self, tmp_path):
        store = LocalDiskStore(str(tmp_path))
        key = await store.put("uploads/db1/game.pgn", b"pgn-bytes")
        assert key == "uploads/db1/game.pgn"
        assert (tmp_path / "uploads" / "db1" / "game.pgn").read_bytes() == b"pgn-bytes"
        assert await store.get("uploads/db1/game.pgn") == b"pgn-bytes"
        assert await store.exists("uploads/db1/game.pgn") is True
        assert await store.delete("uploads/db1/game.pgn") is True
        assert await store.get("uploads/db1/game.pgn") is None
        assert await store.delete("uploads/db1/game.pgn") is False

    @pytest.mark.asyncio
    async def test_traversal_rejected(self, tmp_path):
        store = LocalDiskStore(str(tmp_path))
        with pytest.raises(ObjectKeyError):
            await store.put("../escape.txt", b"x")
        with pytest.raises(ObjectKeyError):
            await store.get("../escape.txt")

    def test_presign_raises(self, tmp_path):
        store = LocalDiskStore(str(tmp_path))
        with pytest.raises(RuntimeError):
            store.presign_get("a.bin")
        with pytest.raises(RuntimeError):
            store.presign_put("a.bin")


# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------

class TestFactories:
    def test_from_env_none_without_bucket(self):
        assert S3Store.from_env({}) is None

    def test_from_env_builds_with_bucket(self):
        store = S3Store.from_env({
            "S3_BUCKET": "prod-bucket",
            "S3_ENDPOINT": "https://r2.example.com",
            "S3_KEY": "ak",
            "S3_SECRET": "sk",
            "S3_REGION": "auto",
            "S3_PREFIX": "scidb",
        })
        assert isinstance(store, S3Store)
        assert store.bucket == "prod-bucket"
        assert store.prefix == "scidb"
        assert store._client_kwargs["endpoint_url"] == "https://r2.example.com"
        assert store._client_kwargs["region_name"] == "auto"

    def test_get_object_store_s3(self):
        store = get_object_store({"S3_BUCKET": "b"})
        assert isinstance(store, S3Store)

    def test_get_object_store_local_default(self):
        store = get_object_store({})
        assert isinstance(store, LocalDiskStore)
        assert store.root.endswith("data")

    def test_get_object_store_local_custom_dir(self, tmp_path):
        store = get_object_store({"DATA_DIR": str(tmp_path)})
        assert isinstance(store, LocalDiskStore)
        assert store.root == str(tmp_path)
