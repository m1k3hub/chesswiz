import { useEffect, useState, useRef, useCallback } from 'react';
import { createApiClient } from '@/api/client';
import { useWorkspaceStore } from '@/state/workspace';
import type { DatabaseFormat, JobProgress } from '@/types';

const api = createApiClient();

const SUPPORTED_FORMATS: DatabaseFormat[] = ['PGN', 'SI3', 'CBH', 'CBV'];

interface ImportExportPanelProps {
  databaseId: string;
  onClose: () => void;
}

/**
 * ImportExportPanel — upload area and active job list for import/export.
 *
 * Toggled from DatabaseModal. Simulates PGN/SI3/CBH/CBV file imports and
 * exports with progress bars and cancel buttons via the typed API client.
 */
export default function ImportExportPanel({ databaseId, onClose }: ImportExportPanelProps) {
  const [jobs, setJobs] = useState<JobProgress[]>([]);
  const [selectedFormat, setSelectedFormat] = useState<DatabaseFormat>('PGN');
  const [filename, setFilename] = useState('');
  const [isDragging, setIsDragging] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const pollTimers = useRef<Map<string, ReturnType<typeof setInterval>>>(new Map());
  const toast = window.ScidbWorkspace?.toast || console.log;

  const activeDatabaseId = useWorkspaceStore((s) => s.activeDatabaseId);
  const targetDb = databaseId || activeDatabaseId;

  const stopPolling = useCallback((jobId: string) => {
    const timer = pollTimers.current.get(jobId);
    if (timer) {
      clearInterval(timer);
      pollTimers.current.delete(jobId);
    }
  }, []);

  const pollJob = useCallback((jobId: string) => {
    stopPolling(jobId);
    pollTimers.current.set(
      jobId,
      setInterval(async () => {
        try {
          const job = await api.getJob(jobId);
          setJobs((prev) => prev.map((j) => (j.jobId === jobId ? job : j)));
          if (job.status === 'complete' || job.status === 'error' || job.status === 'cancelled') {
            stopPolling(jobId);
          }
        } catch {
          stopPolling(jobId);
        }
      }, 800),
    );
  }, [stopPolling]);

  const handleImport = useCallback(async () => {
    const name = filename || `upload.${selectedFormat.toLowerCase()}`;
    try {
      const job = await api.importDatabase({
        databaseId: targetDb,
        format: selectedFormat,
        filename: name,
      });
      setJobs((prev) => [...prev, job]);
      pollJob(job.jobId);
      toast(`Import started: ${name}`, 'accent');
      setFilename('');
    } catch (err) {
      toast(`Import failed: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    }
  }, [filename, selectedFormat, targetDb, pollJob, toast]);

  const handleExport = useCallback(async () => {
    try {
      const job = await api.exportDatabase({
        databaseId: targetDb,
        format: selectedFormat,
      });
      setJobs((prev) => [...prev, job]);
      pollJob(job.jobId);
      toast(`Export started as ${selectedFormat}`, 'accent');
    } catch (err) {
      toast(`Export failed: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    }
  }, [targetDb, selectedFormat, pollJob, toast]);

  const handleCancel = useCallback(async (jobId: string) => {
    try {
      const job = await api.cancelJob(jobId);
      setJobs((prev) => prev.map((j) => (j.jobId === jobId ? job : j)));
      stopPolling(jobId);
      toast('Job cancelled', 'accent');
    } catch {
      /* noop */
    }
  }, [stopPolling, toast]);

  const handleDelete = useCallback(async (jobId: string) => {
    stopPolling(jobId);
    try {
      await api.deleteJob(jobId);
    } catch {
      /* noop */
    }
    setJobs((prev) => prev.filter((j) => j.jobId !== jobId));
  }, [stopPolling]);

  const handleFileSelect = useCallback((file: File) => {
    setFilename(file.name);
    const ext = file.name.split('.').pop()?.toUpperCase();
    if (ext && SUPPORTED_FORMATS.includes(ext as DatabaseFormat)) {
      setSelectedFormat(ext as DatabaseFormat);
    }
  }, []);

  useEffect(() => {
    const timers = pollTimers.current;
    return () => {
      timers.forEach((timer) => clearInterval(timer));
      timers.clear();
    };
  }, []);

  return (
    <div className="modal" style={{ display: 'flex' }} onClick={(e) => {
      if (e.target === e.currentTarget) onClose();
    }}>
      <div className="modal-content database-modal-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">DATABASE / IMPORT & EXPORT</span>
            <h3>Import / Export</h3>
          </div>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <div className="database-toolbar">
          <select
            value={selectedFormat}
            onChange={(e) => setSelectedFormat(e.target.value as DatabaseFormat)}
          >
            {SUPPORTED_FORMATS.map((fmt) => (
              <option key={fmt} value={fmt}>{fmt}</option>
            ))}
          </select>
        </div>

        {/* Upload area */}
        <div
          className="search-hint"
          style={{
            border: `2px dashed ${isDragging ? 'var(--accent-blue)' : 'var(--border)'}`,
            borderRadius: '8px',
            padding: '24px',
            textAlign: 'center',
            cursor: 'pointer',
            margin: '12px 0',
          }}
          onClick={() => fileInputRef.current?.click()}
          onDragOver={(e) => { e.preventDefault(); setIsDragging(true); }}
          onDragLeave={() => setIsDragging(false)}
          onDrop={(e) => {
            e.preventDefault();
            setIsDragging(false);
            const file = e.dataTransfer.files[0];
            if (file) handleFileSelect(file);
          }}
        >
          <input
            ref={fileInputRef}
            type="file"
            accept=".pgn,.si3,.cbh,.cbv"
            style={{ display: 'none' }}
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (file) handleFileSelect(file);
            }}
          />
          {filename ? `📄 ${filename}` : 'Drop a PGN/SI3/CBH/CBV file here or click to browse'}
        </div>

        <div className="search-actions">
          <div className="search-actions-right">
            <button className="ghost-btn" onClick={handleExport}>
              ⬇ Export
            </button>
            <button className="primary-btn" onClick={handleImport} disabled={!targetDb}>
              ⬆ Import
            </button>
          </div>
        </div>

        {/* Active jobs */}
        <div className="search-results-header">
          <span>Active jobs</span>
        </div>
        <div className="search-results-list">
          {jobs.length === 0 ? (
            <div className="database-empty">No active import/export jobs.</div>
          ) : (
            jobs.map((job) => (
              <div key={job.jobId} className="game-row" style={{ display: 'block', padding: '12px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                  <strong>{job.type === 'import' ? '⬆' : '⬇'} {job.message}</strong>
                  <span className={`badge ${job.status === 'complete' ? 'badge-green' : job.status === 'error' || job.status === 'cancelled' ? 'badge-red' : 'badge-blue'}`}>
                    {job.status}
                  </span>
                </div>
                <div className="win-bar" style={{ height: '8px', marginBottom: '4px' }}>
                  <div className="w-white" style={{ width: `${(job.progress / job.total) * 100}%` }}></div>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <small>{job.progress} / {job.total}</small>
                  <div>
                    {(job.status === 'running' || job.status === 'pending') && (
                      <button className="ghost-btn" style={{ fontSize: '11px', padding: '2px 8px' }} onClick={() => handleCancel(job.jobId)}>
                        Cancel
                      </button>
                    )}
                    {(job.status === 'complete' || job.status === 'error' || job.status === 'cancelled') && (
                      <button className="ghost-btn" style={{ fontSize: '11px', padding: '2px 8px' }} onClick={() => handleDelete(job.jobId)}>
                        Dismiss
                      </button>
                    )}
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}