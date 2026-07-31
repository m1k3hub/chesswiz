import { useEffect, useRef } from 'react';
import ChessBoard, { type ChessBoardHandle } from '@/features/board/ChessBoard';
import { createApiClient } from '@/api/client';
import { useWorkspaceStore } from '@/state/workspace';
import { mockPlay } from './mockPlayBackend';
import { getSharedPlaySocket } from './playSocket';
import ClockWidget from './ClockWidget';
import MatchControls from './MatchControls';

const api = createApiClient();

/**
 * PlayBoardPanel — the live match surface: board (play mode, myColor) + clocks
 * + controls. Local clicks are submitted via api.submitMove; opponent moves
 * arriving on the event stream are applied with applyExternalMove. The board and
 * the synced move list are reconciled by length: a local move puts the board one
 * ahead of the store (→ submit); an opponent move puts the store one ahead of
 * the board (→ applyExternalMove).
 */
export default function PlayBoardPanel() {
  const boardRef = useRef<ChessBoardHandle>(null);
  const activeMatch = useWorkspaceStore((s) => s.activeMatch);
  const activeMatchMoves = useWorkspaceStore((s) => s.activeMatchMoves);
  const submittedRef = useRef(0);

  // Keep a fresh reference to submitMove without re-binding the onPositionChange
  // callback each render (ChessBoard memoises on identity).
  const movesRef = useRef(activeMatchMoves);
  movesRef.current = activeMatchMoves;

  const myColor = (() => {
    if (!activeMatch) return 'w' as const;
    if (activeMatch.white.id === mockPlay.me.id) return 'w' as const;
    if (activeMatch.black.id === mockPlay.me.id) return 'b' as const;
    return 'w' as const; // spectator fallback (not used in Phase 2)
  })();

  // Anti-cheat v1 signal (Phase 7): report focus-out while it's the
  // opponent's turn. `ply` is the number of moves played; even → white to move.
  useEffect(() => {
    if (!activeMatch || activeMatch.status !== 'playing') return;
    const sideToMove = activeMatch.ply % 2 === 0 ? 'w' : 'b';
    if (sideToMove === myColor) return; // only my own blur matters, and only during opponent's turn
    const onBlur = () => getSharedPlaySocket().sendBlur(activeMatch.id);
    window.addEventListener('blur', onBlur);
    return () => window.removeEventListener('blur', onBlur);
  }, [activeMatch, myColor]);

  // Apply opponent moves that arrive via the event stream (store ahead of board).
  useEffect(() => {
    if (!activeMatch) return;
    const board = boardRef.current;
    if (!board) return;
    const boardMoves = board.getMoves().length;
    if (activeMatchMoves.length > boardMoves) {
      const next = activeMatchMoves[boardMoves];
      if (next) board.applyExternalMove(next.uci);
    }
  }, [activeMatchMoves, activeMatch]);

  const handlePositionChange = (_fen: string) => {
    if (!activeMatch || activeMatch.status !== 'playing') return;
    const board = boardRef.current;
    if (!board) return;
    const boardMoves = board.getMoves().length;
    const storeMoves = movesRef.current.length;
    if (boardMoves === storeMoves + 1) {
      // Local move just made — submit it. submittedRef guards against re-entry.
      if (submittedRef.current >= boardMoves) return;
      submittedRef.current = boardMoves;
      const lastMove = board.getMoves()[boardMoves - 1];
      // The store is updated from the match.move event alone (fired for both
      // the mover and the opponent — see usePlaySocket), not from this
      // response, so a local move isn't double-appended to activeMatchMoves.
      api
        .submitMove(activeMatch.id, lastMove.uci)
        .catch((e) => {
          submittedRef.current = 0;
          window.ScidbWorkspace?.toast?.(
            `Move rejected: ${e instanceof Error ? e.message : String(e)}`,
            'warning',
          );
        });
    }
  };

  if (!activeMatch) return null;
  const finished = activeMatch.status === 'finished';

  const resultText = (() => {
    if (!finished || !activeMatch.result) return null;
    const r = activeMatch.result;
    if (r.kind === 'mate') return `Checkmate — ${r.winner === 'w' ? 'White' : 'Black'} wins`;
    if (r.kind === 'resign') return `${r.winner === 'w' ? 'White' : 'Black'} wins by resignation`;
    if (r.kind === 'timeout') return `${r.winner === 'w' ? 'White' : 'Black'} wins on time`;
    if (r.kind === 'draw') return `Draw — ${r.reason}`;
    return 'Game finished';
  })();

  return (
    <div className="play-board-panel">
      <div className="play-board-side">
        <ChessBoard
          ref={boardRef}
          mode="play"
          myColor={myColor}
          startFen={activeMatch.startFen}
          onPositionChange={handlePositionChange}
        />
      </div>
      <div className="play-board-aside">
        <ClockWidget match={activeMatch} myColor={myColor} />
        <div className="play-opponent">
          {myColor === 'w' ? activeMatch.black.name : activeMatch.white.name} ({activeMatch.timeControl.kind})
        </div>
        {finished ? (
          <div className="play-result">{resultText}</div>
        ) : (
          <MatchControls match={activeMatch} />
        )}
      </div>
    </div>
  );
}