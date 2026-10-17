import { useCallback, useEffect, useRef, useState } from 'react';
import React from 'react';
import { createApiClient } from '@/api/client';
import { useWorkspaceStore } from '@/state/workspace';
import { subscribeToAnalysis } from '@/api/websocket';
import type { AnalysisJob, AnalysisLine, EngineInfo } from '@/types';

const api = createApiClient();

const DEFAULT_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

const POLL_INTERVAL = 600; // ms

/**
 * Format a UCI principal variation into human-readable move notation.
 * e.g. "e2e4 e7e5 g1f3" → "1. e2e4 e7e5 2. g1f3"
 */
function formatPv(pv: string): string {
  if (!pv) return '—';
  const moves = pv.trim().split(/\s+/);
  const out: string[] = [];
  let moveNum = 1;
  for (let i = 0; i < moves.length; i += 1) {
    if (i % 2 === 0) {
      out.push(`${moveNum}. ${moves[i]}`);
    } else {
      out.push(moves[i]);
      moveNum += 1;
    }
  }
  return out.join(' ');
}

/**
 * EngineInspector — React port of the legacy engine-inspector.js.
 *
 * Renders the UCI engine analysis panel: engine/depth/lines selectors,
 * start/stop/clear controls, eval bar, depth/nodes/nps metrics, and
 * principal variations. Polls the typed API client and subscribes to
 * workspace FEN changes so analysis always targets the current position.
 */
