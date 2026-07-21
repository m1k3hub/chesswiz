import { useEffect, useState, useCallback, useRef } from 'react';
import { createApiClient } from '@/api/client';
import { useWorkspaceStore } from '@/state/workspace';
import type {
  Database,
  MaintenanceOperation,
  MaintenanceReport,
  JobProgress,
} from '@/types';

const api = createApiClient();

const OPERATIONS: { id: MaintenanceOperation; label: string; icon: string; description: string }[] = [
  { id: 'duplicate-detection', label: 'Duplicate Detection', icon: '⧉', description: 'Find and group duplicate games in the database.' },
  { id: 'eco-stats', label: 'ECO Statistics', icon: '▣', description: 'Compute game counts and scores per ECO opening code.' },
  { id: 'compaction', label: 'Compaction', icon: '⬇', description: 'Compact the database file to reclaim unused space.' },
  { id: 'strip-variants', label: 'Strip Variations', icon: '✂', description: 'Remove variations, comments, and NAGs from all games.' },
];

const STATUS_BADGE: Record<string, string> = {
  pending: 'badge-gray',
  running: 'badge-blue',
  complete: 'badge-green',
  error: 'badge-red',
  cancelled: 'badge-red',
  stopped: 'badge-gray',
};

/**
 * MaintenanceCenter — modal for running database maintenance operations.
 *
 * Listens for `scidb:open-maintenance` custom events. Lets the user choose
 * an operation and target database, run the job, poll progress, and display
 * the resulting report (duplicates, ECO stats, compaction savings, or strip
 * counts).
 */
