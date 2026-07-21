import { describe, it, expect } from 'vitest';
import { MockScidbApiClient } from '@/api/client';
import type { PlayerPrepRequest } from '@/types';

describe('MockScidbApiClient player center & opponent prep', () => {
  const client = new MockScidbApiClient();

  it('lists players without query', async () => {
    const players = await client.listPlayers();
    expect(players.length).toBeGreaterThanOrEqual(4);
    expect(players[0]).toHaveProperty('name');
    expect(players[0]).toHaveProperty('elo');
    expect(players[0]).toHaveProperty('games');
  });

  it('filters players by name query', async () => {
    const players = await client.listPlayers('carlsen');
    expect(players.length).toBe(1);
    expect(players[0].name).toMatch(/Carlsen/);
  });

  it('filters players case-insensitively', async () => {
    const players = await client.listPlayers('ANAND');
    expect(players.length).toBe(1);
    expect(players[0].name).toMatch(/Anand/);
  });

  it('returns empty array for non-matching query', async () => {
    const players = await client.listPlayers('nonexistent');
    expect(players).toHaveLength(0);
  });

  it('returns a detailed player card', async () => {
    const card = await client.getPlayerCard('p-carlsen');
    expect(card.id).toBe('p-carlsen');
    expect(card.name).toMatch(/Carlsen/);
    expect(card.peakElo).toBeGreaterThan(card.elo);
    expect(card.topOpenings.length).toBeGreaterThan(0);
    expect(card.topOpenings[0]).toHaveProperty('eco');
    expect(card.topOpenings[0]).toHaveProperty('score');
    expect(card.winRate + card.drawRate + card.lossRate).toBe(100);
  });

  it('throws for unknown player card', async () => {
    await expect(client.getPlayerCard('nonexistent')).rejects.toThrow('Player not found');
  });

  it('generates opponent prep report', async () => {
    const payload: PlayerPrepRequest = { playerId: 'p-carlsen' };
    const report = await client.createPlayerPrepReport(payload);
    expect(report.status).toBe('complete');
    expect(report.type).toBe('opponent');
    expect(report.subject).toMatch(/Carlsen/);
    expect(report.lines.length).toBeGreaterThan(0);
    expect(report.lines[0]).toHaveProperty('san');
    expect(report.lines[0]).toHaveProperty('games');
    expect(report.summary).toContain('Carlsen');
  });

  it('throws for unknown player prep report', async () => {
    const payload: PlayerPrepRequest = { playerId: 'nonexistent' };
    await expect(client.createPlayerPrepReport(payload)).rejects.toThrow('Player not found');
  });
});