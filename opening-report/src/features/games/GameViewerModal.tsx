import { useEffect, useState, useRef, useCallback } from 'react';
import { Chess, type Move } from 'chess.js';
import { parsePGNHeaders } from '@/lib/chess-helpers';
import MiniBoard from '@/features/board/MiniBoard';

interface GameViewerEventDetail {
  pgn: string;
  title?: string;
}

export default function GameViewerModal() {
  const [isOpen, setIsOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [history, setHistory] = useState<Move[]>([]);
  const [ply, setPly] = useState(0);
  const [headers, setHeaders] = useState<Record<string, string>>({});
  const [loadError, setLoadError] = useState(false);
  const [currentFen, setCurrentFen] = useState('start');

  const historyRef = useRef<Move[]>([]);

  const updateFen = useCallback((targetPly: number, moveHistory: Move[]) => {
    const tempChess = new Chess();
    for (let i = 0; i < targetPly; i++) {
      try {
        tempChess.move(moveHistory[i]);
      } catch {
        break;
      }
    }
    setCurrentFen(tempChess.fen());
  }, []);

  const goToPly = useCallback(
    (targetPly: number, moveHistory: Move[]) => {
      const clamped = Math.max(0, Math.min(targetPly, moveHistory.length));
      setPly(clamped);
      updateFen(clamped, moveHistory);
    },
    [updateFen],
  );

  useEffect(() => {
    const handleOpen = (event: Event) => {
      const detail = (event as CustomEvent<GameViewerEventDetail>).detail;
      if (!detail || !detail.pgn) return;

      const chess = new Chess();
      try {
        chess.loadPgn(detail.pgn);
      } catch (e) {
        console.error('Failed to load PGN:', e);
        setLoadError(true);
      }

      const moveHistory = chess.history({ verbose: true });
      const parsedHeaders = parsePGNHeaders(detail.pgn);

      setTitle(detail.title || 'Game Viewer');
      setHistory(moveHistory);
      historyRef.current = moveHistory;
      setPly(0);
      setHeaders(parsedHeaders);
      setLoadError(false);
      setCurrentFen('start');
      setIsOpen(true);
    };
    window.addEventListener('scidb:open-game-viewer', handleOpen);
    return () => window.removeEventListener('scidb:open-game-viewer', handleOpen);
  }, []);

  const handleClose = () => {
    setIsOpen(false);
  };

  if (!isOpen) return null;

  const whitePlayer = headers.White || '?';
  const whiteElo = headers.WhiteElo || '?';
  const blackPlayer = headers.Black || '?';
  const blackElo = headers.BlackElo || '?';
  const result = headers.Result || '*';

  return (
    <div
      id="game-modal"
      className="modal"
      style={{ display: 'flex' }}
      onClick={(e) => {
        if (e.target === e.currentTarget) handleClose();
      }}
    >
      <div className="modal-content modal-large">
        <div className="modal-header">
          <h3 id="game-modal-title">{title}</h3>
          <button id="game-modal-close" className="modal-close" onClick={handleClose}>
            ✕
          </button>
        </div>
        <div className="modal-body">
          <div id="game-viewer-board" style={{ width: '100%', maxWidth: '400px' }}>
            <MiniBoard fen={currentFen} />
          </div>
          <div id="game-viewer-info">
            <p id="game-viewer-players">
              {whitePlayer} ({whiteElo}) vs {blackPlayer} ({blackElo})
            </p>
            <p id="game-viewer-result">Result: {result}</p>
            {loadError && (
              <p style={{ color: 'var(--accent-red)', fontSize: '13px' }}>
                Failed to load PGN data.
              </p>
            )}
            <div id="game-viewer-controls">
              <button id="gv-start" className="ctrl-btn" onClick={() => goToPly(0, history)}>
                ⏮
              </button>
              <button id="gv-prev" className="ctrl-btn" onClick={() => goToPly(ply - 1, history)}>
                ◀
              </button>
              <button id="gv-next" className="ctrl-btn" onClick={() => goToPly(ply + 1, history)}>
                ▶
              </button>
              <button id="gv-end" className="ctrl-btn" onClick={() => goToPly(history.length, history)}>
                ⏭
              </button>
            </div>
            <div id="game-viewer-moves">
              {history.length === 0 ? (
                <span style={{ color: 'var(--text-dim)', fontSize: '12px' }}>
                  No moves to display.
                </span>
              ) : (
                history.map((m, i) => {
                  const moveNum = Math.floor(i / 2) + 1;
                  const isWhite = m.color === 'w';
                  return (
                    <span
                      key={i}
                      className={`move-cell ${i === ply - 1 ? 'active' : ''}`}
                      onClick={() => goToPly(i + 1, history)}
                      style={{ cursor: 'pointer' }}
                    >
                      {isWhite ? (
                        <>
                          <span className="move-num">{moveNum}.</span>{' '}
                          <span className="move-text">{m.san}</span>
                        </>
                      ) : (
                        <span className="move-text">{m.san}</span>
                      )}
                    </span>
                  );
                })
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}