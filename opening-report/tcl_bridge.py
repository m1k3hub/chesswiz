"""
tcl_bridge.py — Async Tcl bridge client for the scidb-beta runtime adapter.

Two modes are supported:

1. **Per-call script mode** (legacy, no backend interpreter needed):
   ``TCL_BRIDGE_PATH`` points to a Tcl script that is invoked once per
   request.  This is used by the bundled ``tcl_bridge_sample.tcl`` and for
   simple shell-out integrations.

2. **Persistent interpreter mode** (real scidb C++/Tcl backend):
   ``TCL_INTERP`` points to the compiled scidb interpreter
   (e.g. ``/path/to/src/tkscidb-beta``) and ``TCL_BRIDGE_PATH`` points to a
   Tcl script (e.g. ``tcl_bridge_real.tcl``).  The interpreter is spawned
   once, kept alive, and requests are exchanged as JSON lines over stdin/
   stdout.  If no X11 display is available the client automatically wraps
   the interpreter with ``xvfb-run -a``.

In both modes, if the bridge is unavailable or returns an error, every
public method returns ``None`` so the caller can fall back to mock data.

Protocol (per-call mode)
------------------------

The bridge is invoked as::

    <bridge_path> <method> <endpoint> [json_body]

For example::

    tcl_bridge_sample.tcl GET /api/databases
    tcl_bridge_sample.tcl POST /api/searches '{"type":"advanced","query":{}}'

The bridge must print exactly one JSON value to stdout.  If the exit code is
non-zero the response is treated as an error and ``None`` is returned.

Protocol (persistent mode)
--------------------------

The interpreter is launched with the bridge script as its first argument::

    xvfb-run -a <tkscidb-beta> <tcl_bridge_real.tcl>

The bridge prints a handshake line to stdout::

    {"__scidb_ready": true}

After that, each request is one JSON line on stdin::

    {"method": "GET", "endpoint": "/api/databases", "body": {}}

and each response is one JSON line on stdout.  If the bridge wants the
adapter to fall back to mock data it returns::

    {"__scidb_fallback": true}

Usage from runtime_adapter::

    from tcl_bridge import TclBridge

    bridge = TclBridge()
    if bridge.is_available():
        databases = await bridge.list_databases()
"""

from __future__ import annotations

import asyncio
import json
import os
import shutil
from typing import Any, Optional

# ---------------------------------------------------------------------------
# Bridge client
# ---------------------------------------------------------------------------

DEFAULT_TIMEOUT = 30  # seconds


