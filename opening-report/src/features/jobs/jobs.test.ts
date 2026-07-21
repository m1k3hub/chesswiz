import { describe, it, expect } from 'vitest';
import { MockScidbApiClient } from '@/api/client';
import type { ImportPayload, ExportPayload } from '@/types';

describe('MockScidbApiClient job lifecycle', () => {
  const client = new MockScidbApiClient();

  it('creates an import job with running status', async () => {
    const payload: ImportPayload = {
      databaseId: 'masters',
      format: 'PGN',
      filename: 'test-games.pgn',
    };
    const job = await client.importDatabase(payload);
    expect(job.type).toBe('import');
    expect(job.status).toBe('running');
    expect(job.progress).toBe(0);
    expect(job.total).toBe(100);
    expect(job.message).toContain('test-games.pgn');
  });

  it('creates an export job with running status', async () => {
    const payload: ExportPayload = {
      databaseId: 'masters',
      format: 'PGN',
    };
    const job = await client.exportDatabase(payload);
    expect(job.type).toBe('export');
    expect(job.status).toBe('running');
    expect(job.progress).toBe(0);
    expect(job.total).toBe(100);
  });

  it('advances import job progress on getJob polls', async () => {
    const payload: ImportPayload = {
      databaseId: 'masters',
      format: 'SI3',
      filename: 'database.si3',
    };
    const created = await client.importDatabase(payload);
    const jobId = created.jobId;

    // First poll advances progress by 20
    const poll1 = await client.getJob(jobId);
    expect(poll1.status).toBe('running');
    expect(poll1.progress).toBe(20);

    // Second poll advances to 40
    const poll2 = await client.getJob(jobId);
    expect(poll2.progress).toBe(40);

    // Third poll to 60
    const poll3 = await client.getJob(jobId);
    expect(poll3.progress).toBe(60);

    // Fourth poll to 80
    const poll4 = await client.getJob(jobId);
    expect(poll4.progress).toBe(80);

    // Fifth poll completes
    const poll5 = await client.getJob(jobId);
    expect(poll5.status).toBe('complete');
    expect(poll5.progress).toBe(100);
    expect(poll5.finishedAt).toBeDefined();
    expect(poll5.message).toContain('Import complete');
  });

  it('cancels a running job', async () => {
    const payload: ImportPayload = {
      databaseId: 'repertoire',
      format: 'PGN',
      filename: 'games.pgn',
    };
    const created = await client.importDatabase(payload);
    const jobId = created.jobId;

    // Advance once to 20
    const poll1 = await client.getJob(jobId);
    expect(poll1.progress).toBe(20);
    expect(poll1.status).toBe('running');

    // Cancel
    const cancelled = await client.cancelJob(jobId);
    expect(cancelled.status).toBe('cancelled');
    expect(cancelled.message).toContain('cancelled');
    expect(cancelled.finishedAt).toBeDefined();

    // Further polls should not advance (status is no longer 'running')
    const afterCancel = await client.getJob(jobId);
    expect(afterCancel.status).toBe('cancelled');
    expect(afterCancel.progress).toBe(20);
  });

  it('deletes a job', async () => {
    const payload: ExportPayload = {
      databaseId: 'masters',
      format: 'CBH',
    };
    const created = await client.exportDatabase(payload);
    const jobId = created.jobId;

    await client.deleteJob(jobId);

    const afterDelete = await client.getJob(jobId);
    expect(afterDelete.status).toBe('error');
    expect(afterDelete.message).toContain('Unknown job');
  });

  it('returns error for unknown job', async () => {
    const job = await client.getJob('nonexistent-job');
    expect(job.status).toBe('error');
    expect(job.message).toContain('Unknown job');
  });

  it('returns error when cancelling unknown job', async () => {
    const job = await client.cancelJob('nonexistent-job');
    expect(job.status).toBe('error');
  });

  it('export job message contains game count', async () => {
    const payload: ExportPayload = {
      databaseId: 'masters',
      format: 'PGN',
      gameIds: ['g-001', 'g-002', 'g-003'],
    };
    const job = await client.exportDatabase(payload);
    expect(job.message).toContain('3');
  });
});