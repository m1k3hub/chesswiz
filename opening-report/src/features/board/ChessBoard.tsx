/*
 * ChessBoard — React chessboard with chess.js move validation and a simple
 * CSS/SVG renderer. No chessboard.js or jQuery dependency.
 *
 * Ports the board + move-list logic from public/js/app.js.
 */

import {
  useState,
  useCallback,
  useRef,
  useEffect,
  forwardRef,
  useImperativeHandle,
  type ChangeEvent,
  type KeyboardEvent,
} from 'react';
import { Chess, type Square } from 'chess.js';
import { useWorkspaceStore } from '@/state/workspace';
import { isValidFen } from '@/lib/validation';
import type { PlayMode } from '@/types';
import PromotionPicker, { type PromoPiece } from './PromotionPicker';
import './ChessBoard.css';

/* ---------- types ---------- */

export interface GameMove {
  san: string;
  uci: string;
  fen: string;
  color: 'w' | 'b';
}

export interface ChessBoardHandle {
  getMoves: () => GameMove[];
  getCurrentFen: () => string;
  /** Apply a move by UCI (e.g. "e2e4", "e7e8q") programmatically — used by the
   * hotseat controller and the live WebSocket play channel. Returns false on
   * illegal move. Bypasses the promotion picker (the uci carries the piece). */
  applyExternalMove: (uci: string) => boolean;
}

interface ChessBoardProps {
  onPositionChange?: (fen: string) => void;
  /** 'analysis' (default) = free move, takeback, FEN load. 'play' = legal-only,
   *  no takeback, no FEN load, opponent-side rejection when myColor is set. */
  mode?: PlayMode;
  /** When set in play mode, only this colour's pieces are selectable by click
   *  — prevents moving the opponent's pieces on their turn. Undefined = hotseat
   *  (both sides playable on their turn). */
  myColor?: 'w' | 'b';
  /** Optional start position seed (FEN). Respected at mount only; this is a
   *  match seed, not a mid-game load, so it is allowed in play mode. Used for
   *  Chess960/custom starts and for tests. */
  startFen?: string;
}

/* ---------- constants ---------- */

/** Filled glyph set — coloured via CSS for contrast on both square shades. */
const PIECE_GLYPH: Record<string, string> = {
  k: '♚', q: '♛', r: '♜', b: '♝', n: '♞', p: '♟',
};

const FILES = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] as const;
const RANKS = [8, 7, 6, 5, 4, 3, 2, 1] as const;

/* ---------- component ---------- */

