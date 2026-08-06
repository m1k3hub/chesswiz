/**
 * playSocket — transport-agnostic event stream for online play.
 *
 * Phase 4: the real `/api/ws/play` WebSocket is used when
 * `VITE_SCIDB_PLAY_WS === '1'` (or `window.SCIDB_PLAY_WS`); otherwise the mock
 * backend (mockPlay) provides the event stream, keeping `npm run dev` without
 * the adapter fully functional. Moves are submitted via the HTTP API client in
 * both cases (the server emits match.move/match.finish back over this stream),
 * so the socket is receive-only.
 */

import type { PlayEvent, PlaySeek } from '@/types';
import { mockPlay } from './mockPlayBackend';
import { getPlayGuestId } from './playIdentity';

export interface PlaySocket {
  /** Subscribe to play events. Returns an unsubscribe function. */
  subscribe(handler: (event: PlayEvent) => void): () => void;
  /** Connection state. */
  readonly connected: boolean;
  /**
   * Real (WebSocket) transport vs in-process mock. Callers that need extra
   * polling (e.g. seek discovery the WS does not push) should only do it for
   * the real transport.
   */
  readonly isRealTransport: boolean;
  /**
   * Anti-cheat v1 signal (Phase 7): report focus-out during the opponent's
   * turn. Fire-and-forget; no-op on the mock transport.
   */
  sendBlur(matchId: string): void;
}

function wsBase(): string {
  const apiBase =
    import.meta.env?.VITE_SCIDB_API_BASE ||
    (typeof window !== 'undefined' ? window.SCIDB_API_BASE || '' : '');
  if (apiBase.startsWith('http')) return apiBase.replace(/^http/, 'ws');
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${protocol}//${window.location.host}`;
}

class WsPlaySocket implements PlaySocket {
  readonly isRealTransport = true;
  private socket: WebSocket | null = null;
  private handlers: Array<(e: PlayEvent) => void> = [];
  private _connected = false;

  constructor() {
    this.connect();
  }

  private connect() {
    const url = `${wsBase()}/api/ws/play?guest=${encodeURIComponent(getPlayGuestId())}`;
    try {
      this.socket = new WebSocket(url);
      this.socket.onopen = () => {
        this._connected = true;
      };
      this.socket.onclose = () => {
        this._connected = false;
        // Reconnect with backoff (mirrors ScidbWebSocketClient behaviour).
        setTimeout(() => this.connect(), 2000);
      };
      this.socket.onmessage = (ev) => {
        let data: unknown;
        try {
          data = JSON.parse(ev.data);
        } catch {
          return;
        }
        // The server sends seek.list and match.resync in addition to PlayEvent;
        // only forward the PlayEvent-shaped messages to subscribers.
        if (data && typeof data === 'object' && 'type' in (data as Record<string, unknown>)) {
          const t = (data as { type: string }).type;
          if (t === 'seek.created' || t === 'seek.cancelled' || t === 'match.paired' || t === 'match.move' || t === 'match.finish') {
            this.handlers.forEach((h) => h(data as PlayEvent));
          }
          if (t === 'seek.list') {
            // Refresh the seeks list from the payload.
            const seeks = (data as { seeks: PlaySeek[] }).seeks || [];
            seeks.forEach((s) => this.handlers.forEach((h) => h({ type: 'seek.created', seek: s })));
          }
        }
      };
    } catch {
      this._connected = false;
      setTimeout(() => this.connect(), 2000);
    }
  }

  get connected() {
    return this._connected;
  }

  subscribe(handler: (e: PlayEvent) => void): () => void {
    this.handlers.push(handler);
    return () => {
      this.handlers = this.handlers.filter((h) => h !== handler);
    };
  }

  sendBlur(matchId: string): void {
    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      this.socket.send(JSON.stringify({ type: 'blur', matchId }));
    }
  }
}

class MockPlaySocket implements PlaySocket {
  readonly isRealTransport = false;
  connected = false;
  subscribe(handler: (e: PlayEvent) => void): () => void {
    this.connected = true;
    return mockPlay.subscribe(handler);
  }
  sendBlur(): void {
    // No anti-cheat signal in the local mock backend.
  }
}

export function createPlaySocket(): PlaySocket {
  const enabled =
    import.meta.env?.VITE_SCIDB_PLAY_WS === '1' ||
    (typeof window !== 'undefined' && (window as { SCIDB_PLAY_WS?: unknown }).SCIDB_PLAY_WS);
  return enabled ? new WsPlaySocket() : new MockPlaySocket();
}

let _sharedSocket: PlaySocket | null = null;

/** Shared PlaySocket instance so both usePlaySocket and blur reporting reuse one connection. */
export function getSharedPlaySocket(): PlaySocket {
  if (!_sharedSocket) _sharedSocket = createPlaySocket();
  return _sharedSocket;
}