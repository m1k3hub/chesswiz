/**
 * play_contract.test.ts — parity contract test for online play.
 *
 * Runs the same scenarios against the in-browser MockScidbApiClient (used by
 * the SPA in Phase 2 and in unit tests) and the real HTTP client talking to
 * a live runtime_adapter (FastAPI) instance, so the two stay equivalent as
 * the plan's testing strategy (ONLINE_PLAY_PLAN.md §9) requires.
 *
 * The FastAPI app is started as a uvicorn subprocess against an in-memory
 * store (no REDIS_URL/DATABASE_URL) — mirrors how tests/test_play.py
 * exercises play_routes.py, but over real HTTP so HttpScidbApiClient's
 * fetch-based transport is exercised too.
 *
 * This spawns a live `python3 -m uvicorn` subprocess, which the plain
 * frontend CI job (`npx vitest run`) has no Python env for — so the HTTP
 * half of the suite is gated behind RUN_PLAY_CONTRACT=1 and no-ops
 * (skipped, not failed) otherwise. The mock-only scenarios still always run.
 *
 * Run:  RUN_PLAY_CONTRACT=1 npx vitest run tests/play_contract.test.ts
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { spawn, type ChildProcess } from 'node:child_process';
import { MockScidbApiClient, HttpScidbApiClient } from '../src/api/client';
import { mockPlay } from '../src/features/play/mockPlayBackend';
import type { PlayUser } from '../src/types';

const PORT = 8799;
const BASE_URL = `http://127.0.0.1:${PORT}/api`;
const RUN_HTTP = process.env.RUN_PLAY_CONTRACT === '1';

let server: ChildProcess | null = null;

async function waitForServer(timeoutMs = 20_000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`${BASE_URL}/play/seeks`, { headers: { 'X-Play-Guest-Id': 'guest-warmup1' } });
      if (res.ok) return;
    } catch {
      /* server not up yet */
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error('runtime_adapter did not become ready in time');
}

/**
 * A minimal HTTP play client that pins a stable guest identity across
 * requests (the browser's real HttpScidbApiClient doesn't yet manage the
 * X-Play-Guest-Id header itself — server-issued cookies/headers are a
 * later-phase concern — so the test plays the role of "the browser" by
 * resending the id the server first issued).
 */
class GuestPinnedHttpClient {
  private client: HttpScidbApiClient;
  guestId: string | null = null;

  constructor(baseUrl: string, seedGuestId?: string) {
    this.guestId = seedGuestId ?? null;
    this.client = new HttpScidbApiClient(baseUrl);
    const realFetch = globalThis.fetch;
    // Wrap fetch just for this client's requests: attach the pinned guest id
    // and capture any id the server assigns/echoes back. The arrow function
    // lexically captures `this` (the instance), so no `self` alias is needed.
    (this.client as unknown as { _fetch?: typeof fetch })._fetch = undefined;
    globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input.toString();
      if (!url.startsWith(baseUrl)) return realFetch(input, init);
      const headers = new Headers(init?.headers);
      if (this.guestId) headers.set('X-Play-Guest-Id', this.guestId);
      return realFetch(input, { ...init, headers }).then((res) => {
        const issued = res.headers.get('x-play-guest-id');
        if (issued) this.guestId = issued;
        return res;
      });
    }) as typeof fetch;
    this.restoreFetch = () => { globalThis.fetch = realFetch; };
  }

  restoreFetch: () => void;
  get api(): HttpScidbApiClient {
    return this.client;
  }
}

