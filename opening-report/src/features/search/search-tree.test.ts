import { describe, it, expect } from 'vitest';
import { MockScidbApiClient } from '@/api/client';
import type { SearchPayload, OpeningTreeRequest } from '@/types';

describe('Search & tree hardening (milestone 3)', () => {
  const client = new MockScidbApiClient();

  // ── Paginated game listing ──────────────────────

  it('returns paginated games with correct metadata', async () => {
    const page1 = await client.listGamesPaginated({
      databaseId: 'masters',
      page: 1,
      limit: 2,
    });
    expect(page1.games).toHaveLength(2);
    expect(page1.page).toBe(1);
    expect(page1.limit).toBe(2);
    expect(page1.total).toBe(4);
    expect(page1.totalPages).toBe(2);
  });

  it('returns second page correctly', async () => {
    const page2 = await client.listGamesPaginated({
      databaseId: 'masters',
      page: 2,
      limit: 2,
    });
    expect(page2.games).toHaveLength(2);
    expect(page2.page).toBe(2);
    expect(page2.totalPages).toBe(2);
  });

  it('returns empty page beyond total', async () => {
    const page3 = await client.listGamesPaginated({
      databaseId: 'masters',
      page: 3,
      limit: 2,
    });
    expect(page3.games).toHaveLength(0);
    expect(page3.totalPages).toBe(2);
  });

  it('supports text query filtering', async () => {
    const result = await client.listGamesPaginated({
      databaseId: 'masters',
      query: 'carlsen',
      page: 1,
      limit: 10,
    });
    expect(result.games).toHaveLength(1);
    expect(result.games[0].white).toMatch(/Carlsen/);
  });

  it('supports sorting by white ascending', async () => {
    const result = await client.listGamesPaginated({
      databaseId: 'masters',
      sort: 'white',
      order: 'asc',
      page: 1,
      limit: 10,
    });
    expect(result.games.length).toBeGreaterThan(1);
    expect(result.games[0].white <= result.games[1].white).toBe(true);
  });

  it('supports sorting by date descending', async () => {
    const result = await client.listGamesPaginated({
      databaseId: 'masters',
      sort: 'date',
      order: 'desc',
      page: 1,
      limit: 10,
    });
    expect(result.games.length).toBeGreaterThan(1);
    expect(result.games[0].date >= result.games[1].date).toBe(true);
  });

  it('defaults to page 1 and limit 20', async () => {
    const result = await client.listGamesPaginated({ databaseId: 'masters' });
    expect(result.page).toBe(1);
    expect(result.limit).toBe(20);
    expect(result.total).toBe(4);
    expect(result.totalPages).toBe(1);
  });

  // ── Search cancellation ──────────────────────

  it('cancels a search job and sets status to cancelled', async () => {
    const payload: SearchPayload = {
      type: 'advanced',
      query: { white: 'carlsen' },
    };
    const result = await client.search(payload);
    expect(result.status).toBe('complete');

    await client.cancelSearch(result.jobId);
    const after = await client.getSearchResults(result.jobId);
    expect(after.status).toBe('cancelled');
    expect(after.games).toEqual([]);
  });

  it('cancelSearch on unknown job does not throw', async () => {
    await expect(client.cancelSearch('nonexistent')).resolves.toBeUndefined();
  });

  // ── Opening tree shape ──────────────────────

  it('returns opening tree with correct move shape', async () => {
    const request: OpeningTreeRequest = {
      moves: [{ uci: 'e2e4', san: 'e4' }],
      fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
      source: 'masters',
    };
    const tree = await client.getOpeningTree(request);
    expect(tree.length).toBeGreaterThan(0);
    const move = tree[0];
    expect(move).toHaveProperty('san');
    expect(move).toHaveProperty('uci');
    expect(move).toHaveProperty('games');
    expect(move).toHaveProperty('score');
    expect(move).toHaveProperty('white');
    expect(move).toHaveProperty('draw');
    expect(move).toHaveProperty('black');
    expect(move).toHaveProperty('eco');
    expect(typeof move.games).toBe('number');
    expect(typeof move.score).toBe('number');
  });

  it('opening tree W/D/L values are non-negative', async () => {
    const tree = await client.getOpeningTree({ moves: [] });
    for (const move of tree) {
      expect(move.white).toBeGreaterThanOrEqual(0);
      expect(move.draw).toBeGreaterThanOrEqual(0);
      expect(move.black).toBeGreaterThanOrEqual(0);
    }
  });

  // ── Index browser / ECO ──────────────────────

  it('returns player namebase entries', async () => {
    const players = await client.getIndexes('players');
    expect(players.length).toBeGreaterThan(0);
    const first = players[0] as { id: string; name: string; games: number };
    expect(first).toHaveProperty('id');
    expect(first).toHaveProperty('name');
    expect(first).toHaveProperty('games');
  });

  it('returns ECO entries', async () => {
    const eco = await client.getIndexes('eco');
    expect(eco.length).toBeGreaterThan(0);
    const first = eco[0] as { code: string; name: string; games: number };
    expect(first).toHaveProperty('code');
    expect(first).toHaveProperty('name');
  });

  it('getEcoTable returns same data as getIndexes eco', async () => {
    const viaIndexes = await client.getIndexes('eco');
    const viaEco = await client.getEcoTable();
    expect(viaIndexes.length).toBe(viaEco.length);
  });
});