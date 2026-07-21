/**
 * GameEditor — React component for viewing and editing a game.
 *
 * Listens for the `scidb:open-game-editor` custom event with detail { gameId },
 * loads the game via the API client, renders a read-only board synced to the
 * main line, editable PGN headers, a clickable move list, and buttons to add
 * variations and comments.
 */

import { useEffect, useState, useCallback } from 'react';
import { createApiClient } from '@/api/client';
import type { GameDetail, GameHeaders, EditorMove } from '@/types';
import { fenAtPly } from './game-helpers';
import { sanitizeHtml } from '@/lib/validation';
import MiniBoard from '@/features/board/MiniBoard';

const api = createApiClient();

export default function GameEditor({ gameId, onClose: _onClose }: { gameId: string; onClose: () => void }) {
  const [game, setGame] = useState<GameDetail | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [currentPly, setCurrentPly] = useState(0);
  const [headers, setHeaders] = useState<GameHeaders>({});
  const [commentText, setCommentText] = useState('');
  const [showCommentEditor, setShowCommentEditor] = useState(false);
  const [currentFen, setCurrentFen] = useState('start');
  const toast = window.ScidbWorkspace?.toast || console.log;

  const loadGame = useCallback(
    async (id: string) => {
      setIsLoading(true);
      setError(null);
      try {
        const detail = await api.getGame(id);
        setGame(detail);
        setHeaders({ ...detail.headers });
        setCurrentPly(0);
      } catch (err) {
        setError(err instanceof Error ? err.message : String(err));
      } finally {
        setIsLoading(false);
      }
    },
    [],
  );

  // The GameEditorModal passes gameId via prop; this component is also
  // self-contained — the modal wrapper handles the event listener.
  useEffect(() => {
    if (gameId) {
      void loadGame(gameId);
    }
  }, [gameId, loadGame]);

  useEffect(() => {
    if (game) {
      const fen = fenAtPly(game.moves, currentPly);
      setCurrentFen(fen);
    }
  }, [game, currentPly]);

  const goToPly = useCallback(
    (ply: number) => {
      const clamped = Math.max(0, Math.min(ply, game?.moves.length ?? 0));
      setCurrentPly(clamped);
    },
    [game],
  );

  const handleHeaderChange = (key: string, value: string) => {
    // Sanitise header values to prevent stored-XSS in rendered game metadata.
    setHeaders((prev) => ({ ...prev, [key]: sanitizeHtml(value) }));
  };

  const handleSaveHeaders = async () => {
    if (!game) return;
    try {
      const updated = await api.updateGame(game.id, { headers });
      setGame(updated);
      setHeaders({ ...updated.headers });
      toast('Headers saved', 'success');
    } catch (err) {
      toast(`Save failed: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    }
  };

  const handleAddVariation = async () => {
    if (!game || currentPly === 0) {
      toast('Navigate to a move before adding a variation', 'accent');
      return;
    }
    const parentMove = game.moves[currentPly - 1];
    if (!parentMove) return;
    try {
      const updated = await api.addVariation(game.id, {
        parentMoveId: parentMove.id,
        moves: [],
      });
      setGame(updated);
      toast('Variation added', 'success');
    } catch (err) {
      toast(`Add variation failed: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    }
  };

  const handleSaveComment = async () => {
    if (!game || currentPly === 0) {
      toast('Navigate to a move before commenting', 'accent');
      return;
    }
    const move = game.moves[currentPly - 1];
    if (!move) return;
    // Sanitise comment text to prevent stored-XSS when rendered as HTML.
    const sanitized = sanitizeHtml(commentText);
    try {
      const updated = await api.setMoveComment(game.id, move.id, {
        comment: { text: sanitized },
      });
      setGame(updated);
      setShowCommentEditor(false);
      setCommentText('');
      toast('Comment saved', 'success');
    } catch (err) {
      toast(`Comment save failed: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    }
  };

  const openCommentEditor = () => {
    const move = game?.moves[currentPly - 1];
    setCommentText(move?.comment?.text || '');
    setShowCommentEditor(true);
  };

  if (isLoading) {
    return <div className="database-empty">Loading game…</div>;
  }

  if (error) {
    return (
      <div className="database-empty">
        Failed to load game: {error}
      </div>
    );
  }

  if (!game) {
    return <div className="database-empty">No game loaded.</div>;
  }

  const editableFields: { key: string; label: string }[] = [
    { key: 'Event', label: 'Event' },
    { key: 'Site', label: 'Site' },
    { key: 'Date', label: 'Date' },
    { key: 'Round', label: 'Round' },
    { key: 'White', label: 'White' },
    { key: 'Black', label: 'Black' },
    { key: 'Result', label: 'Result' },
    { key: 'ECO', label: 'ECO' },
  ];

  return (
    <div className="game-editor">
      {/* Board + navigation */}
      <div className="game-editor-board-section">
        <div className="game-editor-board">
          <MiniBoard fen={currentFen} />
        </div>
        <div className="game-editor-controls">
          <button className="ctrl-btn" onClick={() => goToPly(0)} title="Start">⏮</button>
          <button className="ctrl-btn" onClick={() => goToPly(currentPly - 1)} title="Previous">◀</button>
          <button className="ctrl-btn" onClick={() => goToPly(currentPly + 1)} title="Next">▶</button>
          <button className="ctrl-btn" onClick={() => goToPly(game.moves.length)} title="End">⏭</button>
        </div>
      </div>

      {/* Move list */}
      <div className="game-editor-moves">
        <div className="game-editor-section-header">
          <h4>Moves</h4>
          <span className="game-editor-ply">
            {currentPly} / {game.moves.length}
          </span>
        </div>
        <div className="game-editor-move-list">
          {game.moves.length === 0 ? (
            <span style={{ color: 'var(--text-dim)', fontSize: 12 }}>
              No moves in this game.
            </span>
          ) : (
            game.moves.map((move: EditorMove, i: number) => (
              <span
                key={move.id}
                className={`move-cell ${i === currentPly - 1 ? 'active' : ''}`}
                onClick={() => goToPly(i + 1)}
                style={{ cursor: 'pointer' }}
              >
                {move.color === 'w' && (
                  <span className="move-num">{Math.floor(i / 2) + 1}.</span>
                )}{' '}
                <span className="move-text">{move.san}</span>
                {move.comment && (
                  <span className="move-comment-indicator" title={move.comment.text}> 💬</span>
                )}
                {move.variations.length > 0 && (
                  <span className="move-variation-indicator" title={`${move.variations.length} variation(s)`}> ⇄</span>
                )}
              </span>
            ))
          )}
        </div>
        <div className="game-editor-actions">
          <button className="ghost-btn" onClick={handleAddVariation} disabled={currentPly === 0}>
            ＋ Add variation
          </button>
          <button className="ghost-btn" onClick={openCommentEditor} disabled={currentPly === 0}>
            💬 {game.moves[currentPly - 1]?.comment ? 'Edit' : 'Add'} comment
          </button>
        </div>
        {showCommentEditor && (
          <div className="game-editor-comment-box">
            <textarea
              value={commentText}
              onChange={(e) => setCommentText(e.target.value)}
              placeholder="Enter comment…"
              rows={3}
            />
            <div className="game-editor-comment-actions">
              <button className="small-btn" onClick={handleSaveComment}>Save</button>
              <button
                className="ghost-btn"
                onClick={() => {
                  setShowCommentEditor(false);
                  setCommentText('');
                }}
              >
                Cancel
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Headers form */}
      <div className="game-editor-headers">
        <div className="game-editor-section-header">
          <h4>Headers</h4>
          <button className="small-btn" onClick={handleSaveHeaders}>Save</button>
        </div>
        <div className="search-form-grid">
          {editableFields.map(({ key, label }) => (
            <div className="control-group" key={key}>
              <label>{label}</label>
              <input
                type="text"
                value={headers[key] ?? ''}
                onChange={(e) => handleHeaderChange(String(key), e.target.value)}
                placeholder={label}
              />
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}