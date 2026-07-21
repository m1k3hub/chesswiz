/**
 * engine.worker.ts — Web Worker for running a UCI engine in the browser.
 *
 * This is a minimal stub for a future path where Stockfish can run directly in
 * the browser via WebAssembly (e.g. stockfish.wasm). It receives messages of
 * the form { fen, depth, multiPv } and would post back analysis updates.
 *
 * Currently it only logs that it received the request — the actual WASM engine
 * integration is not yet implemented. The backend runtime adapter handles real
 * analysis today.
 */

interface EngineWorkerMessage {
  fen: string;
  depth?: number;
  multiPv?: number;
  engineUrl?: string;
}

self.onmessage = (event: MessageEvent<EngineWorkerMessage>) => {
  const { fen, depth = 20, multiPv = 1, engineUrl } = event.data;

  // In the future, this would:
  // 1. Fetch engineUrl (e.g. /stockfish.js or stockfish.wasm) if not already loaded
  // 2. Instantiate the WASM engine
  // 3. Send `position fen <fen>` and `go depth <depth>`
  // 4. Parse `info` lines and postMessage updates back

  console.log('[engine.worker] Analysis request received (not yet implemented):', {
    fen: fen.slice(0, 40),
    depth,
    multiPv,
    engineUrl,
  });

  // Post a placeholder response so callers know the worker is alive
  (self as unknown as Worker).postMessage({
    type: 'analysis.worker-not-implemented',
    fen,
    depth,
    multiPv,
    message: 'Browser Web Worker engine is a stub. Use the backend runtime adapter for real analysis.',
  });
};

export {};