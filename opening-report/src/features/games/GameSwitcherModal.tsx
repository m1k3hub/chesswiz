import { useEffect, useState, useRef, useCallback } from 'react';
import { createApiClient } from '@/api/client';
import { useWorkspaceStore } from '@/state/workspace';
import type { GameSummary, PaginatedGames, GameSortField, SortOrder } from '@/types';

const api = createApiClient();

const SORT_COLUMNS: { field: GameSortField; label: string }[] = [
  { field: 'white', label: 'White' },
  { field: 'black', label: 'Black' },
  { field: 'event', label: 'Event' },
  { field: 'date', label: 'Date' },
  { field: 'eco', label: 'ECO' },
  { field: 'result', label: 'Result' },
];

const PAGE_SIZES = [10, 20, 50, 100];

export default function GameSwitcherModal() {
  const [isOpen, setIsOpen] = useState(false);
  const [page, setPage] = useState(1);
  const [limit, setLimit] = useState(20);
  const [sort, setSort] = useState<GameSortField | null>(null);
  const [order, setOrder] = useState<SortOrder>('asc');
  const [query, setQuery] = useState('');
  const [data, setData] = useState<PaginatedGames | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const activeDatabaseId = useWorkspaceStore((s) => s.activeDatabaseId);
  const toast = window.ScidbWorkspace?.toast || console.log;
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const loadGames = useCallback(async () => {
    setIsLoading(true);
    try {
      const result = await api.listGamesPaginated({
        databaseId: activeDatabaseId,
        page,
        limit,
        sort: sort || undefined,
        order: sort ? order : undefined,
        query: query || undefined,
      });
      setData(result);
    } catch (err) {
      toast(`Failed to load games: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    } finally {
      setIsLoading(false);
    }
  }, [activeDatabaseId, page, limit, sort, order, query, toast]);

  useEffect(() => {
    const handleOpen = () => {
      setIsOpen(true);
      setPage(1);
      setQuery('');
    };
    window.addEventListener('scidb:open-game-switcher', handleOpen);
    return () => window.removeEventListener('scidb:open-game-switcher', handleOpen);
  }, []);

  useEffect(() => {
    if (isOpen) {
      inputRef.current?.focus();
      loadGames();
    }
  }, [isOpen]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!isOpen) return;
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      setPage(1);
      loadGames();
    }, 300);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [query]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!isOpen) return;
    loadGames();
  }, [page, limit, sort, order]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleSort = (field: GameSortField) => {
    if (sort === field) {
      setOrder((o) => (o === 'asc' ? 'desc' : 'asc'));
    } else {
      setSort(field);
      setOrder('asc');
    }
    setPage(1);
  };

  const handleSelect = (game: GameSummary) => {
    window.ScidbWorkspace?.setState({ activeGameId: game.id });
    setIsOpen(false);
    window.dispatchEvent(new CustomEvent('scidb:open-game-editor', { detail: { gameId: game.id } }));
  };

  if (!isOpen) return null;

  const games = data?.games ?? [];
  const total = data?.total ?? 0;
  const totalPages = data?.totalPages ?? 1;

  return (
    <div id="game-switcher-modal" className="modal" style={{ display: 'flex' }} onClick={(e) => {
      if (e.target === e.currentTarget) setIsOpen(false);
    }}>
      <div className="modal-content game-switcher-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">MASTER GAMES</span>
            <h3>Game switcher</h3>
          </div>
          <button id="game-switcher-close" className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>
        <div className="database-toolbar">
          <input
            id="game-search"
            ref={inputRef}
            type="search"
            placeholder="Search players, events, ECO…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <button className="ghost-btn" onClick={() => {
            setIsOpen(false);
            window.dispatchEvent(new CustomEvent('scidb:open-search-center'));
          }}>Advanced filters</button>
        </div>

        <div className="game-table-head">
          {SORT_COLUMNS.map((col) => (
            <span
              key={col.field}
              style={{ cursor: 'pointer', userSelect: 'none' }}
              onClick={() => handleSort(col.field)}
            >
              {col.label}
              {sort === col.field ? (order === 'asc' ? ' ▲' : ' ▼') : ''}
            </span>
          ))}
        </div>
        <div id="game-switcher-list" className="game-switcher-list">
          {isLoading ? (
            <div className="database-empty">Loading games…</div>
          ) : games.length === 0 ? (
            <div className="database-empty">No games match this search.</div>
          ) : (
            games.map((game) => (
              <button
                key={game.id}
                className="game-row"
                data-game-id={game.id}
                onClick={() => handleSelect(game)}
              >
                <span className="game-players">
                  <strong>{game.white}</strong>
                  <em>vs</em>
                  <strong>{game.black}</strong>
                </span>
                <span className="game-event">{game.event}<small>{game.date}</small></span>
                <span className="game-eco">{game.eco}<small>{game.result}</small></span>
              </button>
            ))
          )}
        </div>

        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 0', borderTop: '1px solid var(--border)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <button
              className="ctrl-btn"
              disabled={page <= 1}
              onClick={() => setPage((p) => Math.max(1, p - 1))}
            >◀</button>
            <span style={{ fontSize: '13px', color: 'var(--text-dim)' }}>
              Page {page} of {totalPages} ({total} games)
            </span>
            <button
              className="ctrl-btn"
              disabled={page >= totalPages}
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
            >▶</button>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            <label style={{ fontSize: '12px', color: 'var(--text-dim)' }}>Per page:</label>
            <select
              value={limit}
              onChange={(e) => { setLimit(Number(e.target.value)); setPage(1); }}
              style={{ fontSize: '12px' }}
            >
              {PAGE_SIZES.map((size) => (
                <option key={size} value={size}>{size}</option>
              ))}
            </select>
          </div>
        </div>
      </div>
    </div>
  );
}