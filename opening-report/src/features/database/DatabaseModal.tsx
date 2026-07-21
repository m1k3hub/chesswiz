import { useEffect, useState, useRef, useCallback } from 'react';
import { createApiClient } from '@/api/client';
import { useWorkspaceStore } from '@/state/workspace';
import type { Database, DatabaseFormat } from '@/types';
import ImportExportPanel from './ImportExportPanel';

const api = createApiClient();

export default function DatabaseModal() {
  const [isOpen, setIsOpen] = useState(false);
  const [databases, setDatabases] = useState<Database[]>([]);
  const [filter, setFilter] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [showImportExport, setShowImportExport] = useState(false);
  const [selectedDbForImport, setSelectedDbForImport] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const setActiveDatabaseId = useWorkspaceStore((s) => s.setActiveDatabaseId);
  const toast = window.ScidbWorkspace?.toast || console.log;

  const loadDatabases = useCallback(async () => {
    setIsLoading(true);
    try {
      const dbs = await api.listDatabases();
      setDatabases(dbs);
    } catch (err) {
      toast(`Failed to load databases: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    } finally {
      setIsLoading(false);
    }
  }, [toast]);

  useEffect(() => {
    const handleOpen = () => {
      setIsOpen(true);
      loadDatabases();
    };
    window.addEventListener('scidb:open-database-manager', handleOpen);
    return () => window.removeEventListener('scidb:open-database-manager', handleOpen);
  }, [loadDatabases]);

  useEffect(() => {
    if (isOpen) inputRef.current?.focus();
  }, [isOpen]);

  const handleSelect = (db: Database) => {
    setActiveDatabaseId(db.id);
    setIsOpen(false);
    toast(`Active database: ${db.name}`, 'accent');
  };

  const handleCreate = () => {
    const name = window.prompt('Database name:');
    if (!name) return;
    const format = (window.prompt('Format (SCI, PGN):', 'PGN') || 'PGN').toUpperCase() as DatabaseFormat;
    api.createDatabase({ name, format, games: 0, readOnly: false }).then((db) => {
      setDatabases((prev) => [...prev, db]);
      toast(`Created database ${db.name}`, 'success');
    }).catch((e) => {
      toast(`Failed to create database: ${e instanceof Error ? e.message : String(e)}`, 'error');
    });
  };

  const handleImportExport = (db: Database) => {
    setSelectedDbForImport(db.id);
    setShowImportExport(true);
  };

  const filtered = databases.filter((db) =>
    `${db.name} ${db.format}`.toLowerCase().includes(filter.toLowerCase())
  );

  if (showImportExport && selectedDbForImport) {
    return <ImportExportPanel databaseId={selectedDbForImport} onClose={() => setShowImportExport(false)} />;
  }

  if (!isOpen) return null;

  return (
    <div id="database-modal" className="modal" style={{ display: 'flex' }} onClick={(e) => {
      if (e.target === e.currentTarget) setIsOpen(false);
    }}>
      <div className="modal-content database-modal-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">LIBRARY</span>
            <h3>Database manager</h3>
          </div>
          <button id="database-modal-close" className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>
        <div className="database-toolbar">
          <input
            id="database-filter"
            ref={inputRef}
            type="search"
            placeholder="Filter databases…"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
          />
          <button className="primary-btn" id="database-create" onClick={handleCreate}>
            ＋ Create database
          </button>
        </div>
        <div id="database-list" className="database-list">
          {isLoading ? (
            <div className="database-empty">Loading databases…</div>
          ) : filtered.length === 0 ? (
            <div className="database-empty">No databases match.</div>
          ) : (
            filtered.map((db) => (
              <button
                key={db.id}
                className="database-row"
                data-database-id={db.id}
                onClick={() => handleSelect(db)}
              >
                <span className="database-icon">▦</span>
                <span>
                  <strong>{db.name}</strong>
                  <small>{db.format} · {Number(db.games).toLocaleString()} games{db.readOnly ? ' · read only' : ''}</small>
                </span>
                <span className="database-chevron" style={{ display: 'flex', gap: '4px' }}>
                <button
                  className="ghost-btn"
                  style={{ fontSize: '11px', padding: '2px 8px' }}
                  onClick={(e) => { e.stopPropagation(); handleImportExport(db); }}
                >
                  Import/Export
                </button>
                <span>›</span>
              </span>
              </button>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
