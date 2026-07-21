#!/usr/bin/env python3
"""
stockfish_worker.py — Async UCI engine worker for the scidb-beta runtime adapter.

Starts a UCI engine (Stockfish or any compatible binary) as a subprocess,
sends ``position fen <fen>`` and ``go depth <depth>`` (or ``go movetime <ms>``),
parses ``info`` lines for depth / nodes / nps / multipv / score / pv, and
streams updates back through an ``asyncio.Queue``.

Sandboxing and resource limits (see ``engines/sandbox.py``):

    threads        UCI ``Threads`` option (engine search threads).
    hash_mb        UCI ``Hash`` option in MiB (engine transposition table).
    memory_mb      Max RSS in MiB, enforced by an async watchdog that kills
                   the whole process group when exceeded.
    cpu_limit      Advisory CPU percent (reserved; not enforced by rlimits —
                   CPU time is better bounded via ``time_limit_s`` or
                   ``EngineSandboxConfig.cpu_time_s``).
    time_limit_s   Max wall-clock seconds for the analysis.
    sandbox        Optional ``EngineSandboxConfig`` controlling rlimits
                   (applied via ``preexec_fn``), the RSS watchdog interval,
                   and the bwrap/firejail namespace wrapper.
    allowlist      Optional sequence of allowlisted engine paths/dirs. When
                   given, the engine binary is validated with
                   ``validate_engine_binary`` before spawn.

The engine always runs in its own session (``start_new_session=True``) so
the watchdog and ``stop``/``quit`` can kill the entire process group.

Usage from the runtime adapter::

    worker = UciWorker(engine_path, threads=2, hash_mb=128)
    await worker.start(fen, depth=20, multi_pv=3, queue=out_queue)
    # … consumer reads from out_queue until a terminal message arrives …

Terminal queue messages:

    {"type": "analysis.complete", ...}            # bestmove / stop / timeout
    {"type": "analysis.error", "error": "memory-limit-exceeded", ...}
"""

from __future__ import annotations

import asyncio
import os
import re
import time
from typing import Any, Dict, List, Optional, Sequence

from engines.sandbox import (
    EngineSandboxConfig,
    build_preexec_fn,
    detect_sandbox_backend,
    kill_process_tree,
    rss_watchdog,
    validate_engine_binary,
    wrap_engine_argv,
)


# ---------------------------------------------------------------------------
# UCI info-line parser
# ---------------------------------------------------------------------------

_INFO_RE = re.compile(r"^info\s+(?:depth\s+(\d+)\s+)?(.*)")
_SCORE_RE = re.compile(r"score\s+(cp\s+(-?\d+)|mate\s+(-?\d+))")
_PV_RE = re.compile(r"(?:^|\s)pv\s+(.+?)(?:\s+(?:score|nodes|nps|hashfull|tbhits|time|seldepth|currmove|currline|refutation)\s+|$)")
_MULTIPV_RE = re.compile(r"multipv\s+(\d+)")
_NODES_RE = re.compile(r"nodes\s+(\d+)")
_NPS_RE = re.compile(r"nps\s+(\d+)")


def parse_info_line(line: str) -> Optional[Dict[str, Any]]:
    """Parse a single UCI ``info`` line into a structured dict.

    Returns ``None`` if the line is not a usable info line (e.g. ``info string``).
    """
    line = line.strip()
    if not line.startswith("info"):
        return None

    # Skip non-search info lines like "info string ..."
    if line.startswith("info string"):
        return None

    result: Dict[str, Any] = {}

    depth_match = _INFO_RE.match(line)
    if depth_match and depth_match.group(1):
        result["depth"] = int(depth_match.group(1))

    score_match = _SCORE_RE.search(line)
    if score_match:
        if score_match.group(2) is not None:
            cp = int(score_match.group(2))
            result["eval"] = f"{cp / 100:+.2f}"
        elif score_match.group(3) is not None:
            mate = int(score_match.group(3))
            result["eval"] = f"M{mate:+d}"

    multipv_match = _MULTIPV_RE.search(line)
    if multipv_match:
        result["multipv"] = int(multipv_match.group(1))

    pv_match = _PV_RE.search(line)
    if pv_match:
        result["pv"] = pv_match.group(1).strip()

    nodes_match = _NODES_RE.search(line)
    if nodes_match:
        result["nodes"] = int(nodes_match.group(1))

    nps_match = _NPS_RE.search(line)
    if nps_match:
        result["nps"] = int(nps_match.group(1))

    return result


