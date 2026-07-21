#!/usr/bin/env python3
"""
engines/sandbox.py — Sandboxing primitives for UCI engine subprocesses.

This module provides the defense-in-depth layers used when the runtime
adapter spawns a chess engine:

1. **Binary allowlist** — only explicitly allowlisted engine executables may
   be spawned (``parse_engine_allowlist`` / ``validate_engine_binary``).
2. **POSIX rlimits** — applied in the child via ``preexec_fn``
   (``build_preexec_fn``): address-space, CPU-time, file-descriptor and
   file-size caps.
3. **RSS watchdog** — an async task that polls the child's resident set size
   (via ``psutil`` when installed, otherwise ``/proc/<pid>/status`` on Linux)
   and kills the whole process group when the limit is exceeded
   (``rss_watchdog``).
4. **Optional namespace sandbox** — the engine command line can be wrapped in
   `bubblewrap <https://github.com/containers/bubblewrap>`_ (``bwrap``) or
   `firejail <https://firejail.wordpress.com/>`_ when available
   (``detect_sandbox_backend`` / ``wrap_engine_argv``). The wrapper drops
   network access and makes the filesystem read-only for the engine.

All layers degrade gracefully: if ``psutil`` is missing the watchdog falls
back to ``/proc``; if neither bwrap nor firejail is installed the backend
resolves to ``"none"`` (the rlimit layer + watchdog still apply).

Only POSIX platforms support ``preexec_fn`` / rlimits; on other platforms the
rlimit layer is a no-op (the watchdog still works when RSS can be read).
"""

from __future__ import annotations

import asyncio
import inspect
import os
import shutil
import signal
import sys
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Optional, Sequence, Union

__all__ = [
    "EngineNotAllowedError",
    "EngineSandboxConfig",
    "parse_engine_allowlist",
    "validate_engine_binary",
    "detect_sandbox_backend",
    "build_preexec_fn",
    "wrap_engine_argv",
    "read_rss_bytes",
    "rss_watchdog",
    "kill_process_tree",
]

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_NOFILE_LIMIT = 256        # max open file descriptors for the engine
DEFAULT_FSIZE_MB = 64             # max file size the engine may create
DEFAULT_WATCHDOG_INTERVAL_S = 0.5

_MB = 1024 * 1024


class EngineNotAllowedError(PermissionError):
    """Raised when an engine binary fails allowlist validation."""


@dataclass
class EngineSandboxConfig:
    """Resource limits and sandbox settings for one engine process.

    Attributes:
        memory_mb: Max resident set size in MiB. Enforced by the async RSS
            watchdog. ``0`` disables the watchdog.
        rlimit_as_mb: Optional hard ``RLIMIT_AS`` (virtual address space) cap
            in MiB. ``None`` disables it. Note that engines ``mmap`` large
            regions (hash tables), so this must be generous when set; the RSS
            watchdog is the primary memory guard.
        cpu_time_s: Optional ``RLIMIT_CPU`` cap in seconds of CPU time.
            ``None`` disables it (wall-clock ``time_limit_s`` on the worker
            is usually the better bound).
        nofile: ``RLIMIT_NOFILE`` cap (open file descriptors).
        fsize_mb: ``RLIMIT_FSIZE`` cap in MiB (files the engine creates).
        sandbox_backend: ``"auto"`` | ``"none"`` | ``"bwrap"`` | ``"firejail"``.
        watchdog_interval_s: RSS poll interval for the watchdog.
    """

    memory_mb: int = 512
    rlimit_as_mb: Optional[int] = None
    cpu_time_s: Optional[int] = None
    nofile: int = DEFAULT_NOFILE_LIMIT
    fsize_mb: int = DEFAULT_FSIZE_MB
    sandbox_backend: str = "auto"
    watchdog_interval_s: float = DEFAULT_WATCHDOG_INTERVAL_S


# ---------------------------------------------------------------------------
# Binary allowlist
# ---------------------------------------------------------------------------

def parse_engine_allowlist(env_value: str, *default_entries: str) -> list[str]:
    """Parse an allowlist from an environment variable plus defaults.

    ``env_value`` may contain comma- or ``os.pathsep``-separated entries.
    Each entry is either an executable file or a directory (any executable
    directly inside a directory entry is allowed, resolved by realpath).

    When ``env_value`` is blank, ``default_entries`` are used instead. This
    lets an operator *replace* the built-in allowlist by setting
    ``SCIDB_ENGINE_ALLOWLIST`` explicitly.
    """
    raw = env_value.strip()
    if raw:
        parts: list[str] = []
        for chunk in raw.split(","):
            parts.extend(p for p in chunk.split(os.pathsep) if p.strip())
        entries = [p.strip() for p in parts if p.strip()]
    else:
        entries = [e for e in default_entries if e]
    # Normalise: keep original spelling but resolve "." / "..".
    return [os.path.normpath(e) for e in entries]


