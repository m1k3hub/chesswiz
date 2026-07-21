import { useEffect, useState, useCallback } from 'react';
import { createApiClient } from '@/api/client';
import type { CrosstableResult, CrosstablePlayerRow } from '@/types';

const api = createApiClient();

/**
 * CrosstableModal — query and display tournament crosstables.
 *
 * Listens for `scidb:open-crosstable` custom events. Lets the user search
 * by event, site, or player names, then renders a sortable crosstable grid
 * with rank, points, W/D/L, and Sonneborn-Berger scores.
 */
export default function CrosstableModal() {
  const [isOpen, setIsOpen] = useState(false);
  const [event, setEvent] = useState('');
  const [site, setSite] = useState('');
  const [players, setPlayers] = useState('');
  const [result, setResult] = useState<CrosstableResult | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<'rank' | 'points' | 'sonnebornBerger'>('rank');
  const toast = window.ScidbWorkspace?.toast || console.log;

  useEffect(() => {
    const handleOpen = () => {
      setIsOpen(true);
      setResult(null);
      setError(null);
    };
    window.addEventListener('scidb:open-crosstable', handleOpen);
    return () => window.removeEventListener('scidb:open-crosstable', handleOpen);
  }, []);

  const runQuery = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const playerList = players
        .split(',')
        .map((p) => p.trim())
        .filter(Boolean);
      const r = await api.queryCrosstable({
        event: event || undefined,
        site: site || undefined,
        players: playerList.length > 0 ? playerList : undefined,
      });
      setResult(r);
      if (r.players.length === 0) {
        toast('No crosstable data found for the given query', 'accent');
      }
    } catch (e) {
      setError(`Query failed: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setIsLoading(false);
    }
  }, [event, site, players, toast]);

  const sortedPlayers: CrosstablePlayerRow[] = result
    ? [...result.players].sort((a, b) => {
        if (sortKey === 'rank') return a.rank - b.rank;
        if (sortKey === 'points') return b.points - a.points;
        return b.sonnebornBerger - a.sonnebornBerger;
      })
    : [];

  if (!isOpen) return null;

  return (
    <div id="crosstable-modal" className="modal" style={{ display: 'flex' }} onClick={(e) => {
      if (e.target === e.currentTarget) setIsOpen(false);
    }}>
      <div className="modal-content modal-large">
        <div className="modal-header">
          <div>
            <span className="eyebrow">TOURNAMENT</span>
            <h3>Crosstable</h3>
          </div>
          <button className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>

        <div className="modal-body">
          {/* Query form */}
          <div className="search-form-grid" style={{ marginBottom: 16 }}>
            <div className="control-group">
              <label>Event</label>
              <input
                type="text"
                placeholder="e.g. Tata Steel Masters"
                value={event}
                onChange={(e) => setEvent(e.target.value)}
                disabled={isLoading}
              />
            </div>
            <div className="control-group">
              <label>Site</label>
              <input
                type="text"
                placeholder="e.g. Wijk aan Zee"
                value={site}
                onChange={(e) => setSite(e.target.value)}
                disabled={isLoading}
              />
            </div>
            <div className="control-group full-width">
              <label>Players (comma-separated)</label>
              <input
                type="text"
                placeholder="e.g. Carlsen, Caruana, Nepomniachtchi"
                value={players}
                onChange={(e) => setPlayers(e.target.value)}
                disabled={isLoading}
              />
            </div>
          </div>

          <div className="search-actions">
            <span className="search-status">
              {isLoading ? 'Querying…' : result ? `${result.players.length} players` : 'Ready'}
            </span>
            <div className="search-actions-right">
              <button
                className="primary-btn"
                onClick={runQuery}
                disabled={isLoading}
              >
                {isLoading ? 'Loading…' : 'Query crosstable'}
              </button>
            </div>
          </div>

          {error && (
            <p style={{ color: 'var(--accent-red)', fontSize: 14, marginTop: 12 }}>{error}</p>
          )}

          {/* Crosstable grid */}
          {result && result.players.length > 0 && (
            <div style={{ marginTop: 16 }}>
              <div style={{ display: 'flex', gap: 12, marginBottom: 12, alignItems: 'center' }}>
                <div>
                  <strong>{result.event}</strong>
                  <small style={{ display: 'block', color: 'var(--text-dim)' }}>
                    {result.site} · {result.totalRounds} rounds
                  </small>
                </div>
              </div>

              <table className="stats-table">
                <thead>
                  <tr>
                    <th
                      className="number"
                      style={{ cursor: 'pointer' }}
                      onClick={() => setSortKey('rank')}
                    >
                      #
                    </th>
                    <th>Player</th>
                    <th className="number">Games</th>
                    <th
                      className="number"
                      style={{ cursor: 'pointer' }}
                      onClick={() => setSortKey('points')}
                    >
                      Pts
                    </th>
                    <th className="number">W</th>
                    <th className="number">D</th>
                    <th className="number">L</th>
                    <th
                      className="number"
                      style={{ cursor: 'pointer' }}
                      onClick={() => setSortKey('sonnebornBerger')}
                    >
                      SB
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {sortedPlayers.map((p) => (
                    <tr key={p.player}>
                      <td className="number">{p.rank}</td>
                      <td><strong>{p.player}</strong></td>
                      <td className="number">{p.games}</td>
                      <td className="number" style={{ color: 'var(--accent-green)' }}>
                        {p.points.toFixed(1)}
                      </td>
                      <td className="number">{p.wins}</td>
                      <td className="number">{p.draws}</td>
                      <td className="number">{p.losses}</td>
                      <td className="number">{p.sonnebornBerger.toFixed(1)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {result && result.players.length === 0 && !error && (
            <div className="database-empty" style={{ marginTop: 16 }}>
              No crosstable data found. Try adjusting your query.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}