const ChessBoard = forwardRef<ChessBoardHandle, ChessBoardProps>(
  ({ onPositionChange, mode = 'analysis', myColor, startFen }, ref) => {
    const chessRef = useRef(startFen ? new Chess(startFen) : new Chess());
    const [gameHistory, setGameHistory] = useState<GameMove[]>([]);
    const [currentPly, setCurrentPly] = useState(0);
    const [flipped, setFlipped] = useState(false);
    const [selectedSquare, setSelectedSquare] = useState<string | null>(null);
    const [validTargets, setValidTargets] = useState<Set<string>>(new Set());
    const [fenInput, setFenInput] = useState('');
    const [pendingPromotion, setPendingPromotion] = useState<{ from: string; to: string } | null>(null);

    const isPlay = mode === 'play';

    const setCurrentFen = useWorkspaceStore((s) => s.setCurrentFen);

    // Refs to avoid stale closures inside callbacks.
    const gameHistoryRef = useRef(gameHistory);
    const currentPlyRef = useRef(currentPly);
    gameHistoryRef.current = gameHistory;
    currentPlyRef.current = currentPly;

    /* ----- imperative handle ----- */

    useImperativeHandle(ref, () => ({
      getMoves: () => gameHistoryRef.current.slice(0, currentPlyRef.current),
      getCurrentFen: () => chessRef.current.fen(),
      applyExternalMove: (uci: string) => {
        if (uci.length < 4) return false;
        const from = uci.slice(0, 2);
        const to = uci.slice(2, 4);
        const promo = (uci[4] as PromoPiece | undefined) || 'q';
        return makeMove(from, to, promo, { external: true });
      },
    }));

    /* ----- position sync ----- */

    const syncPosition = useCallback(
      (newFen: string, notify = true) => {
        setFenInput(newFen);
        setCurrentFen(newFen);
        if (notify) onPositionChange?.(newFen);
      },
      [setCurrentFen, onPositionChange],
    );

    // Expose game state for legacy modules (report.js generateReport).
    useEffect(() => {
      (window as unknown as Record<string, unknown>).__scidbGameMoves =
        gameHistory.slice(0, currentPly);
    }, [gameHistory, currentPly]);

    /* ----- move making ----- */

    const makeMove = useCallback(
      (from: string, to: string, promotion: PromoPiece = 'q', opts?: { external?: boolean }): boolean => {
        const chess = chessRef.current;

        // In play mode there is no takeback, so the cursor is always at the
        // tail of history; never truncate. In analysis mode, truncate when
        // navigating from a non-final ply (legacy behaviour, unchanged).
        if (!isPlay && currentPlyRef.current < gameHistoryRef.current.length) {
          gameHistoryRef.current = gameHistoryRef.current.slice(
            0,
            currentPlyRef.current,
          );
        }

        try {
          const move = chess.move({ from, to, promotion });
          if (!move) return false;

          const entry: GameMove = {
            san: move.san,
            uci: move.from + move.to + (move.promotion || ''),
            fen: chess.fen(),
            color: move.color,
          };

          const nextHistory = [...gameHistoryRef.current, entry];
          gameHistoryRef.current = nextHistory;
          currentPlyRef.current = nextHistory.length;
          setGameHistory(nextHistory);
          setCurrentPly(nextHistory.length);
          syncPosition(chess.fen(), !opts?.external);
          return true;
        } catch {
          return false;
        }
      },
      [syncPosition, isPlay],
    );

    /* ----- click interaction ----- */

    const handleSquareClick = useCallback(
      (square: string) => {
        const chess = chessRef.current;

        // Attempt a move if a piece is selected and the target is valid.
        if (selectedSquare && validTargets.has(square)) {
          // In play mode, surface a promotion picker instead of auto-queening.
          if (isPlay) {
            const moves = chess.moves({ square: selectedSquare as Square, verbose: true });
            const targetMoves = moves.filter((m) => m.to === square);
            const isPromotion = targetMoves.some((m) => m.promotion);
            if (isPromotion) {
              setPendingPromotion({ from: selectedSquare, to: square });
              setSelectedSquare(null);
              setValidTargets(new Set());
              return;
            }
          }
          makeMove(selectedSquare, square);
          setSelectedSquare(null);
          setValidTargets(new Set());
          return;
        }

        // Click the same square — deselect.
        if (square === selectedSquare) {
          setSelectedSquare(null);
          setValidTargets(new Set());
          return;
        }

        // Select a piece if it belongs to the side to move. In play mode with
        // myColor set, additionally require the piece to be the user's own colour
        // so the opponent's pieces can't be moved on the opponent's turn.
        const piece = chess.get(square as Square);
        if (
          piece &&
          piece.color === chess.turn() &&
          (!isPlay || !myColor || piece.color === myColor)
        ) {
          setSelectedSquare(square);
          const moves = chess.moves({ square: square as Square, verbose: true });
          setValidTargets(new Set(moves.map((m) => m.to)));
        } else {
          setSelectedSquare(null);
          setValidTargets(new Set());
        }
      },
      [selectedSquare, validTargets, makeMove, isPlay, myColor],
    );

    /* ----- navigation ----- */

    const goToPly = useCallback(
      (ply: number) => {
        const clamped = Math.max(0, Math.min(ply, gameHistoryRef.current.length));
        const chess =
          clamped === 0
            ? new Chess()
            : new Chess(gameHistoryRef.current[clamped - 1].fen);
        chessRef.current = chess;
        setCurrentPly(clamped);
        setSelectedSquare(null);
        setValidTargets(new Set());
        syncPosition(chess.fen());
      },
      [syncPosition],
    );

    const goStart = useCallback(() => goToPly(0), [goToPly]);
    const goPrev = useCallback(() => goToPly(currentPlyRef.current - 1), [goToPly]);
    const goNext = useCallback(() => goToPly(currentPlyRef.current + 1), [goToPly]);
    const goEnd = useCallback(() => goToPly(gameHistoryRef.current.length), [goToPly]);
    const toggleFlip = useCallback(() => setFlipped((f) => !f), []);

    /* ----- FEN loading ----- */

    const handleLoadFen = useCallback(() => {
      const trimmed = fenInput.trim();
      if (!trimmed) return;
      if (!isValidFen(trimmed)) {
        window.ScidbWorkspace?.toast('Invalid FEN: malformed or illegal position', 'warning');
        return;
      }
      try {
        const newChess = new Chess(trimmed);
        chessRef.current = newChess;
        setGameHistory([]);
        setCurrentPly(0);
        setSelectedSquare(null);
        setValidTargets(new Set());
        syncPosition(newChess.fen());
      } catch (e) {
        window.ScidbWorkspace?.toast(
          'Invalid FEN: ' + (e instanceof Error ? e.message : String(e)),
          'warning',
        );
      }
    }, [fenInput, syncPosition]);

    const handleFenKeyDown = useCallback(
      (e: KeyboardEvent<HTMLInputElement>) => {
        if (e.key === 'Enter') handleLoadFen();
      },
      [handleLoadFen],
    );

    const handleFenInputChange = useCallback(
      (e: ChangeEvent<HTMLInputElement>) => setFenInput(e.target.value),
      [],
    );

    /* ----- board rendering ----- */

    const board = chessRef.current.board();
    const displayRanks = flipped ? [...RANKS].reverse() : RANKS;
    const displayFiles = flipped ? [...FILES].reverse() : FILES;

    const squares: JSX.Element[] = [];
    for (let r = 0; r < 8; r++) {
      for (let c = 0; c < 8; c++) {
        const rank = displayRanks[r];
        const file = displayFiles[c];
        const square = `${file}${rank}`;
        // chess.js board[0] = rank 8, board[0][0] = a8
        const boardRow = 8 - rank;
        const boardCol = FILES.indexOf(file);
        const piece = board[boardRow][boardCol];
        const isLight = (boardRow + boardCol) % 2 === 0;
        const isSelected = selectedSquare === square;
        const isValidTarget = validTargets.has(square);
        const hasPiece = piece !== null && piece !== undefined;

        squares.push(
          <div
            key={square}
            className={[
              'scidb-square',
              isLight ? 'light' : 'dark',
              isSelected ? 'selected' : '',
              isValidTarget ? 'valid-target' : '',
              isValidTarget && hasPiece ? 'valid-capture' : '',
            ]
              .filter(Boolean)
              .join(' ')}
            onClick={() => handleSquareClick(square)}
            data-square={square}
          >
            {c === 0 && (
              <span className="scidb-coord rank-coord">{rank}</span>
            )}
            {r === 7 && (
              <span className="scidb-coord file-coord">{file}</span>
            )}
            {hasPiece && (
              <span
                className={`scidb-piece ${piece!.color === 'w' ? 'white' : 'black'}`}
              >
                {PIECE_GLYPH[piece!.type]}
              </span>
            )}
          </div>,
        );
      }
    }

    /* ----- move list rendering ----- */

    const renderMoveList = () => {
      if (gameHistory.length === 0) {
        return (
          <span className="scidb-move-list-empty">
            Start position — make moves on the board
          </span>
        );
      }
      return gameHistory.map((m, i) => {
        const moveNum = Math.floor(i / 2) + 1;
        const isWhite = m.color === 'w';
        const isActive = i === currentPly - 1;
        return (
          <span
            key={i}
            className={`move-cell${isActive ? ' active' : ''}`}
            onClick={mode === 'analysis' ? () => goToPly(i + 1) : undefined}
            style={mode === 'play' ? { cursor: 'default' } : undefined}
          >
            {isWhite && <span className="move-num">{moveNum}.</span>}
            <span className="move-text">{m.san}</span>
          </span>
        );
      });
    };

    /* ----- render ----- */

    return (
      <div className="scidb-board-section">
        <div className="scidb-board-wrapper">
          <div className="scidb-board">{squares}</div>
        </div>

        <div className="scidb-controls">
          <button className="ctrl-btn" title="Start position" onClick={goStart} disabled={isPlay}>
            ⏮
          </button>
          <button className="ctrl-btn" title="Previous move" onClick={goPrev} disabled={isPlay}>
            ◀
          </button>
          <button className="ctrl-btn" title="Next move" onClick={goNext} disabled={isPlay}>
            ▶
          </button>
          <button className="ctrl-btn" title="Last move" onClick={goEnd} disabled={isPlay}>
            ⏭
          </button>
          <button className="ctrl-btn" title="Flip board" onClick={toggleFlip}>
            ⇅
          </button>
        </div>

        <div className="scidb-notation">
          <div className="scidb-move-list">
            {renderMoveList()}
          </div>
        </div>

        {mode === 'analysis' && (
          <div className="scidb-fen-bar">
            <input
              type="text"
              placeholder="Paste FEN or make moves on board…"
              value={fenInput}
              onChange={handleFenInputChange}
              onKeyDown={handleFenKeyDown}
            />
            <button className="small-btn" onClick={handleLoadFen}>
              Load FEN
            </button>
          </div>
        )}

        {pendingPromotion && (
          <PromotionPicker
            color={chessRef.current.turn()}
            onSelect={(piece) => {
              const { from, to } = pendingPromotion;
              setPendingPromotion(null);
              makeMove(from, to, piece);
            }}
            onCancel={() => {
              setPendingPromotion(null);
              setSelectedSquare(null);
              setValidTargets(new Set());
            }}
          />
        )}
      </div>
    );
  },
);

ChessBoard.displayName = 'ChessBoard';

export default ChessBoard;