def validate_engine_binary(path: str, allowlist: Sequence[str]) -> str:
    """Validate *path* against *allowlist* and return its canonical real path.

    Checks, in order: non-empty, exists, is a regular file, is executable,
    and the **resolved real path** matches an allowlist entry (exact match for
    file entries, or directly-under for directory entries). Resolving the
    real path first means a symlink inside an allowed directory cannot escape
    to a binary outside the allowlist.

    Raises:
        EngineNotAllowedError: when any check fails.
    """
    if not path or not isinstance(path, str):
        raise EngineNotAllowedError("empty engine path")

    real = os.path.realpath(path)

    if not os.path.exists(real):
        raise EngineNotAllowedError(f"engine binary does not exist: {path!r}")
    if not os.path.isfile(real):
        raise EngineNotAllowedError(f"engine path is not a regular file: {path!r}")
    if not os.access(real, os.X_OK):
        raise EngineNotAllowedError(f"engine binary is not executable: {path!r}")

    for entry in allowlist:
        entry_real = os.path.realpath(entry)
        if os.path.isdir(entry_real):
            parent = entry_real.rstrip(os.sep) + os.sep
            if real.startswith(parent):
                return real
        elif real == entry_real:
            return real

    raise EngineNotAllowedError(
        f"engine binary {real!r} is not in the engine allowlist"
    )


# ---------------------------------------------------------------------------
# POSIX rlimits (applied in the child via preexec_fn)
# ---------------------------------------------------------------------------

def build_preexec_fn(config: EngineSandboxConfig) -> Optional[Callable[[], None]]:
    """Return a ``preexec_fn`` applying *config*'s rlimits, or ``None``.

    The returned callable runs in the child process after fork, before exec.
    Each limit is applied independently; a failure for one limit (e.g. an
    ``RLIMIT`` the platform doesn't support) is reported on stderr but does
    not abort the spawn — limits are defense-in-depth, with the RSS watchdog
    as the primary memory guard.

    Returns ``None`` on non-POSIX platforms or when there is nothing to apply
    (``resource`` unavailable), in which case the caller must omit the
    ``preexec_fn`` argument entirely.
    """
    if os.name != "posix":
        return None
    try:
        import resource
    except ImportError:  # pragma: no cover - non-POSIX
        return None

    def _apply(name: str, limit: int, value: int) -> None:
        try:
            resource.setrlimit(limit, (value, value))
        except (ValueError, OSError) as exc:  # pragma: no cover - platform specific
            print(f"sandbox: could not set {name}={value}: {exc}", file=sys.stderr)

    def preexec() -> None:
        _apply("RLIMIT_NOFILE", resource.RLIMIT_NOFILE, max(16, config.nofile))
        _apply("RLIMIT_FSIZE", resource.RLIMIT_FSIZE, max(1, config.fsize_mb) * _MB)
        if config.rlimit_as_mb:
            _apply("RLIMIT_AS", resource.RLIMIT_AS, config.rlimit_as_mb * _MB)
        if config.cpu_time_s:
            _apply("RLIMIT_CPU", resource.RLIMIT_CPU, max(1, int(config.cpu_time_s)))

    return preexec


# ---------------------------------------------------------------------------
# Namespace sandbox wrappers (bubblewrap / firejail)
# ---------------------------------------------------------------------------

def detect_sandbox_backend(preference: str = "auto") -> str:
    """Resolve *preference* to ``"bwrap"``, ``"firejail"`` or ``"none"``.

    ``"auto"`` prefers bubblewrap (lighter, no setuid requirement on most
    distros) and falls back to firejail, then to ``"none"``. An explicit
    ``"bwrap"``/``"firejail"`` preference that is not installed also resolves
    to ``"none"`` — the caller should log a warning in that case.
    """
    pref = (preference or "auto").strip().lower()
    if pref in ("none", "off", "disabled"):
        return "none"
    have_bwrap = shutil.which("bwrap") is not None
    have_firejail = shutil.which("firejail") is not None
    if pref == "bwrap":
        return "bwrap" if have_bwrap else "none"
    if pref == "firejail":
        return "firejail" if have_firejail else "none"
    # auto
    if have_bwrap:
        return "bwrap"
    if have_firejail:
        return "firejail"
    return "none"


