import { describe, it, expect, beforeEach } from 'vitest';
import { MockScidbApiClient } from '@/api/client';
import type { CrosstableQuery } from '@/types';

describe('Crosstable mock API', () => {
  let client: MockScidbApiClient;

  beforeEach(() => {
    client = new MockScidbApiClient();
  });

  it('returns a crosstable with players', async () => {
    const result = await client.queryCrosstable({});
    expect(result.players.length).toBeGreaterThan(0);
    expect(result.totalRounds).toBeGreaterThan(0);
  });

  it('returns players with required fields', async () => {
    const result = await client.queryCrosstable({});
    const player = result.players[0];
    expect(player).toHaveProperty('player');
    expect(player).toHaveProperty('rank');
    expect(player).toHaveProperty('points');
    expect(player).toHaveProperty('wins');
    expect(player).toHaveProperty('draws');
    expect(player).toHaveProperty('losses');
    expect(player).toHaveProperty('sonnebornBerger');
    expect(player).toHaveProperty('games');
  });

  it('filters by player name', async () => {
    const query: CrosstableQuery = {
      players: ['Carlsen, Magnus', 'Caruana, Fabiano'],
    };
    const result = await client.queryCrosstable(query);
    expect(result.players.length).toBe(2);
    expect(result.players.some((p) => p.player === 'Carlsen, Magnus')).toBe(true);
    expect(result.players.some((p) => p.player === 'Caruana, Fabiano')).toBe(true);
  });

  it('returns empty players when filter matches none', async () => {
    const query: CrosstableQuery = {
      players: ['Nonexistent Player'],
    };
    const result = await client.queryCrosstable(query);
    expect(result.players.length).toBe(0);
  });

  it('overrides event and site in result', async () => {
    const query: CrosstableQuery = {
      event: 'Custom Event',
      site: 'Custom Site',
    };
    const result = await client.queryCrosstable(query);
    expect(result.event).toBe('Custom Event');
    expect(result.site).toBe('Custom Site');
  });

  it('players are sorted by rank by default', async () => {
    const result = await client.queryCrosstable({});
    for (let i = 1; i < result.players.length; i++) {
      expect(result.players[i].rank).toBeGreaterThan(result.players[i - 1].rank);
    }
  });
});