describe('play contract parity (mock vs HTTP)', () => {
  beforeAll(async () => {
    if (!RUN_HTTP) return;
    server = spawn(
      'python3',
      ['-m', 'uvicorn', 'runtime_adapter:app', '--host', '127.0.0.1', '--port', String(PORT)],
      {
        cwd: process.cwd(),
        env: { ...process.env, SCIDB_ALLOW_INSECURE_DEV_AUTH: '1' },
        stdio: 'ignore',
      },
    );
    await waitForServer();
  }, 30_000);

  afterAll(() => {
    server?.kill();
  });

  const httpIt = RUN_HTTP ? it : it.skip;

  it('mock: create seek → accept → move → resign, and rating shape', async () => {
    const owner = new MockScidbApiClient();
    mockPlay.__setMe({ id: 'guest-mockowner', name: 'Guest-OWNR', rating: 1500 } as PlayUser);

    const seek = await owner.createSeek({
      timeControl: { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2 },
      variant: 'standard',
      rated: false,
      color: 'w',
      ratingRange: null,
    });
    expect(seek.id).toMatch(/^seek-/);
    expect(seek.owner.id).toBe('guest-mockowner');

    // Switch identity to simulate a second player accepting.
    mockPlay.__setMe({ id: 'guest-mockjoiner', name: 'Guest-JOIN', rating: 1500 } as PlayUser);
    const opponent = new MockScidbApiClient();
    const openSeeks = await opponent.listSeeks();
    expect(openSeeks.some((s) => s.id === seek.id)).toBe(true);

    const match = await opponent.acceptSeek(seek.id);
    expect(match.id).toMatch(/^match-/);
    expect(match.status).toBe('playing');
    expect(match.white.id).toBe('guest-mockowner');
    expect(match.black.id).toBe('guest-mockjoiner');
    expect(match.clocks.whiteMs).toBe(180_000);

    // Owner (white) submits the opening move.
    mockPlay.__setMe({ id: 'guest-mockowner', name: 'Guest-OWNR', rating: 1500 } as PlayUser);
    const { move, result } = await owner.submitMove(match.id, 'e2e4');
    expect(move.san).toBe('e4');
    expect(result).toBeNull();

    // Joiner resigns.
    mockPlay.__setMe({ id: 'guest-mockjoiner', name: 'Guest-JOIN', rating: 1500 } as PlayUser);
    const resignResult = await opponent.resignMatch(match.id);
    expect(resignResult.kind).toBe('resign');
    expect(resignResult.winner).toBe('w');

    const rating = await owner.getMyRating();
    expect(Array.isArray(rating)).toBe(true);
    expect(rating[0]).toMatchObject({ variant: 'standard', rating: expect.any(Number), rd: expect.any(Number) });

    mockPlay.reset();
  });

  httpIt('http: create seek → accept → move → resign, and rating shape (same scenario, live server)', async () => {
    const owner = new GuestPinnedHttpClient(BASE_URL, 'guest-httpowner');
    const seek = await owner.api.createSeek({
      timeControl: { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2 },
      variant: 'standard',
      rated: false,
      color: 'w',
      ratingRange: null,
    });
    owner.restoreFetch();
    expect(seek.id).toMatch(/^seek-/);
    expect(seek.owner.id).toBe('guest-httpowner');

    const opponent = new GuestPinnedHttpClient(BASE_URL, 'guest-httpjoiner');
    const openSeeks = await opponent.api.listSeeks();
    expect(openSeeks.some((s) => s.id === seek.id)).toBe(true);

    const match = await opponent.api.acceptSeek(seek.id);
    opponent.restoreFetch();
    expect(match.id).toMatch(/^match-/);
    expect(match.status).toBe('playing');
    expect(match.white.id).toBe('guest-httpowner');
    expect(match.black.id).toBe('guest-httpjoiner');
    expect(match.clocks.whiteMs).toBe(180_000);

    const ownerAgain = new GuestPinnedHttpClient(BASE_URL, 'guest-httpowner');
    const { move, result } = await ownerAgain.api.submitMove(match.id, 'e2e4');
    ownerAgain.restoreFetch();
    expect(move.san).toBe('e4');
    expect(result).toBeNull();

    const opponentAgain = new GuestPinnedHttpClient(BASE_URL, 'guest-httpjoiner');
    const resignResult = await opponentAgain.api.resignMatch(match.id);
    opponentAgain.restoreFetch();
    expect(resignResult.kind).toBe('resign');
    expect(resignResult.winner).toBe('w');

    const ratingClient = new GuestPinnedHttpClient(BASE_URL, 'guest-httpowner');
    const rating = await ratingClient.api.getMyRating();
    ratingClient.restoreFetch();
    expect(Array.isArray(rating)).toBe(true);
    expect(rating[0]).toMatchObject({ variant: 'standard', rating: expect.any(Number), rd: expect.any(Number) });
  });

  it('mock rejects accepting your own seek', async () => {
    mockPlay.__setMe({ id: 'guest-mocksolo', name: 'Guest-SOLO', rating: 1500 } as PlayUser);
    const mockClient = new MockScidbApiClient();
    const mockSeek = await mockClient.createSeek({
      timeControl: { kind: 'bullet', baseSeconds: 60, incrementSeconds: 0 },
      variant: 'standard',
      rated: false,
      color: 'random',
      ratingRange: null,
    });
    await expect(mockClient.acceptSeek(mockSeek.id)).rejects.toThrow();
    mockPlay.reset();
  });

  httpIt('http rejects accepting your own seek (same failure shape as mock)', async () => {
    const httpClient = new GuestPinnedHttpClient(BASE_URL, 'guest-httpsolo');
    const httpSeek = await httpClient.api.createSeek({
      timeControl: { kind: 'bullet', baseSeconds: 60, incrementSeconds: 0 },
      variant: 'standard',
      rated: false,
      color: 'random',
      ratingRange: null,
    });
    await expect(httpClient.api.acceptSeek(httpSeek.id)).rejects.toThrow();
    httpClient.restoreFetch();
  });
});
