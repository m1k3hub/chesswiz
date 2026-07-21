/**
 * GameEditorModal — modal wrapper for the GameEditor component.
 *
 * Listens for the `scidb:open-game-editor` custom event with detail { gameId },
 * opens the modal, and renders GameEditor inside.
 */

import { useEffect, useState } from 'react';
import GameEditor from './GameEditor';

interface GameEditorEventDetail {
  gameId: string;
}

export default function GameEditorModal() {
  const [isOpen, setIsOpen] = useState(false);
  const [gameId, setGameId] = useState('');

  useEffect(() => {
    const handleOpen = (event: Event) => {
      const detail = (event as CustomEvent<GameEditorEventDetail>).detail;
      if (!detail?.gameId) return;
      setGameId(detail.gameId);
      setIsOpen(true);
    };
    window.addEventListener('scidb:open-game-editor', handleOpen);
    return () => window.removeEventListener('scidb:open-game-editor', handleOpen);
  }, []);

  if (!isOpen) return null;

  return (
    <div
      id="game-editor-modal"
      className="modal"
      style={{ display: 'flex' }}
      onClick={(e) => {
        if (e.target === e.currentTarget) setIsOpen(false);
      }}
    >
      <div className="modal-content modal-large">
        <div className="modal-header">
          <h3>Game Editor — {gameId}</h3>
          <button className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>
        <div className="modal-body">
          <GameEditor gameId={gameId} onClose={() => setIsOpen(false)} />
        </div>
      </div>
    </div>
  );
}