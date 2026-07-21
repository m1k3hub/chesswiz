import { describe, it, expect, beforeEach } from 'vitest';
import { MockScidbApiClient } from '@/api/client';
import type { MaintenanceJobRequest } from '@/types';

describe('Maintenance mock API', () => {
  let client: MockScidbApiClient;

  beforeEach(() => {
    client = new MockScidbApiClient();
  });

  it('starts a duplicate-detection job', async () => {
    const payload: MaintenanceJobRequest = {
      databaseId: 'masters',
      operation: 'duplicate-detection',
    };
    const job = await client.startMaintenance(payload);
    expect(job.jobId).toMatch(/^mock-maintenance-/);
    expect(job.type).toBe('maintenance');
    expect(job.status).toBe('running');
    expect(job.progress).toBe(0);
    expect(job.total).toBe(100);
  });

  it('returns a duplicate-detection report', async () => {
    const payload: MaintenanceJobRequest = {
      databaseId: 'masters',
      operation: 'duplicate-detection',
    };
    const job = await client.startMaintenance(payload);
    const report = await client.getMaintenanceReport(job.jobId);
    expect(report.jobId).toBe(job.jobId);
    expect(report.operation).toBe('duplicate-detection');
    expect(report.duplicates).toBeDefined();
    expect(report.duplicates!.length).toBeGreaterThan(0);
    expect(report.duplicates![0]).toHaveProperty('gameId');
    expect(report.duplicates![0]).toHaveProperty('duplicates');
    expect(report.duplicates![0]).toHaveProperty('white');
    expect(report.duplicates![0]).toHaveProperty('black');
  });

  it('returns an eco-stats report', async () => {
    const payload: MaintenanceJobRequest = {
      databaseId: 'masters',
      operation: 'eco-stats',
    };
    const job = await client.startMaintenance(payload);
    const report = await client.getMaintenanceReport(job.jobId);
    expect(report.operation).toBe('eco-stats');
    expect(report.ecoStats).toBeDefined();
    expect(report.ecoStats!.length).toBeGreaterThan(0);
    const row = report.ecoStats![0];
    expect(row).toHaveProperty('eco');
    expect(row).toHaveProperty('name');
    expect(row).toHaveProperty('games');
    expect(row).toHaveProperty('whiteScore');
    expect(row).toHaveProperty('drawRate');
  });

  it('returns a compaction report', async () => {
    const payload: MaintenanceJobRequest = {
      databaseId: 'repertoire',
      operation: 'compaction',
    };
    const job = await client.startMaintenance(payload);
    const report = await client.getMaintenanceReport(job.jobId);
    expect(report.operation).toBe('compaction');
    expect(report.compaction).toBeDefined();
    expect(report.compaction!.bytesBefore).toBeGreaterThan(0);
    expect(report.compaction!.bytesAfter).toBeGreaterThan(0);
    expect(report.compaction!.bytesAfter).toBeLessThan(report.compaction!.bytesBefore);
    expect(report.compaction!.savedPercent).toBeGreaterThan(0);
  });

  it('returns a strip-variants report', async () => {
    const payload: MaintenanceJobRequest = {
      databaseId: 'masters',
      operation: 'strip-variants',
    };
    const job = await client.startMaintenance(payload);
    const report = await client.getMaintenanceReport(job.jobId);
    expect(report.operation).toBe('strip-variants');
    expect(report.strip).toBeDefined();
    expect(report.strip!.strippedVariations).toBeGreaterThan(0);
    expect(report.strip!.strippedComments).toBeGreaterThan(0);
    expect(report.strip!.strippedNags).toBeGreaterThan(0);
  });

  it('throws for unknown maintenance job', async () => {
    await expect(client.getMaintenanceReport('nonexistent')).rejects.toThrow();
  });

  it('maintenance job appears in getJob', async () => {
    const payload: MaintenanceJobRequest = {
      databaseId: 'masters',
      operation: 'eco-stats',
    };
    const job = await client.startMaintenance(payload);
    const polled = await client.getJob(job.jobId);
    expect(polled.jobId).toBe(job.jobId);
    expect(polled.type).toBe('maintenance');
  });
});