def wrap_engine_argv(argv: Sequence[str], backend: str = "none") -> list[str]:
    """Return *argv* wrapped for *backend* (``"bwrap"``/``"firejail"``/``"none"``).

    The engine path is canonicalised with ``realpath`` first. The bwrap
    profile:

    * ``--die-with-parent`` — engine dies if the adapter dies;
    * ``--unshare-net`` / ``--unshare-ipc`` — no network, no SysV IPC;
    * read-only binds of the system library roots and the engine binary;
    * a fresh ``--tmpfs /tmp`` as the only writable location, with the
      engine binary re-bound into it afterwards when it lives under /tmp;
    * ``--chdir /tmp`` so the engine never writes into the repo.

    The firejail profile uses ``--noprofile --net=none --private-tmp``.
    """
    engine = os.path.realpath(argv[0])
    rest = list(argv[1:])

    if backend == "bwrap":
        cmd = [
            "bwrap",
            "--die-with-parent",
            "--unshare-net",
            "--unshare-ipc",
            "--dev", "/dev",
        ]
        for d in ("/usr", "/lib", "/lib64", "/bin", "/sbin", "/etc"):
            if os.path.exists(d):
                cmd += ["--ro-bind", d, d]
        # Fresh /tmp first so it is the only writable location ...
        cmd += ["--tmpfs", "/tmp"]
        # ... then re-bind the engine binary itself (covers engines installed
        # under /tmp, which the tmpfs would otherwise shadow).
        cmd += ["--ro-bind", engine, engine]
        cmd += ["--chdir", "/tmp", "--", engine]
        return cmd + rest

    if backend == "firejail":
        return [
            "firejail",
            "--quiet",
            "--noprofile",
            "--net=none",
            "--private-tmp",
            "--",
            engine,
        ] + rest

    return [engine] + rest


# ---------------------------------------------------------------------------
# RSS watchdog
# ---------------------------------------------------------------------------

def _read_rss_procfs(pid: int) -> Optional[int]:
    """Read VmRSS from /proc/<pid>/status (Linux). Returns bytes or None."""
    try:
        with open(f"/proc/{pid}/status", "r", encoding="ascii", errors="replace") as fh:
            for line in fh:
                if line.startswith("VmRSS:"):
                    # Format: "VmRSS:\t   12345 kB"
                    parts = line.split()
                    if len(parts) >= 2:
                        return int(parts[1]) * 1024
                    return None
    except (OSError, ValueError):
        return None
    return None


def read_rss_bytes(pid: int) -> Optional[int]:
    """Return the resident set size of *pid* in bytes, or ``None``.

    Tries ``psutil`` first (portable), then falls back to
    ``/proc/<pid>/status`` on Linux. Returns ``None`` when the value cannot
    be determined (process gone or unsupported platform).
    """
    try:
        import psutil  # type: ignore

        try:
            return int(psutil.Process(pid).memory_info().rss)
        except psutil.NoSuchProcess:
            return None
        except Exception:
            pass  # fall through to procfs
    except ImportError:
        pass

    if sys.platform.startswith("linux"):
        return _read_rss_procfs(pid)
    return None


def kill_process_tree(proc: Any) -> None:
    """Kill *proc* and its whole process group (best effort).

    The engine is spawned with ``start_new_session=True`` so its PID is also
    its process-group id; ``killpg`` therefore reaches engine-spawned helper
    processes (and a bwrap/firejail wrapper) too. Falls back to killing just
    the direct child when ``killpg`` is unavailable.
    """
    pid = getattr(proc, "pid", None)
    if pid is None:
        return
    killed = False
    if hasattr(os, "killpg"):
        try:
            os.killpg(pid, signal.SIGKILL)
            killed = True
        except (ProcessLookupError, PermissionError, OSError):
            killed = False
    if not killed:
        try:
            proc.kill()
        except (ProcessLookupError, OSError):
            pass


async def rss_watchdog(
    proc: Any,
    limit_bytes: int,
    on_exceed: Optional[Callable[[int], Union[None, Awaitable[None]]]] = None,
    interval: float = DEFAULT_WATCHDOG_INTERVAL_S,
) -> None:
    """Poll *proc*'s RSS and kill the process group when *limit_bytes* is exceeded.

    Intended to be run as an ``asyncio.Task`` alongside the UCI read loop.
    Exits when the process exits, when the task is cancelled, or after
    killing the process. ``on_exceed`` (sync or async callable receiving the
    observed RSS in bytes) is invoked once, right after the kill.

    When RSS cannot be read on this platform the watchdog simply keeps
    polling until the process exits — it never kills on missing data.
    """
    try:
        while getattr(proc, "returncode", None) is None:
            await asyncio.sleep(interval)
            if getattr(proc, "returncode", None) is not None:
                break
            rss = read_rss_bytes(proc.pid)
            if rss is not None and rss > limit_bytes:
                kill_process_tree(proc)
                if on_exceed is not None:
                    result = on_exceed(rss)
                    if inspect.isawaitable(result):
                        await result
                return
    except asyncio.CancelledError:
        raise
