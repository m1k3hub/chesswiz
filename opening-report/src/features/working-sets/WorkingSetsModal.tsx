import { useEffect, useState, useRef } from 'react';
import { useWorkspaceStore } from '@/state/workspace';

/**
 * WorkingSetsModal — manage saved working sets.
 *
 * Lists saved working sets with rename, delete, and load actions.
 * "Load" replaces the current workingSet and opens the game switcher.
 * "Promote" also opens the game switcher.
 */
export default function WorkingSetsModal() {
  const [isOpen, setIsOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');
  const editInputRef = useRef<HTMLInputElement>(null);

  const savedWorkingSets = useWorkspaceStore((s) => s.savedWorkingSets);
  const removeWorkingSet = useWorkspaceStore((s) => s.removeWorkingSet);
  const renameWorkingSet = useWorkspaceStore((s) => s.renameWorkingSet);
  const loadWorkingSet = useWorkspaceStore((s) => s.loadWorkingSet);
  const toast = window.ScidbWorkspace?.toast || console.log;

  useEffect(() => {
    const handleOpen = () => setIsOpen(true);
    window.addEventListener('scidb:open-working-sets', handleOpen);
    return () => window.removeEventListener('scidb:open-working-sets', handleOpen);
  }, []);

  useEffect(() => {
    if (editingId) {
      setTimeout(() => editInputRef.current?.select(), 0);
    }
  }, [editingId]);

  const handleLoad = (id: string, name: string) => {
    loadWorkingSet(id);
    setIsOpen(false);
    window.dispatchEvent(new CustomEvent('scidb:open-game-switcher'));
    toast(`Loaded working set "${name}"`, 'accent');
  };

  const handlePromote = (id: string, name: string) => {
    loadWorkingSet(id);
    setIsOpen(false);
    window.dispatchEvent(new CustomEvent('scidb:open-game-switcher'));
    toast(`Promoted working set "${name}" to switcher`, 'accent');
  };

  const handleDelete = (id: string, name: string) => {
    removeWorkingSet(id);
    toast(`Deleted working set "${name}"`, 'warning');
  };

  const handleRenameStart = (id: string, name: string) => {
    setEditingId(id);
    setEditName(name);
  };

  const handleRenameCommit = () => {
    if (editingId) {
      const trimmed = editName.trim();
      if (trimmed) {
        renameWorkingSet(editingId, trimmed);
        toast('Renamed working set', 'success');
      }
    }
    setEditingId(null);
    setEditName('');
  };

  const handleRenameKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleRenameCommit();
    } else if (e.key === 'Escape') {
      setEditingId(null);
      setEditName('');
    }
  };

  if (!isOpen) return null;

  return (
    <div
      id="working-sets-modal"
      className="modal"
      style={{ display: 'flex' }}
      onClick={(e) => {
        if (e.target === e.currentTarget) setIsOpen(false);
      }}
    >
      <div className="modal-content database-modal-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">COLLECTIONS</span>
            <h3>Working sets</h3>
          </div>
          <button id="working-sets-close" className="modal-close" onClick={() => setIsOpen(false)}>
            ✕
          </button>
        </div>
        <div className="database-list">
          {savedWorkingSets.length === 0 ? (
            <div className="database-empty">
              No saved working sets. Run a search and save the results to create one.
            </div>
          ) : (
            savedWorkingSets.map((ws) => (
              <div key={ws.id} className="database-row working-set-row">
                <span className="database-icon">⌕</span>
                <span className="working-set-info">
                  {editingId === ws.id ? (
                    <input
                      ref={editInputRef}
                      type="text"
                      className="working-set-rename-input"
                      value={editName}
                      onChange={(e) => setEditName(e.target.value)}
                      onBlur={handleRenameCommit}
                      onKeyDown={handleRenameKeyDown}
                    />
                  ) : (
                    <strong onClick={() => handleRenameStart(ws.id, ws.name)} title="Click to rename">
                      {ws.name}
                    </strong>
                  )}
                  <small>{ws.games.length} games</small>
                </span>
                <span className="working-set-actions">
                  <button className="ghost-btn" onClick={() => handleLoad(ws.id, ws.name)}>
                    Load
                  </button>
                  <button className="ghost-btn" onClick={() => handlePromote(ws.id, ws.name)}>
                    Promote
                  </button>
                  <button className="ghost-btn" onClick={() => handleRenameStart(ws.id, ws.name)}>
                    Rename
                  </button>
                  <button className="ghost-btn" onClick={() => handleDelete(ws.id, ws.name)}>
                    Delete
                  </button>
                </span>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}