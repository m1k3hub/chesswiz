import { describe, it, expect } from 'vitest';
import { MockScidbApiClient } from './client';
import type { SearchPayload } from '@/types';

describe('MockScidbApiClient', () => {
  const client = new MockScidbApiClient();

  it('lists built-in databases', async () => {
    const databases = await client.listDatabases();
    expect(databases).toHaveLength(2);
    expect(databases[0].id).toBe('masters');
  });

  it('returns mock games', async () => {
    const games = await client.listGames();
    expect(games.length).toBeGreaterThan(0);
    expect(games[0]).toHaveProperty('white');
  });

  it('filters games by advanced query', async () => {
    const payload: SearchPayload = {
      type: 'advanced',
      query: { white: 'carlsen' },
    };
    const result = await client.search(payload);
    expect(result.status).toBe('complete');

    const full = await client.getSearchResults(result.jobId);
    const game = full.games?.[0];
    expect(game).toBeDefined();
    expect(game!.white).toContain('Carlsen');
  });

  it('returns an opening tree', async () => {
    const tree = await client.getOpeningTree({ moves: [] });
    expect(tree.length).toBeGreaterThan(0);
    expect(tree[0]).toHaveProperty('san');
    expect(tree[0]).toHaveProperty('games');
  });

  it('starts and polls a mock analysis', async () => {
    const { jobId } = await client.startAnalysis({ fen: 'start', multiPv: 3 });
    const job = await client.getAnalysis(jobId);
    expect(job.status).toBe('running');
    expect(job.lines.length).toBe(3);
  });
});
