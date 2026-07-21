/**
 * BoardPanel — React shell around the chessboard and report controls.
 *
 * The board, move list, navigation controls, and FEN loading are owned by
 * the React ChessBoard component. Report controls (data source, time control,
 * rating, generate button) remain here; the generate button dispatches a
 * `scidb:generate-report` custom event that the OpeningReport component
 * listens for.
 */

import { useRef, useCallback } from 'react';
import ChessBoard, { type ChessBoardHandle, type GameMove } from '@/features/board/ChessBoard';

export interface GenerateReportDetail {
  moves: GameMove[];
  fen: string;
  source: string;
  speed: string;
  ratingRange: string;
}

export default function BoardPanel() {
  const boardRef = useRef<ChessBoardHandle>(null);

  const handleGenerate = useCallback(() => {
    const moves = boardRef.current?.getMoves() ?? [];
    if (moves.length === 0) {
      alert('Please make at least one move on the board before generating a report.');
      return;
    }

    const fen = boardRef.current?.getCurrentFen() ?? '';
    const source = (document.getElementById('data-source') as HTMLSelectElement | null)?.value || 'masters';
    const speed = (document.getElementById('time-control') as HTMLSelectElement | null)?.value || 'blitz';
    const ratingRange = (document.getElementById('rating-range') as HTMLSelectElement | null)?.value || 'all';

    window.dispatchEvent(new CustomEvent<GenerateReportDetail>('scidb:generate-report', {
      detail: { moves, fen, source, speed, ratingRange },
    }));
  }, []);

  return (
    <div id="board-panel">
      <div className="workspace-toolbar">
        <div>
          <span className="eyebrow">DATABASE / MASTER GAMES</span>
          <h2>Opening laboratory</h2>
        </div>
        <div className="toolbar-actions">
          <button className="ghost-btn" onClick={() => window.ScidbWorkspace?.toast('PGN import is ready for the API adapter', 'accent')}>
            Import PGN
          </button>
          <button
            className="primary-btn"
            onClick={() => {
              window.ScidbWorkspace?.toast('Database creation is ready for the API adapter', 'accent');
              window.ScidbWorkspace?.setActivePanel('database-manager');
            }}
          >
            ＋ New database
          </button>
        </div>
      </div>

      <ChessBoard ref={boardRef} onPositionChange={(fen) => window.ScidbWorkspace?.setCurrentFen(fen)} />

      <div id="report-controls">
        <div className="section-heading">
          <div>
            <span className="eyebrow">POSITION ANALYSIS</span>
            <h3>Opening report</h3>
          </div>
          <span className="live-chip">● LIVE</span>
        </div>
        <div className="control-group">
          <label>Data Source</label>
          <select id="data-source" defaultValue="masters">
            <option value="masters">Masters (OTB)</option>
            <option value="lichess">Lichess (all players)</option>
          </select>
        </div>
        <div className="control-group" id="speed-group">
          <label>Time Control</label>
          <select id="time-control" defaultValue="blitz">
            <option value="blitz">Blitz</option>
            <option value="rapid">Rapid</option>
            <option value="classical">Classical</option>
            <option value="all">All</option>
          </select>
        </div>
        <div className="control-group" id="rating-group">
          <label>Rating Range</label>
          <select id="rating-range" defaultValue="all">
            <option value="all">All ratings</option>
            <option value="elo">Elo-segmented (all ranges)</option>
            <option value="low">Below 1600</option>
            <option value="club">1600–2200</option>
            <option value="high">2200–2500</option>
            <option value="top">2500+</option>
          </select>
        </div>
        <button id="btn-generate" className="generate-btn" onClick={handleGenerate}>
          Generate report <span>⌘ ↵</span>
        </button>
      </div>
    </div>
  );
}