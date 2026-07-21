/*
 * MiniBoard — small read-only React/SVG chessboard for modals (tactics,
 * game viewer, game editor).  No chessboard.js or jQuery dependency.
 *
 * Accepts a FEN string and renders an 8×8 board with the same piece glyphs
 * and square colors as ChessBoard.tsx.  Supports board orientation flip and
 * an optional onSquareClick callback for interactive tactics puzzles.
 */

import { useMemo } from 'react';
import { Chess } from 'chess.js';
import './MiniBoard.css';

/* ---------- types ---------- */

export interface MiniBoardProps {
  fen: string;
  orientation?: 'white' | 'black';
  onSquareClick?: (square: string) => void;
  selectedSquare?: string | null;
  validTargets?: Set<string>;
}

/* ---------- constants ---------- */

const PIECE_GLYPH: Record<string, string> = {
  k: '♚', q: '♛', r: '♜', b: '♝', n: '♞', p: '♟',
};

const FILES = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] as const;
const RANKS = [8, 7, 6, 5, 4, 3, 2, 1] as const;

/* ---------- component ---------- */

export default function MiniBoard({
  fen,
  orientation = 'white',
  onSquareClick,
  selectedSquare,
  validTargets,
}: MiniBoardProps) {
  // Parse the FEN into a board array. We use chess.js for robust parsing.
  const board = useMemo(() => {
    try {
      const chess = new Chess(fen);
      return chess.board();
    } catch {
      // FEN might be 'start' or invalid; fall back to the start position.
      try {
        return new Chess().board();
      } catch {
        return new Chess().board();
      }
    }
  }, [fen]);

  const flipped = orientation === 'black';
  const displayRanks = flipped ? [...RANKS].reverse() : RANKS;
  const displayFiles = flipped ? [...FILES].reverse() : FILES;

  const squares: JSX.Element[] = [];
  for (let r = 0; r < 8; r++) {
    for (let c = 0; c < 8; c++) {
      const rank = displayRanks[r];
      const file = displayFiles[c];
      const square = `${file}${rank}`;
      const boardRow = 8 - rank;
      const boardCol = FILES.indexOf(file);
      const piece = board[boardRow]?.[boardCol];
      const isLight = (boardRow + boardCol) % 2 === 0;
      const isSelected = selectedSquare === square;
      const isValidTarget = validTargets?.has(square) ?? false;
      const hasPiece = piece !== null && piece !== undefined;

      squares.push(
        <div
          key={square}
          className={[
            'mini-square',
            isLight ? 'light' : 'dark',
            isSelected ? 'selected' : '',
            isValidTarget ? 'valid-target' : '',
            isValidTarget && hasPiece ? 'valid-capture' : '',
            onSquareClick ? 'clickable' : '',
          ]
            .filter(Boolean)
            .join(' ')}
          onClick={onSquareClick ? () => onSquareClick(square) : undefined}
          data-square={square}
        >
          {c === 0 && (
            <span className="mini-coord rank-coord">{rank}</span>
          )}
          {r === 7 && (
            <span className="mini-coord file-coord">{file}</span>
          )}
          {hasPiece && (
            <span
              className={`mini-piece ${piece!.color === 'w' ? 'white' : 'black'}`}
            >
              {PIECE_GLYPH[piece!.type]}
            </span>
          )}
        </div>,
      );
    }
  }

  return (
    <div className="mini-board-wrapper">
      <div className="mini-board">{squares}</div>
    </div>
  );
}