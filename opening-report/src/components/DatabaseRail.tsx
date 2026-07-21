import { useEffect, useState } from 'react';
import { useWorkspaceStore } from '@/state/workspace';
import { createApiClient } from '@/api/client';
import type { Database } from '@/types';

const api = createApiClient();

export default function DatabaseRail() {
  const [databases, setDatabases] = useState<Database[]>([]);
  const activeDatabaseId = useWorkspaceStore((s) => s.activeDatabaseId);
  const setActivePanel = useWorkspaceStore((s) => s.setActivePanel);
  const toast = window.ScidbWorkspace?.toast || console.log;

  useEffect(() => {
    let cancelled = false;
    api.listDatabases().then((dbs) => {
      if (!cancelled) setDatabases(dbs);
    }).catch(() => { /* API unavailable; keep empty database list */ });
    return () => { cancelled = true; };
  }, []);

  const handleDatabaseClick = () => {
    setActivePanel('database-manager');
    window.dispatchEvent(new CustomEvent('scidb:open-database-manager'));
  };

  const activeDb = databases.find((db) => db.id === activeDatabaseId);

  return (
    <aside className="side-rail">
      <div className="rail-label">LIBRARY</div>
      <button
        className={`rail-item ${activeDb ? 'selected' : ''}`}
        onClick={handleDatabaseClick}
        title={activeDb ? `${activeDb.name} (${activeDb.format})` : undefined}
      >
        <span>▦</span> My databases <b>{databases.length}</b>
      </button>
      <button className="rail-item" onClick={() => window.dispatchEvent(new CustomEvent('scidb:open-game-switcher'))}>
        <span>⌕</span> Search games
      </button>
      <button className="rail-item" onClick={() => window.dispatchEvent(new CustomEvent('scidb:open-search-center'))}>
        <span>⚲</span> Search center
      </button>
      <button className="rail-item" onClick={() => window.dispatchEvent(new CustomEvent('scidb:open-opening-tree'))}>
        <span>◒</span> Opening explorer
      </button>
      <button className="rail-item" onClick={() => toast('Reports module selected')}>
        <span>▣</span> Reports
      </button>
      <button className="rail-item" onClick={() => window.dispatchEvent(new CustomEvent('scidb:open-job-center'))}>
        <span>≡</span> Job center
      </button>
      <button className="rail-item" onClick={() => window.dispatchEvent(new CustomEvent('scidb:open-working-sets'))}>
        <span>▤</span> Working sets
      </button>
      <button className="rail-item" onClick={() => window.dispatchEvent(new CustomEvent('scidb:open-maintenance'))}>
        <span>⚙</span> Maintenance
      </button>
      <button className="rail-item" onClick={() => window.dispatchEvent(new CustomEvent('scidb:open-crosstable'))}>
        <span>⊞</span> Crosstable
      </button>
      <button className="rail-item" onClick={() => window.dispatchEvent(new CustomEvent('scidb:open-index-browser'))}>
        <span>ℹ</span> Index browser
      </button>
      <button className="rail-item" onClick={() => window.dispatchEvent(new CustomEvent('scidb:open-repertoire-studio'))}>
        <span>♫</span> Repertoire
      </button>
      <button className="rail-item" onClick={() => window.dispatchEvent(new CustomEvent('scidb:open-player-center'))}>
        <span>♟</span> Player center
      </button>

      <div className="rail-divider"></div>
      <div className="rail-label">COLLECTIONS</div>
      <button className="rail-item">
        <span className="dot blue"></span> World Championship
      </button>
      <button className="rail-item">
        <span className="dot gold"></span> My repertoire
      </button>
      <button className="rail-item">
        <span className="dot green"></span> Training positions
      </button>

      <div className="rail-bottom">
        <button className="rail-item" onClick={() => toast('Settings module selected')}>
          <span>⚙</span> Settings
        </button>
        <small>scidb-beta 1.0 · ready</small>
      </div>
    </aside>
  );
}
