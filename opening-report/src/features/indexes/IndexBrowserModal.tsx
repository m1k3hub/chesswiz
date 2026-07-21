import { useEffect, useState, useCallback, useRef } from 'react';
import { createApiClient } from '@/api/client';
import type { IndexType, NamebaseEntry, EcoEntry } from '@/types';

const api = createApiClient();

const TABS: { id: IndexType; label: string }[] = [
  { id: 'players', label: 'Players' },
  { id: 'events', label: 'Events' },
  { id: 'sites', label: 'Sites' },
  { id: 'annotators', label: 'Annotators' },
  { id: 'eco', label: 'ECO' },
];

type IndexRow = NamebaseEntry | EcoEntry;

function isEcoEntry(row: IndexRow): row is EcoEntry {
  return 'code' in row;
}

export default function IndexBrowserModal() {
  const [isOpen, setIsOpen] = useState(false);
  const [activeTab, setActiveTab] = useState<IndexType>('players');
  const [rows, setRows] = useState<IndexRow[]>([]);
  const [filtered, setFiltered] = useState<IndexRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [query, setQuery] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  const loadIndex = useCallback(async (type: IndexType) => {
    setIsLoading(true);
    try {
      const data = await api.getIndexes(type);
      setRows(data);
      setFiltered(data);
    } catch (err) {
      console.error('Failed to load index:', err);
      setRows([]);
      setFiltered([]);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    const handleOpen = () => {
      setIsOpen(true);
      setQuery('');
      loadIndex(activeTab);
    };
    window.addEventListener('scidb:open-index-browser', handleOpen);
    return () => window.removeEventListener('scidb:open-index-browser', handleOpen);
  }, [activeTab, loadIndex]);

  useEffect(() => {
    if (isOpen) inputRef.current?.focus();
  }, [isOpen]);

  useEffect(() => {
    const q = query.toLowerCase();
    setFiltered(
      q
        ? rows.filter((r) => {
            const name = isEcoEntry(r) ? `${r.code} ${r.name}` : r.name;
            return name.toLowerCase().includes(q);
          })
        : rows
    );
  }, [query, rows]);

  const handleTabSwitch = (tab: IndexType) => {
    setActiveTab(tab);
    setQuery('');
    loadIndex(tab);
  };

  if (!isOpen) return null;

  return (
    <div id="index-browser-modal" className="modal" style={{ display: 'flex' }} onClick={(e) => {
      if (e.target === e.currentTarget) setIsOpen(false);
    }}>
      <div className="modal-content search-center-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">INDEX BROWSER</span>
            <h3>Namebases &amp; ECO table</h3>
          </div>
          <button id="index-browser-close" className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>
        <div className="search-center-body">
          <div className="search-tabs">
            {TABS.map((tab) => (
              <button
                key={tab.id}
                className={`search-tab ${activeTab === tab.id ? 'active' : ''}`}
                onClick={() => handleTabSwitch(tab.id)}
              >
                {tab.label}
              </button>
            ))}
          </div>
          <div className="database-toolbar" style={{ marginTop: '12px' }}>
            <input
              ref={inputRef}
              type="search"
              placeholder={activeTab === 'eco' ? 'Search ECO code or name…' : 'Filter names…'}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </div>
          <div className="search-results-list" style={{ marginTop: '12px', maxHeight: '400px', overflowY: 'auto' }}>
            {isLoading ? (
              <div className="database-empty">Loading…</div>
            ) : filtered.length === 0 ? (
              <div className="database-empty">No entries match.</div>
            ) : activeTab === 'eco' ? (
              filtered.map((row) => {
                const eco = row as EcoEntry;
                return (
                  <div key={eco.code} className="game-row" style={{ cursor: 'default' }}>
                    <span className="game-players">
                      <strong>{eco.code}</strong>
                    </span>
                    <span className="game-event">{eco.name}</span>
                    <span className="game-eco">{eco.games}<small>games</small></span>
                  </div>
                );
              })
            ) : (
              filtered.map((row) => {
                const entry = row as NamebaseEntry;
                return (
                  <div key={entry.id} className="game-row" style={{ cursor: 'default' }}>
                    <span className="game-players">
                      <strong>{entry.name}</strong>
                    </span>
                    <span className="game-event"><small>{entry.games} games</small></span>
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>
    </div>
  );
}