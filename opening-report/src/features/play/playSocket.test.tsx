import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { createPlaySocket } from './playSocket';
import type { PlayEvent } from '@/types';

// Stub the browser WebSocket so WsPlaySocket can be exercised in jsdom.
class StubWebSocket {
  static last: StubWebSocket | null = null;
  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onmessage: ((ev: { data: string }) => void) | null = null;
  url: string;
  constructor(url: string) {
    this.url = url;
    StubWebSocket.last = this;
    setTimeout(() => this.onopen?.(), 0);
  }
  close() {
    this.onclose?.();
  }
  emit(data: unknown) {
    this.onmessage?.({ data: JSON.stringify(data) });
  }
}

beforeEach(() => {
  (window as unknown as { SCIDB_PLAY_WS: unknown }).SCIDB_PLAY_WS = 1;
  (globalThis as unknown as { WebSocket: unknown }).WebSocket = StubWebSocket;
  StubWebSocket.last = null;
});

afterEach(() => {
  delete (window as unknown as { SCIDB_PLAY_WS?: unknown }).SCIDB_PLAY_WS;
  vi.restoreAllMocks();
});

describe('playSocket — WS transport (Phase 4)', () => {
  it('forwards match.move events to subscribers', async () => {
    const socket = createPlaySocket();
    const events: PlayEvent[] = [];
    const unsub = socket.subscribe((e) => events.push(e));
    await new Promise((r) => setTimeout(r, 10));
    StubWebSocket.last!.emit({
      type: 'match.move',
      matchId: 'm1',
      move: { ply: 1, san: 'e4', uci: 'e2e4', fen: 'x', clockMsAfter: 0, latencyMs: 0 },
      clocks: { whiteMs: 178000, blackMs: 180000 },
      clockUpdatedAt: Date.now(),
    });
    expect(events.some((e) => e.type === 'match.move')).toBe(true);
    unsub();
  });

  it('turns a seek.list payload into seek.created events', async () => {
    const socket = createPlaySocket();
    const events: PlayEvent[] = [];
    const unsub = socket.subscribe((e) => events.push(e));
    await new Promise((r) => setTimeout(r, 10));
    StubWebSocket.last!.emit({
      type: 'seek.list',
      seeks: [
        {
          id: 's1',
          owner: { id: 'other', name: 'Other', rating: 1500 },
          timeControl: { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2 },
          variant: 'standard', rated: false, color: 'w', ratingRange: null, createdAt: 0,
        },
      ],
    });
    expect(events.some((e) => e.type === 'seek.created' && e.seek.id === 's1')).toBe(true);
    unsub();
  });
});