class TclBridge:
    """Async wrapper around a Tcl bridge executable or persistent interpreter.

    The bridge is *enabled* when ``TCL_BRIDGE_PATH`` points to an existing
    file.  In persistent mode ``TCL_INTERP`` must additionally point to the
    scidb Tcl interpreter binary.  All public methods return ``None`` when the
    bridge is disabled or the subprocess fails.
    """

    def __init__(self, path: Optional[str] = None, timeout: int = DEFAULT_TIMEOUT) -> None:
        self.path = path or os.environ.get("TCL_BRIDGE_PATH", "")
        self.interp = os.environ.get("TCL_INTERP", "")
        self.database = os.environ.get("SCIDB_DATABASE", "")
        self.timeout = timeout
        self._proc: Optional[asyncio.subprocess.Process] = None
        self._stderr_task: Optional[asyncio.Task] = None
        self._lock = asyncio.Lock()

    # -- lifecycle --------------------------------------------------------

    def _script_exists(self) -> bool:
        if not self.path:
            return False
        if os.path.isfile(self.path):
            return True
        return bool(shutil.which(self.path))

    def _interp_exists(self) -> bool:
        if not self.interp:
            return False
        return os.path.isfile(self.interp) or bool(shutil.which(self.interp))

    def is_available(self) -> bool:
        """Return True when the bridge can be invoked.

        For per-call mode ``TCL_BRIDGE_PATH`` must exist.  For persistent
        mode both ``TCL_INTERP`` and ``TCL_BRIDGE_PATH`` must exist.
        """
        if not self._script_exists():
            return False
        if self.interp:
            return self._interp_exists()
        return True

    async def _ensure_proc(self) -> bool:
        """Start the persistent interpreter and perform the handshake."""
        async with self._lock:
            if self._proc is not None and self._proc.returncode is None:
                return True

            # If a previous process died, clean it up.
            if self._proc is not None:
                await self._close_proc()

            if not self.is_available():
                return False

            args: list[str] = [self.interp, self.path]
            if not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
                args = ["xvfb-run", "-a", *args]

            try:
                self._proc = await asyncio.create_subprocess_exec(
                    *args,
                    stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
            except OSError as exc:
                print(f"[tcl_bridge] failed to start interpreter: {exc}")
                return False

            # Drain stderr in the background so the pipe never blocks.
            self._stderr_task = asyncio.create_task(self._drain_stderr())

            # Wait for the handshake line.
            try:
                line = await asyncio.wait_for(
                    self._readline(),
                    timeout=max(self.timeout, 30),
                )
            except asyncio.TimeoutError:
                print("[tcl_bridge] interpreter handshake timed out")
                await self._close_proc()
                return False
            except Exception as exc:
                print(f"[tcl_bridge] interpreter handshake failed: {exc}")
                await self._close_proc()
                return False

            try:
                handshake = json.loads(line)
                if not handshake.get("__scidb_ready"):
                    print(f"[tcl_bridge] unexpected handshake: {line}")
                    await self._close_proc()
                    return False
            except json.JSONDecodeError:
                print(f"[tcl_bridge] invalid handshake: {line}")
                await self._close_proc()
                return False

            return True

    async def _readline(self) -> str:
        if self._proc is None or self._proc.stdout is None:
            raise RuntimeError("interpreter not running")
        data = await self._proc.stdout.readline()
        if not data:
            raise RuntimeError("interpreter closed stdout")
        return data.decode(errors="replace").strip()

    async def _drain_stderr(self) -> None:
        if self._proc is None or self._proc.stderr is None:
            return
        try:
            while True:
                line = await self._proc.stderr.readline()
                if not line:
                    break
                text = line.decode(errors="replace").rstrip()
                if text:
                    print(f"[tcl_bridge stderr] {text}")
        except Exception:
            pass

    async def _close_proc(self) -> None:
        if self._proc is None:
            return
        try:
            if self._proc.returncode is None:
                self._proc.kill()
                await self._proc.wait()
        except Exception:
            pass
        self._proc = None
        if self._stderr_task is not None:
            self._stderr_task.cancel()
            self._stderr_task = None

    def close(self) -> None:
        """Release the persistent interpreter if one is running."""
        if self._proc is None:
            return
        try:
            loop = asyncio.get_running_loop()
            loop.create_task(self._close_proc())
        except RuntimeError:
            pass

    # -- low-level call ---------------------------------------------------

    def _should_fallback(self, data: Any) -> bool:
        return isinstance(data, dict) and data.get("__scidb_fallback") is True

    async def _call_per_call(self, method: str, endpoint: str, body: Optional[dict]) -> Any:
        """One-shot subprocess invocation for script-only mode."""
        args: list[str] = [self.path, method, endpoint]
        if body is not None:
            args.append(json.dumps(body))
        try:
            proc = await asyncio.create_subprocess_exec(
                *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=self.timeout)
            if proc.returncode != 0:
                err = stderr.decode(errors="replace").strip() if stderr else ""
                print(f"[tcl_bridge] {method} {endpoint} failed (exit {proc.returncode}): {err}")
                return None
            text = stdout.decode(errors="replace").strip()
            if not text:
                return None
            data = json.loads(text)
            if self._should_fallback(data):
                return None
            return data
        except asyncio.TimeoutError:
            print(f"[tcl_bridge] {method} {endpoint} timed out after {self.timeout}s")
            return None
        except (json.JSONDecodeError, OSError, Exception) as exc:
            print(f"[tcl_bridge] {method} {endpoint} error: {exc}")
            return None

    async def _call_persistent(self, method: str, endpoint: str, body: Optional[dict]) -> Any:
        """JSON-line RPC to the persistent interpreter."""
        if not await self._ensure_proc():
            return None

        req = {"method": method, "endpoint": endpoint, "body": body or {}}
        assert self._proc is not None
        assert self._proc.stdin is not None
        try:
            self._proc.stdin.write((json.dumps(req) + "\n").encode())
            await self._proc.stdin.drain()

            line = await asyncio.wait_for(self._readline(), timeout=self.timeout)
            data = json.loads(line)
            if self._should_fallback(data):
                return None
            return data
        except asyncio.TimeoutError:
            print(f"[tcl_bridge] {method} {endpoint} timed out after {self.timeout}s")
            return None
        except (json.JSONDecodeError, RuntimeError, Exception) as exc:
            print(f"[tcl_bridge] {method} {endpoint} error: {exc}")
            # If the process died, clear it so the next call can retry.
            await self._close_proc()
            return None

    async def _call(self, method: str, endpoint: str, body: Optional[dict] = None) -> Any:
        """Invoke the bridge and return parsed JSON, or ``None`` on error."""
        if not self.is_available():
            return None
        if self.interp:
            return await self._call_persistent(method, endpoint, body)
        return await self._call_per_call(method, endpoint, body)

    # -- public API (one method per adapter endpoint) ---------------------

    async def list_databases(self) -> Optional[list[dict]]:
        """GET /api/databases → list of Database dicts."""
        return await self._call("GET", "/api/databases")

    async def list_games(self, database_id: str) -> Optional[list[dict]]:
        """GET /api/databases/:id/games → list of GameSummary dicts."""
        return await self._call("GET", f"/api/databases/{database_id}/games")

    async def get_game(self, game_id: str) -> Optional[dict]:
        """GET /api/games/:id → GameDetail dict."""
        return await self._call("GET", f"/api/games/{game_id}")

    async def search(self, payload: dict) -> Optional[dict]:
        """POST /api/searches → search job reference dict."""
        return await self._call("POST", "/api/searches", payload)

    async def get_search_results(self, job_id: str) -> Optional[dict]:
        """GET /api/searches/:id/results → full search results."""
        return await self._call("GET", f"/api/searches/{job_id}/results")

    async def tree_query(self, payload: dict) -> Optional[list[dict]]:
        """POST /api/tree/query → list of OpeningMove dicts."""
        return await self._call("POST", "/api/tree/query", payload)

    async def start_analysis(self, payload: dict) -> Optional[dict]:
        """POST /api/analysis/start → analysis job reference."""
        return await self._call("POST", "/api/analysis/start", payload)

    async def get_analysis(self, job_id: str) -> Optional[dict]:
        """GET /api/analysis/:id → AnalysisJob dict."""
        return await self._call("GET", f"/api/analysis/{job_id}")

    async def stop_analysis(self, job_id: str) -> Optional[dict]:
        """POST /api/analysis/:id/stop → stop confirmation."""
        return await self._call("POST", f"/api/analysis/{job_id}/stop")

    async def workspace(self) -> Optional[dict]:
        """GET /api/workspace → workspace state."""
        return await self._call("GET", "/api/workspace")