export default function EngineInspector({ visible }: { visible: boolean }) {
  // Config state
  const [engines, setEngines] = useState<EngineInfo[]>([]);
  const [engineId, setEngineId] = useState('stockfish');
  const [depth, setDepth] = useState(20);
  const [multiPv, setMultiPv] = useState(3);

  // Analysis state
  const [isRunning, setIsRunning] = useState(false);
  const [evalText, setEvalText] = useState('0.00');
  const [evalPct, setEvalPct] = useState(50);
  const [depthText, setDepthText] = useState('—');
  const [nodesText, setNodesText] = useState('— nodes');
  const [npsText, setNpsText] = useState('— nps');
  const [lines, setLines] = useState<AnalysisLine[]>([]);

  const [useStreaming, setUseStreaming] = useState(true);
  const unsubscribeRef = useRef<(() => void) | null>(null);

  // Refs for polling lifecycle
  const jobIdRef = useRef<string | null>(null);
  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const fenRef = useRef<string>(DEFAULT_FEN);

  // Subscribe to workspace FEN changes
  const currentFen = useWorkspaceStore((s) => s.currentFen);
  const setActiveEngineJobId = useWorkspaceStore((s) => s.setActiveEngineJobId);
  const toast = window.ScidbWorkspace?.toast || console.log;

  // Rated-game engine lock (docs/plans/ONLINE_PLAY_PLAN.md §5.2, Phase 7): defense in
  // depth alongside the server-side /api/analysis/start check.
  const activePlayMode = useWorkspaceStore((s) => s.activePlayMode);
  const activeMatch = useWorkspaceStore((s) => s.activeMatch);
  const ratedLocked = activePlayMode === 'play' && !!activeMatch?.rated && activeMatch.status === 'playing';

  const renderIdle = useCallback(() => {
    setEvalText('0.00');
    setEvalPct(50);
    setDepthText('—');
    setNodesText('— nodes');
    setNpsText('— nps');
    setLines([]);
  }, []);

  // Fetch available engines on mount
  useEffect(() => {
    let cancelled = false;
    api.getEngines().then((list) => {
      if (!cancelled && list.length > 0) {
        setEngines(list);
        setEngineId(list[0].engineId);
      }
    }).catch(() => { /* mock fallback uses default */ });
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    if (currentFen && currentFen !== fenRef.current) {
      fenRef.current = currentFen;
      if (!jobIdRef.current) {
        renderIdle();
      }
    }
  }, [currentFen, renderIdle]);

  const clearPolling = useCallback(() => {
    if (pollTimerRef.current) {
      clearInterval(pollTimerRef.current);
      pollTimerRef.current = null;
    }
  }, []);

  const finish = useCallback(() => {
    clearPolling();
    jobIdRef.current = null;
    setActiveEngineJobId(null);
    setIsRunning(false);
  }, [clearPolling, setActiveEngineJobId]);

  const stop = useCallback(async () => {
    const currentJobId = jobIdRef.current;
    clearPolling();
    if (currentJobId) {
      try {
        await api.stopAnalysis(currentJobId);
      } catch {
        /* noop */
      }
    }
    jobIdRef.current = null;
    setActiveEngineJobId(null);
    setIsRunning(false);
  }, [clearPolling, setActiveEngineJobId]);

  const renderAnalysis = useCallback((data: AnalysisJob) => {
    const best = data.lines && data.lines[0];
    const score = best ? parseFloat(best.eval) : 0;
    const scoreText = score > 0 ? `+${score.toFixed(2)}` : score.toFixed(2);
    setEvalText(scoreText);
    setDepthText(`${data.depth || 0}`);
    setNodesText(`${(data.nodes || 0).toLocaleString()} nodes`);
    setNpsText(`${((data.nps || 0) / 1000).toFixed(0)}k nps`);

    const pct = Math.max(0, Math.min(100, 50 + score * 8));
    setEvalPct(pct);
    setLines(data.lines || []);
  }, []);

  const poll = useCallback(
    async (id: string) => {
      try {
        const data = await api.getAnalysis(id);
        if (!data || data.status === 'unknown' || data.status === 'stopped') {
          stop();
          return;
        }
        renderAnalysis(data);
        if (data.status === 'complete') {
          finish();
        }
      } catch (e) {
        console.warn('Engine poll failed', e);
      }
    },
    [stop, finish, renderAnalysis]
  );

  const clearSubscription = useCallback(() => {
    unsubscribeRef.current?.();
    unsubscribeRef.current = null;
  }, []);

  const applyAnalysisUpdate = useCallback((data: AnalysisJob) => {
    renderAnalysis(data);
    if (data.status === 'complete' || data.status === 'stopped' || data.status === 'unknown') {
      finish();
    }
  }, [renderAnalysis, finish]);

  const start = useCallback(async () => {
    if (ratedLocked) {
      toast('Engine disabled during a rated game', 'warning');
      return;
    }
    if (jobIdRef.current) await stop();

    setIsRunning(true);
    try {
      const response = await api.startAnalysis({
        fen: fenRef.current,
        multiPv,
        depth,
        engineId,
      });
      jobIdRef.current = response.jobId;
      setActiveEngineJobId(response.jobId);

      if (useStreaming) {
        clearSubscription();
        unsubscribeRef.current = subscribeToAnalysis(response.jobId, (msg) => {
          const data = msg as AnalysisJob;
          applyAnalysisUpdate(data);
        });
      } else {
        const capturedJobId = response.jobId;
        clearPolling();
        pollTimerRef.current = setInterval(() => poll(capturedJobId), POLL_INTERVAL);
      }
    } catch (e) {
      toast(`Engine start failed: ${e instanceof Error ? e.message : String(e)}`, 'accent');
      setIsRunning(false);
    }
  }, [ratedLocked, stop, multiPv, depth, engineId, setActiveEngineJobId, clearPolling, poll, toast, useStreaming, clearSubscription, applyAnalysisUpdate]);

  const clear = useCallback(() => {
    stop();
    clearSubscription();
    renderIdle();
  }, [stop, renderIdle, clearSubscription]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      clearPolling();
      clearSubscription();
    };
  }, [clearPolling, clearSubscription]);

  // Don't render when the Overview tab is active
  if (!visible) return null;

  return (
    <div id="engine-inspector" className="visible">
      <div className="engine-toolbar">
        <div className="engine-control-group">
          <label>Engine</label>
          <select
            value={engineId}
            onChange={(e) => setEngineId(e.target.value)}
            disabled={isRunning}
          >
            {engines.length > 0 ? (
              engines.map((eng) => (
                <option key={eng.engineId} value={eng.engineId}>{eng.name}</option>
              ))
            ) : (
              <React.Fragment>
              <option value="stockfish">Stockfish 16</option>
              <option value="stockfish-15">Stockfish 15</option>
              </React.Fragment>
            )}
          </select>
        </div>
        <div className="engine-control-group">
          <label>Depth</label>
          <select
            value={depth}
            onChange={(e) => setDepth(parseInt(e.target.value, 10))}
            disabled={isRunning}
          >
            <option value={15}>15</option>
            <option value={20}>20</option>
            <option value={25}>25</option>
            <option value={30}>30</option>
          </select>
        </div>
        <div className="engine-control-group">
          <label>Lines</label>
          <select
            value={multiPv}
            onChange={(e) => setMultiPv(parseInt(e.target.value, 10))}
            disabled={isRunning}
          >
            <option value={1}>1</option>
            <option value={3}>3</option>
            <option value={5}>5</option>
          </select>
        </div>
        <div className="engine-control-group">
          <label>Transport</label>
          <select
            value={useStreaming ? 'ws' : 'poll'}
            onChange={(e) => setUseStreaming(e.target.value === 'ws')}
            disabled={isRunning}
          >
            <option value="ws">WebSocket stream</option>
            <option value="poll">HTTP poll</option>
          </select>
        </div>
        <div className="engine-actions">
          <button
            id="engine-start-btn"
            className="primary-btn"
            onClick={start}
            disabled={isRunning || ratedLocked}
            title={ratedLocked ? 'Engine disabled during a rated game' : undefined}
          >
            {isRunning ? 'Running…' : ratedLocked ? 'Locked (rated game)' : 'Start'}
          </button>
          <button
            id="engine-stop-btn"
            className="ghost-btn"
            onClick={stop}
            disabled={!isRunning}
          >
            Stop
          </button>
          <button
            id="engine-clear-btn"
            className="ghost-btn"
            onClick={clear}
          >
            Clear
          </button>
        </div>
      </div>

      <div className="engine-status-row">
        <div id="engine-eval">{evalText}</div>
        <div id="engine-eval-bar" style={{ ['--eval-pct' as string]: `${evalPct}%` }}>
          <div className="engine-eval-marker"></div>
        </div>
        <div className="engine-meta">
          <span id="engine-depth">{depthText}</span>
          <span id="engine-nodes">{nodesText}</span>
          <span id="engine-nps">{npsText}</span>
        </div>
      </div>

      <div id="engine-lines">
        {lines.length === 0 ? (
          <div className="engine-line-placeholder">
            Start analysis to see principal variations.
          </div>
        ) : (
          lines.map((line, idx) => (
            <div className="engine-line" key={idx}>
              <span className="engine-line-rank">{idx + 1}</span>
              <span
                className="engine-line-eval"
                data-eval={line.eval}
              >
                {line.eval}
              </span>
              <span className="engine-line-depth">
                d{line.depth || depthText}
              </span>
              <span className="engine-line-pv">{formatPv(line.pv)}</span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}