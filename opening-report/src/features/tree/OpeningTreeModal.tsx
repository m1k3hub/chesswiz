import { useEffect, useState, useCallback } from 'react';
import { createApiClient } from '@/api/client';
import { useWorkspaceStore } from '@/state/workspace';
import type { OpeningMove, OpeningTreeRequest } from '@/types';

const api = createApiClient();

export default function OpeningTreeModal() {
  const [isOpen, setIsOpen] = useState(false);
  const [rows, setRows] = useState<OpeningMove[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [positionLabel, setPositionLabel] = useState('Start position');
  const currentFen = useWorkspaceStore((s) => s.currentFen);
  const toast = window.ScidbWorkspace?.toast || console.log;

  const loadTree = useCallback(async () => {
    setIsLoading(true);

    // Gather moves from the global ChessBoard handle.
    const gameMoves = (window as unknown as Record<string, unknown>).__scidbGameMoves as
      { uci: string; san: string }[] | undefined;

    const moves = gameMoves ?? [];
    const request: OpeningTreeRequest = {
      moves,
      fen: currentFen,
      source: 'masters',
    };

    // Build a human-readable position label.
    if (moves.length === 0) {
      setPositionLabel('Start position');
    } else {
      setPositionLabel(moves.map((m) => m.san).join(' '));
    }

    try {
      const data = await api.getOpeningTree(request);
      setRows(data);
    } catch (err) {
      toast(`Failed to load opening tree: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    } finally {
      setIsLoading(false);
    }
  }, [currentFen, toast]);

  useEffect(() => {
    const handleOpen = () => {
      setIsOpen(true);
      loadTree();
    };
    window.addEventListener('scidb:open-opening-tree', handleOpen);
    return () => window.removeEventListener('scidb:open-opening-tree', handleOpen);
  }, [loadTree]);

  if (!isOpen) return null;

  return (
    <div id="opening-tree-modal" className="modal" style={{ display: 'flex' }} onClick={(e) => {
      if (e.target === e.currentTarget) setIsOpen(false);
    }}>
      <div className="modal-content opening-tree-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">REFERENCE DATABASE · MASTER GAMES</span>
            <h3>Opening tree</h3>
          </div>
          <button id="opening-tree-close" className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>
        <div className="tree-context">
          <span>Current position</span>
          <strong>{positionLabel}</strong>
          <small>Click a move to continue the line</small>
        </div>
        <div className="tree-head">
          <span>MOVE</span>
          <span>GAMES</span>
          <span>W / D / L</span>
          <span>SCORE</span>
          <span>ECO</span>
        </div>
        <div id="opening-tree-list" className="opening-tree-list">
          {isLoading ? (
            <div className="database-empty">Reading opening tree…</div>
          ) : rows.length === 0 ? (
            <div className="database-empty">No opening data available for this position.</div>
          ) : (
            rows.map((move) => {
              const total = move.white + move.draw + move.black;
              const wPct = total > 0 ? (move.white / total * 100).toFixed(1) : '0';
              const dPct = total > 0 ? (move.draw / total * 100).toFixed(1) : '0';
              const bPct = total > 0 ? (move.black / total * 100).toFixed(1) : '0';

              return (
                <button
                  key={move.san}
                  className="tree-row"
                  data-san={move.san}
                  onClick={() => toast(`Candidate ${move.san} selected — play it on the board`, 'accent')}
                >
                  <span className="tree-move">{move.san}</span>
                  <span className="tree-count">{Number(move.games).toLocaleString()}<small>games</small></span>
                  <span className="tree-score">
                    <div className="win-bar" style={{ minWidth: '100px', height: '12px' }}>
                      <div className="w-white" style={{ width: `${wPct}%` }}></div>
                      <div className="w-draw" style={{ width: `${dPct}%` }}></div>
                      <div className="w-black" style={{ width: `${bPct}%` }}></div>
                    </div>
                  </span>
                  <span className="tree-score">
                    <i style={{ width: `${move.score}%` }}></i>
                    <small>{move.score}%</small>
                  </span>
                  <span className="tree-eco">{move.eco}</span>
                </button>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}