# ---------------------------------------------------------------------------
# UCI Worker
# ---------------------------------------------------------------------------

class UciWorker:
    """Asynchronous wrapper around a UCI engine subprocess."""

    def __init__(
        self,
        engine_path: str,
        *,
        cpu_limit: int = 100,
        memory_mb: int = 512,
        time_limit_s: float = 30.0,
        threads: int = 1,
        hash_mb: int = 64,
        sandbox: Optional[EngineSandboxConfig] = None,
        allowlist: Optional[Sequence[str]] = None,
    ):
        if allowlist is not None:
            # Raises EngineNotAllowedError when the binary is not allowlisted.
            engine_path = validate_engine_binary(engine_path, allowlist)

        self.engine_path = engine_path
        self.cpu_limit = cpu_limit
        self.memory_mb = memory_mb
        self.time_limit_s = time_limit_s
        self.threads = max(1, int(threads))
        self.hash_mb = max(1, int(hash_mb))

        # Sandbox config: explicit one wins; otherwise derive from memory_mb.
        if sandbox is not None:
            self.sandbox = sandbox
        else:
            self.sandbox = EngineSandboxConfig(memory_mb=memory_mb)

        self._proc: Optional[asyncio.subprocess.Process] = None
        self._stop_requested = False
        self._memory_exceeded = False
        self._start_time = 0.0
        self._lines: List[Dict[str, Any]] = []  # accumulated PV lines indexed by multipv
        self._watchdog_task: Optional[asyncio.Task] = None
        self._stderr_task: Optional[asyncio.Task] = None
        self._stderr_lines: List[str] = []

    async def start(
        self,
        fen: str,
        *,
        depth: Optional[int] = None,
        movetime_ms: Optional[int] = None,
        multi_pv: int = 1,
        queue: Optional[asyncio.Queue] = None,
    ) -> None:
        """Start analysis on the given FEN and stream results to *queue*.

        Exactly one of ``depth`` or ``movetime_ms`` must be provided.
        """
        if depth is None and movetime_ms is None:
            depth = 20

        backend = detect_sandbox_backend(self.sandbox.sandbox_backend)
        argv = wrap_engine_argv([self.engine_path], backend)
        preexec_fn = build_preexec_fn(self.sandbox)

        self._proc = await asyncio.create_subprocess_exec(
            *argv,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env={**os.environ, "OMP_NUM_THREADS": str(self.threads)},
            preexec_fn=preexec_fn,
            start_new_session=True,  # own process group → killpg reaches wrappers
        )

        self._stop_requested = False
        self._memory_exceeded = False
        self._start_time = time.monotonic()
        self._lines = [{} for _ in range(multi_pv)]
        self._stderr_lines = []

        # Drain stderr continuously so a chatty engine (or bwrap warning)
        # can never deadlock on a full pipe buffer.
        self._stderr_task = asyncio.create_task(self._drain_stderr())

        # RSS watchdog: primary memory guard.
        if self.sandbox.memory_mb and self.sandbox.memory_mb > 0:
            self._watchdog_task = asyncio.create_task(
                rss_watchdog(
                    self._proc,
                    self.sandbox.memory_mb * 1024 * 1024,
                    on_exceed=self._on_memory_exceeded,
                    interval=self.sandbox.watchdog_interval_s,
                )
            )

        # UCI handshake
        await self._send("uci")
        await self._wait_for("uciok", timeout=5.0)
        await self._send(f"setoption name Threads value {self.threads}")
        await self._send(f"setoption name Hash value {self.hash_mb}")
        await self._send(f"setoption name MultiPV value {multi_pv}")
        # isready guarantees the setoption commands above were applied before
        # the search starts. The wait is deliberately short and tolerant:
        # conforming engines (Stockfish) answer in milliseconds, and legacy
        # stubs that never send readyok must not stall analysis startup.
        await self._send("isready")
        await self._wait_for("readyok", timeout=2.0)

        # Position
        await self._send(f"position fen {fen}")

        # Go
        if depth is not None:
            await self._send(f"go depth {depth}")
        else:
            await self._send(f"go movetime {movetime_ms}")

        # Read loop
        try:
            await self._read_loop(queue, multi_pv)
        finally:
            await self._cleanup()

    async def stop(self) -> None:
        """Request the engine to stop searching."""
        self._stop_requested = True
        if self._proc and self._proc.stdin:
            await self._send("stop")

    async def quit(self) -> None:
        """Send ``quit`` and kill the process if it doesn't exit."""
        if self._proc:
            try:
                await self._send("quit")
                await asyncio.wait_for(self._proc.wait(), timeout=2.0)
            except asyncio.TimeoutError:
                self._kill()
            except Exception:
                self._kill()

    # ----- internal helpers -----

    def _on_memory_exceeded(self, rss_bytes: int) -> None:
        """Watchdog callback: record the breach; the read loop reports it."""
        self._memory_exceeded = True

    async def _drain_stderr(self) -> None:
        """Consume engine stderr, keeping the last few lines for diagnostics."""
        assert self._proc is not None and self._proc.stderr is not None
        try:
            while True:
                raw = await self._proc.stderr.readline()
                if not raw:
                    break
                text = raw.decode(errors="replace").strip()
                if text:
                    self._stderr_lines.append(text)
                    if len(self._stderr_lines) > 50:
                        self._stderr_lines = self._stderr_lines[-50:]
        except Exception:
            pass

    async def _send(self, command: str) -> None:
        if self._proc and self._proc.stdin:
            self._proc.stdin.write((command + "\n").encode())
            await self._proc.stdin.drain()

    async def _wait_for(self, token: str, timeout: float = 5.0) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            remaining = max(0.05, deadline - time.monotonic())
            try:
                line = await asyncio.wait_for(self._proc.stdout.readline(), timeout=remaining)
            except asyncio.TimeoutError:
                break
            if not line:
                break
            text = line.decode(errors="replace").strip()
            if token in text:
                return
        # If we time out, continue anyway — the engine may not need a full handshake.

    async def _read_loop(self, queue: Optional[asyncio.Queue], multi_pv: int) -> None:
        """Read stdout lines, parse info, and publish updates."""
        assert self._proc is not None

        while True:
            # Check resource limits
            elapsed = time.monotonic() - self._start_time
            if elapsed > self.time_limit_s:
                await self._send("stop")
                break

            try:
                raw = await asyncio.wait_for(self._proc.stdout.readline(), timeout=1.0)
            except asyncio.TimeoutError:
                if self._stop_requested:
                    break
                continue

            if not raw:
                break

            text = raw.decode(errors="replace").strip()

            if text.startswith("bestmove"):
                break

            if text.startswith("info"):
                parsed = parse_info_line(text)
                if parsed:
                    self._merge_line(parsed, multi_pv)
                    update = self._build_update()
                    if queue:
                        await queue.put({"type": "analysis.update", **update})

        # Memory-limit breach is reported as an error, not a completion.
        if self._memory_exceeded:
            if queue:
                await queue.put({
                    "type": "analysis.error",
                    "error": "memory-limit-exceeded",
                    "limitMb": self.sandbox.memory_mb,
                    "stderr": self._stderr_lines[-5:],
                })
            return

        # Publish final
        final = self._build_update()
        final["status"] = "complete"
        if queue:
            await queue.put({"type": "analysis.complete", **final})

    def _merge_line(self, parsed: Dict[str, Any], multi_pv: int) -> None:
        """Merge a parsed info line into the accumulated state."""
        multipv_idx = parsed.get("multipv", 1) - 1
        if multipv_idx < 0 or multipv_idx >= multi_pv:
            return

        entry = self._lines[multipv_idx]
        if "depth" in parsed:
            entry["depth"] = parsed["depth"]
        if "eval" in parsed:
            entry["eval"] = parsed["eval"]
        if "pv" in parsed:
            entry["pv"] = parsed["pv"]
        if "nodes" in parsed:
            entry["nodes"] = parsed["nodes"]
        if "nps" in parsed:
            entry["nps"] = parsed["nps"]

    def _build_update(self) -> Dict[str, Any]:
        """Build a snapshot of the current analysis state."""
        lines = []
        max_depth = 0
        total_nodes = 0
        nps = 0
        for entry in self._lines:
            if entry:
                lines.append({
                    "pv": entry.get("pv", ""),
                    "eval": entry.get("eval", "0.00"),
                    "depth": entry.get("depth", 0),
                })
                if entry.get("depth", 0) > max_depth:
                    max_depth = entry["depth"]
                if entry.get("nodes"):
                    total_nodes = entry["nodes"]
                if entry.get("nps"):
                    nps = entry["nps"]

        return {
            "depth": max_depth,
            "nodes": total_nodes,
            "nps": nps,
            "lines": lines,
        }

    async def _cleanup(self) -> None:
        """Stop the watchdog/stderr tasks and terminate the engine process."""
        if self._watchdog_task and not self._watchdog_task.done():
            self._watchdog_task.cancel()
            try:
                await self._watchdog_task
            except asyncio.CancelledError:
                pass
            except Exception:
                pass
        self._watchdog_task = None

        if self._proc and self._proc.returncode is None:
            try:
                await self._send("quit")
                await asyncio.wait_for(self._proc.wait(), timeout=2.0)
            except (asyncio.TimeoutError, Exception):
                self._kill()

        if self._stderr_task and not self._stderr_task.done():
            try:
                await asyncio.wait_for(self._stderr_task, timeout=1.0)
            except (asyncio.TimeoutError, Exception):
                self._stderr_task.cancel()
        self._stderr_task = None

    def _kill(self) -> None:
        """Forcefully kill the engine process group (wrapper included)."""
        if self._proc and self._proc.returncode is None:
            kill_process_tree(self._proc)


# ---------------------------------------------------------------------------
# Convenience function
# ---------------------------------------------------------------------------

async def run_analysis(
    engine_path: str,
    fen: str,
    *,
    depth: int = 20,
    multi_pv: int = 3,
    cpu_limit: int = 100,
    memory_mb: int = 512,
    time_limit_s: float = 30.0,
    threads: int = 1,
    hash_mb: int = 64,
    sandbox: Optional[EngineSandboxConfig] = None,
    allowlist: Optional[Sequence[str]] = None,
    queue: Optional[asyncio.Queue] = None,
) -> None:
    """Run a one-shot UCI analysis and stream results to *queue*.

    If *queue* is ``None`` a new ``asyncio.Queue`` is created.
    """
    if queue is None:
        queue = asyncio.Queue()

    worker = UciWorker(
        engine_path,
        cpu_limit=cpu_limit,
        memory_mb=memory_mb,
        time_limit_s=time_limit_s,
        threads=threads,
        hash_mb=hash_mb,
        sandbox=sandbox,
        allowlist=allowlist,
    )
    await worker.start(fen, depth=depth, multi_pv=multi_pv, queue=queue)
