import { describe, it, expect } from 'vitest';
import { MockScidbApiClient } from '@/api/client';
import type { OpeningPrepRequest } from '@/types';

describe('MockScidbApiClient repertoire & opening prep', () => {
  const client = new MockScidbApiClient();

  it('lists repertoires with moves', async () => {
    const reps = await client.listRepertoires();
    expect(reps.length).toBeGreaterThanOrEqual(2);
    expect(reps[0]).toHaveProperty('name');
    expect(reps[0]).toHaveProperty('side');
    expect(reps[0]).toHaveProperty('moves');
    expect(reps[0].moves.length).toBeGreaterThan(0);
  });

  it('returns repertoire with ECO code and side', async () => {
    const reps = await client.listRepertoires();
    const italian = reps.find((r) => r.id === 'rep-w-italian');
    expect(italian).toBeDefined();
    expect(italian!.side).toBe('white');
    expect(italian!.eco).toBe('C50');
    expect(italian!.moves[0].san).toBe('e4');
  });

  it('generates opening prep report for a repertoire', async () => {
    const payload: OpeningPrepRequest = { repertoireId: 'rep-w-italian' };
    const report = await client.createOpeningPrepReport(payload);
    expect(report.status).toBe('complete');
    expect(report.type).toBe('opening');
    expect(report.subject).toContain('Italian');
    expect(report.lines.length).toBeGreaterThan(0);
    expect(report.lines[0]).toHaveProperty('san');
    expect(report.lines[0]).toHaveProperty('games');
    expect(report.lines[0]).toHaveProperty('performance');
    expect(report.summary).toContain('Italian');
  });

  it('generates opening prep report for Sicilian repertoire', async () => {
    const payload: OpeningPrepRequest = { repertoireId: 'rep-b-sicilian' };
    const report = await client.createOpeningPrepReport(payload);
    expect(report.subject).toContain('Sicilian');
    expect(report.lines[0].san).toBe('e4');
  });

  it('throws for unknown repertoire', async () => {
    const payload: OpeningPrepRequest = { repertoireId: 'nonexistent' };
    await expect(client.createOpeningPrepReport(payload)).rejects.toThrow('Repertoire not found');
  });

  it('report lines have valid performance labels', async () => {
    const payload: OpeningPrepRequest = { repertoireId: 'rep-w-italian' };
    const report = await client.createOpeningPrepReport(payload);
    const validLabels = ['good', 'solid', 'risky', 'rare', 'neutral'];
    for (const line of report.lines) {
      expect(validLabels).toContain(line.performance);
    }
  });
});