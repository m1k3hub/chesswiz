import { useEffect, useState, useCallback, useRef } from 'react';
import { createApiClient } from '@/api/client';
import { subscribeToJobEvents } from '@/api/websocket';
import type { JobProgress } from '@/types';

const api = createApiClient();

const STATUS_COLORS: Record<string, string> = {
  pending: 'badge-gray',
  running: 'badge-blue',
  complete: 'badge-green',
  error: 'badge-red',
  cancelled: 'badge-red',
  stopped: 'badge-gray',
};

const TYPE_ICONS: Record<string, string> = {
  search: '⌕',
  import: '⬆',
  export: '⬇',
  report: '▣',
  maintenance: '⚙',
  analysis: '⚖',
};

/**
 * JobCenter — modal showing all active and recent jobs.
 *
 * Listens for `scidb:open-job-center` custom events and WebSocket job
 * progress events. Displays searches, imports, exports, reports,
 * maintenance, and analysis jobs with status, progress bars, and
 * cancel/dismiss actions.
 */
export default function JobCenter() {
  const [isOpen, setIsOpen] = useState(false);
  const [jobs, setJobs] = useState<JobProgress[]>([]);
  const unsubscribeWs = useRef<(() => void) | null>(null);
  const pollTimers = useRef<Map<string, ReturnType<typeof setInterval>>>(new Map());
  const toast = window.ScidbWorkspace?.toast || console.log;

  const stopPolling = useCallback((jobId: string) => {
    const timer = pollTimers.current.get(jobId);
    if (timer) {
      clearInterval(timer);
      pollTimers.current.delete(jobId);
    }
  }, []);

  const addOrUpdateJob = useCallback((job: JobProgress) => {
    setJobs((prev) => {
      const existing = prev.find((j) => j.jobId === job.jobId);
      if (existing) {
        return prev.map((j) => (j.jobId === job.jobId ? job : j));
      }
      return [job, ...prev];
    });
  }, []);

  const _pollJob = useCallback((jobId: string) => {
    stopPolling(jobId);
    pollTimers.current.set(
      jobId,
      setInterval(async () => {
        try {
          const job = await api.getJob(jobId);
          addOrUpdateJob(job);
          if (job.status === 'complete' || job.status === 'error' || job.status === 'cancelled') {
            stopPolling(jobId);
          }
        } catch {
          stopPolling(jobId);
        }
      }, 1000),
    );
  }, [stopPolling, addOrUpdateJob]);

  void _pollJob;

  const handleCancel = useCallback(async (jobId: string) => {
    try {
      const job = await api.cancelJob(jobId);
      addOrUpdateJob(job);
      stopPolling(jobId);
      toast('Job cancelled', 'accent');
    } catch {
      /* noop */
    }
  }, [addOrUpdateJob, stopPolling, toast]);

  const handleDelete = useCallback(async (jobId: string) => {
    stopPolling(jobId);
    try {
      await api.deleteJob(jobId);
    } catch {
      /* noop */
    }
    setJobs((prev) => prev.filter((j) => j.jobId !== jobId));
  }, [stopPolling]);

  useEffect(() => {
    const handleOpen = () => setIsOpen(true);
    window.addEventListener('scidb:open-job-center', handleOpen);
    return () => window.removeEventListener('scidb:open-job-center', handleOpen);
  }, []);

  // Subscribe to WebSocket job events
  useEffect(() => {
    if (!isOpen) return;
    unsubscribeWs.current = subscribeToJobEvents((msg) => {
      const event = msg as { jobId?: string; type?: string; progress?: number; status?: string };
      if (event.jobId) {
        addOrUpdateJob({
          jobId: event.jobId,
          type: (event.type as JobProgress['type']) || 'search',
          status: (event.status as JobProgress['status']) || 'running',
          progress: event.progress || 0,
          total: 100,
          startedAt: Date.now(),
          message: event.status === 'complete' ? 'Job complete' : 'Job running…',
        });
      }
    });
    return () => {
      unsubscribeWs.current?.();
      unsubscribeWs.current = null;
    };
  }, [isOpen, addOrUpdateJob]);

  // Cleanup all timers on close
  useEffect(() => {
    if (!isOpen) {
      pollTimers.current.forEach((timer) => clearInterval(timer));
      pollTimers.current.clear();
    }
  }, [isOpen]);

  // Cleanup on unmount
  useEffect(() => {
    const timers = pollTimers.current;
    return () => {
      timers.forEach((timer) => clearInterval(timer));
      timers.clear();
      unsubscribeWs.current?.();
    };
  }, []);

  if (!isOpen) return null;

  return (
    <div id="job-center-modal" className="modal" style={{ display: 'flex' }} onClick={(e) => {
      if (e.target === e.currentTarget) setIsOpen(false);
    }}>
      <div className="modal-content database-modal-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">SYSTEM</span>
            <h3>Job center</h3>
          </div>
          <button className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>

        <div className="search-results-header">
          <span>{jobs.length} job{jobs.length !== 1 ? 's' : ''}</span>
          <button className="ghost-btn" onClick={() => setJobs([])}>Clear all</button>
        </div>

        <div className="search-results-list">
          {jobs.length === 0 ? (
            <div className="database-empty">No active or recent jobs.</div>
          ) : (
            jobs.map((job) => (
              <div key={job.jobId} className="game-row" style={{ display: 'block', padding: '12px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                  <strong>
                    {TYPE_ICONS[job.type] || '•'} {job.type} — {job.message || job.jobId}
                  </strong>
                  <span className={`badge ${STATUS_COLORS[job.status] || 'badge-gray'}`}>
                    {job.status}
                  </span>
                </div>
                {(job.status === 'running' || job.status === 'pending') && (
                  <div className="win-bar" style={{ height: '6px', marginBottom: '4px' }}>
                    <div className="w-white" style={{ width: `${job.total > 0 ? (job.progress / job.total) * 100 : 0}%` }}></div>
                  </div>
                )}
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <small>
                    {job.total > 0 ? `${job.progress} / ${job.total}` : ''}
                    {job.startedAt ? ` · started ${new Date(job.startedAt).toLocaleTimeString()}` : ''}
                  </small>
                  <div>
                    {(job.status === 'running' || job.status === 'pending') && (
                      <button className="ghost-btn" style={{ fontSize: '11px', padding: '2px 8px' }} onClick={() => handleCancel(job.jobId)}>
                        Cancel
                      </button>
                    )}
                    {(job.status === 'complete' || job.status === 'error' || job.status === 'cancelled' || job.status === 'stopped') && (
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