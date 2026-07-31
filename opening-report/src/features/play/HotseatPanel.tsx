import { useRef, useState, useCallback } from 'react';
import { Chess } from 'chess.js';
import ChessBoard, { type ChessBoardHandle } from '@/features/board/ChessBoard';
import { useWorkspaceStore } from '@/state/workspace';

/**
 * HotseatPanel — local two-player game on the shared ChessBoard in play mode.
 *
 * Phase 1 dev surface: exercises the play-mode restrictions (no takeback, no
 * FEN load, promotion picker, legal-only moves) without a server. Both colours
 * are played from the same browser by clicking; `myColor` is deliberately left
 * undefined so either side may move on its turn. Live online play (Phase 4)
 * replaces this with a `PlayBoardPanel` bound to a WebSocket match.
 *
 * The panel itself is a thin status shell: ChessBoard owns the chess instance;
 * we derive turn/result from the FEN reported via `onPositionChange`. "New
 * game" remounts the board via a key.
 */
type HotseatStatus =
  | { kind: 'playing'; turn: 'w' | 'b' }
  | { kind: 'mate'; winner: 'w' | 'b' }
  | { kind: 'stalemate' }
  | { kind: 'draw'; reason: string };

function deriveStatus(fen: string): HotseatStatus {
  const c = new Chess(fen);
  if (c.isCheckmate()) return { kind: 'mate', winner: c.turn() === 'w' ? 'b' : 'w' };
  if (c.isStalemate()) return { kind: 'stalemate' };
  if (c.isThreefoldRepetition()) return { kind: 'draw', reason: 'threefold repetition' };
  if (c.isInsufficientMaterial()) return { kind: 'draw', reason: 'insufficient material' };
  if (c.isDraw()) return { kind: 'draw', reason: '50-move rule' };
  return { kind: 'playing', turn: c.turn() };
}

export default function HotseatPanel() {
  const boardRef = useRef<ChessBoardHandle>(null);
  const [gameKey, setGameKey] = useState(0);
  const [status, setStatus] = useState<HotseatStatus>(() => ({
    kind: 'playing',
    turn: 'w',
  }));
  const [moveCount, setMoveCount] = useState(0);

  // The Play Center toolbar drives this flag; the board switches between play
  // (enforced rules) and analysis (free move/takeback/FEN) accordingly.
  const mode = useWorkspaceStore((s) => s.activePlayMode);

  const handlePositionChange = useCallback((fen: string) => {
    setStatus(deriveStatus(fen));
    const moves = boardRef.current?.getMoves() ?? [];
    setMoveCount(moves.length);
  }, []);

  const newGame = useCallback(() => {
    setGameKey((k) => k + 1);
    setStatus({ kind: 'playing', turn: 'w' });
    setMoveCount(0);
  }, []);

  const statusText = (() => {
    switch (status.kind) {
      case 'playing':
        return status.turn === 'w' ? 'White to move' : 'Black to move';
      case 'mate':
        return `Checkmate — ${status.winner === 'w' ? 'White' : 'Black'} wins`;
      case 'stalemate':
        return 'Stalemate — draw';
      case 'draw':
        return `Draw — ${status.reason}`;
    }
  })();

  const gameOver = status.kind !== 'playing';

  return (
    <div className="hotseat-panel">
      <div className="hotseat-statusbar">
        <span className={`hotseat-status ${gameOver ? 'finished' : 'playing'}`}>
          {statusText}
        </span>
        <span className="hotseat-moves">{moveCount} ply</span>
        <button className="small-btn" onClick={newGame}>New game</button>
      </div>
      <ChessBoard
        key={gameKey}
        ref={boardRef}
        mode={mode}
        onPositionChange={handlePositionChange}
      />
      <p className="hotseat-hint">
        Hotseat (local, Phase 1) — both players click the same board. In play
        mode, takeback/FEN-load/navigation are disabled; switch to analysis mode
        above to freely examine the position.
      </p>
    </div>
  );
}