export default function MaintenanceCenter() {
  const [isOpen, setIsOpen] = useState(false);
  const [databases, setDatabases] = useState<Database[]>([]);
  const [operation, setOperation] = useState<MaintenanceOperation>('duplicate-detection');
  const [databaseId, setDatabaseId] = useState('');
  const [job, setJob] = useState<JobProgress | null>(null);
  const [report, setReport] = useState<MaintenanceReport | null>(null);
  const [isRunning, setIsRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const pollTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const activeDatabaseId = useWorkspaceStore((s) => s.activeDatabaseId);
  const toast = window.ScidbWorkspace?.toast || console.log;

  useEffect(() => {
    const handleOpen = () => {
      setIsOpen(true);
      setJob(null);
      setReport(null);
      setError(null);
      setDatabaseId(activeDatabaseId);
    };
    window.addEventListener('scidb:open-maintenance', handleOpen);
    return () => window.removeEventListener('scidb:open-maintenance', handleOpen);
  }, [activeDatabaseId]);

  useEffect(() => {
    if (isOpen) {
      api.listDatabases().then(setDatabases).catch(() => setDatabases([]));
    }
  }, [isOpen]);

  const clearPolling = useCallback(() => {
    if (pollTimer.current) {
      clearInterval(pollTimer.current);
      pollTimer.current = null;
    }
  }, []);

  useEffect(() => () => clearPolling(), [clearPolling]);

  const pollJob = useCallback(async (jobId: string) => {
    try {
      const updated = await api.getJob(jobId);
      setJob(updated);
      if (updated.status === 'complete') {
        clearPolling();
        setIsRunning(false);
        try {
          const rpt = await api.getMaintenanceReport(jobId);
          setReport(rpt);
          toast(`Maintenance complete: ${rpt.message || 'done'}`, 'success');
        } catch (e) {
          setError(`Failed to fetch report: ${e instanceof Error ? e.message : String(e)}`);
        }
      } else if (updated.status === 'error' || updated.status === 'cancelled') {
        clearPolling();
        setIsRunning(false);
        setError(updated.message || `Job ${updated.status}`);
      }
    } catch (e) {
      console.warn('Maintenance poll failed', e);
    }
  }, [clearPolling, toast]);

  const runOperation = useCallback(async () => {
    if (!databaseId) {
      setError('Please select a target database.');
      return;
    }
    setIsRunning(true);
    setError(null);
    setJob(null);
    setReport(null);
    try {
      const response = await api.startMaintenance({ databaseId, operation });
      setJob(response);
      clearPolling();
      pollTimer.current = setInterval(() => pollJob(response.jobId), 600);
    } catch (e) {
      setError(`Failed to start: ${e instanceof Error ? e.message : String(e)}`);
      setIsRunning(false);
    }
  }, [databaseId, operation, clearPolling, pollJob]);

  const cancelJob = useCallback(async () => {
    if (!job) return;
    clearPolling();
    try {
      await api.cancelJob(job.jobId);
      setIsRunning(false);
      setJob((prev) => prev ? { ...prev, status: 'cancelled' } : null);
      toast('Maintenance job cancelled', 'accent');
    } catch (e) {
      setError(`Cancel failed: ${e instanceof Error ? e.message : String(e)}`);
    }
  }, [job, clearPolling, toast]);

  if (!isOpen) return null;

  const selectedOp = OPERATIONS.find((op) => op.id === operation);

  return (
    <div id="maintenance-modal" className="modal" style={{ display: 'flex' }} onClick={(e) => {
      if (e.target === e.currentTarget) setIsOpen(false);
    }}>
      <div className="modal-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">DATABASE MAINTENANCE</span>
            <h3>Maintenance center</h3>
          </div>
          <button className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>

        <div className="modal-body">
          {/* Operation selection */}
          <div className="search-form-grid" style={{ marginBottom: 16 }}>
            <div className="control-group full-width">
              <label>Operation</label>
              <select value={operation} onChange={(e) => setOperation(e.target.value as MaintenanceOperation)} disabled={isRunning}>
                {OPERATIONS.map((op) => (
                  <option key={op.id} value={op.id}>{op.icon} {op.label}</option>
                ))}
              </select>
            </div>
            <div className="control-group full-width">
              <label>Target database</label>
              <select value={databaseId} onChange={(e) => setDatabaseId(e.target.value)} disabled={isRunning}>
                {databases.map((db) => (
                  <option key={db.id} value={db.id}>{db.name} ({db.format})</option>
                ))}
              </select>
            </div>
          </div>

          {selectedOp && (
            <p style={{ marginBottom: 14, fontSize: 13, color: 'var(--text-dim)' }}>
              {selectedOp.description}
            </p>
          )}

          {/* Actions */}
          <div className="search-actions">
            <span className="search-status">
              {job ? `${job.status} — ${job.progress}/${job.total}` : 'Ready'}
            </span>
            <div className="search-actions-right">
              {isRunning ? (
                <button className="ghost-btn" onClick={cancelJob}>Cancel</button>
              ) : (
                <button className="primary-btn" onClick={runOperation}>Run operation</button>
              )}
            </div>
          </div>

          {/* Progress bar */}
          {job && (
            <div style={{ marginTop: 12 }}>
              <div className="win-bar" style={{ height: 8 }}>
                <div className="w-white" style={{ width: `${job.total > 0 ? (job.progress / job.total) * 100 : 0}%` }} />
              </div>
              <span className={`badge ${STATUS_BADGE[job.status] || 'badge-gray'}`} style={{ marginTop: 6, display: 'inline-block' }}>
                {job.status}
              </span>
            </div>
          )}

          {/* Error */}
          {error && (
            <p style={{ color: 'var(--accent-red)', fontSize: 14, marginTop: 12 }}>{error}</p>
          )}

          {/* Report output */}
          {report && (
            <div style={{ marginTop: 16 }}>
              <div className="report-section-header">
                <span className="section-icon">📋</span>
                <h3>Report — {OPERATIONS.find((op) => op.id === report.operation)?.label}</h3>
              </div>
              <div className="report-section-body">
                {report.message && (
                  <p style={{ marginBottom: 12, fontSize: 14 }}>{report.message}</p>
                )}

                {/* Duplicate groups */}
                {report.duplicates && report.duplicates.length > 0 && (
                  <table className="stats-table">
                    <thead>
                      <tr>
                        <th>Game</th>
                        <th>White</th>
                        <th>Black</th>
                        <th>Date</th>
                        <th>Duplicates</th>
                      </tr>
                    </thead>
                    <tbody>
                      {report.duplicates.map((dg) => (
                        <tr key={dg.gameId}>
                          <td><strong>{dg.gameId}</strong></td>
                          <td>{dg.white}</td>
                          <td>{dg.black}</td>
                          <td>{dg.date}</td>
                          <td>{dg.duplicates.join(', ')}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}

                {/* ECO stats */}
                {report.ecoStats && report.ecoStats.length > 0 && (
                  <table className="stats-table">
                    <thead>
                      <tr>
                        <th>ECO</th>
                        <th>Name</th>
                        <th className="number">Games</th>
                        <th className="number">White Score</th>
                        <th className="number">Draw Rate</th>
                      </tr>
                    </thead>
                    <tbody>
                      {report.ecoStats.map((row) => (
                        <tr key={row.eco}>
                          <td><strong>{row.eco}</strong></td>
                          <td>{row.name}</td>
                          <td className="number">{row.games.toLocaleString()}</td>
                          <td className="number">{row.whiteScore}%</td>
                          <td className="number">{row.drawRate}%</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}

                {/* Compaction result */}
                {report.compaction && (
                  <div className="insight-grid" style={{ gridTemplateColumns: 'repeat(2, 1fr)' }}>
                    <div>
                      <span className="metric-label">BEFORE</span>
                      <strong>{(report.compaction.bytesBefore / 1_000_000).toFixed(1)} MB</strong>
                    </div>
                    <div>
                      <span className="metric-label">AFTER</span>
                      <strong>{(report.compaction.bytesAfter / 1_000_000).toFixed(1)} MB</strong>
                    </div>
                    <div>
                      <span className="metric-label">SAVED</span>
                      <strong>{(report.compaction.savedBytes / 1_000_000).toFixed(1)} MB</strong>
                    </div>
                    <div>
                      <span className="metric-label">PERCENT</span>
                      <strong>{report.compaction.savedPercent}%</strong>
                    </div>
                  </div>
                )}

                {/* Strip result */}
                {report.strip && (
                  <div className="insight-grid" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
                    <div>
                      <span className="metric-label">VARIATIONS</span>
                      <strong>{report.strip.strippedVariations}</strong>
                    </div>
                    <div>
                      <span className="metric-label">COMMENTS</span>
                      <strong>{report.strip.strippedComments}</strong>
                    </div>
                    <div>
                      <span className="metric-label">NAGS</span>
                      <strong>{report.strip.strippedNags}</strong>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}