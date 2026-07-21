import { useEffect, useState, useCallback } from 'react';
import { createApiClient } from '@/api/client';
import type { PlayerSummary, PlayerCard, PrepReport, PlayerPrepRequest } from '@/types';

const api = createApiClient();

/**
 * PlayerCenter — React modal for searching players, viewing player cards,
 * and requesting opponent prep reports.
 *
 * Listens for the `scidb:open-player-center` custom event dispatched by
 * the database rail.
 */
export default function PlayerCenter() {
  const [isOpen, setIsOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [players, setPlayers] = useState<PlayerSummary[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [card, setCard] = useState<PlayerCard | null>(null);
  const [isLoadingCard, setIsLoadingCard] = useState(false);
  const [report, setReport] = useState<PrepReport | null>(null);
  const [isGenerating, setIsGenerating] = useState(false);
  const toast = window.ScidbWorkspace?.toast || console.log;

  const loadPlayers = useCallback(async (q?: string) => {
    setIsLoading(true);
    try {
      const data = await api.listPlayers(q);
      setPlayers(data);
    } catch (err) {
      toast(`Failed to load players: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    } finally {
      setIsLoading(false);
    }
  }, [toast]);

  useEffect(() => {
    const handleOpen = () => {
      setIsOpen(true);
      setCard(null);
      setReport(null);
      setSelectedId(null);
      loadPlayers();
    };
    window.addEventListener('scidb:open-player-center', handleOpen);
    return () => window.removeEventListener('scidb:open-player-center', handleOpen);
  }, [loadPlayers]);

  const handleSearch = () => {
    loadPlayers(query || undefined);
  };

  const handleSelectPlayer = async (playerId: string) => {
    setSelectedId(playerId);
    setCard(null);
    setReport(null);
    setIsLoadingCard(true);
    try {
      const data = await api.getPlayerCard(playerId);
      setCard(data);
    } catch (err) {
      toast(`Failed to load player card: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    } finally {
      setIsLoadingCard(false);
    }
  };

  const handleGeneratePrep = async () => {
    if (!selectedId) return;
    setIsGenerating(true);
    setReport(null);
    try {
      const payload: PlayerPrepRequest = { playerId: selectedId };
      const result = await api.createPlayerPrepReport(payload);
      setReport(result);
      toast(`Opponent prep report generated for ${result.subject}`, 'success');
    } catch (err) {
      toast(`Prep report failed: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    } finally {
      setIsGenerating(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div
      id="player-center-modal"
      className="modal"
      style={{ display: 'flex' }}
      onClick={(e) => { if (e.target === e.currentTarget) setIsOpen(false); }}
    >
      <div className="modal-content modal-large">
        <div className="modal-header">
          <div>
            <span className="eyebrow">PLAYERS</span>
            <h3>Player center</h3>
          </div>
          <button className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>
        <div className="modal-body" style={{ display: 'flex', gap: '20px' }}>
          {/* Left: search + player list */}
          <div style={{ flex: '0 0 280px' }}>
            <div className="database-toolbar" style={{ marginBottom: '8px' }}>
              <input
                type="search"
                placeholder="Search players…"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') handleSearch(); }}
              />
              <button className="ghost-btn" onClick={handleSearch}>Search</button>
            </div>
            <div style={{ overflowY: 'auto', maxHeight: '60vh' }}>
              {isLoading ? (
                <div className="database-empty">Loading players…</div>
              ) : players.length === 0 ? (
                <div className="database-empty">No players found.</div>
              ) : (
                players.map((p) => (
                  <button
                    key={p.id}
                    className={`database-row ${selectedId === p.id ? 'selected' : ''}`}
                    style={{ width: '100%', marginBottom: '4px' }}
                    onClick={() => handleSelectPlayer(p.id)}
                  >
                    <span className="database-icon">♟</span>
                    <span>
                      <strong>{p.name}</strong>
                      <small>{p.title || ''} {p.elo} · {p.country || ''} · {p.games} games</small>
                    </span>
                  </button>
                ))
              )}
            </div>
          </div>

          {/* Right: player card + prep report */}
          <div style={{ flex: 1, overflowY: 'auto' }}>
            {!selectedId ? (
              <div className="database-empty">Select a player to view their card.</div>
            ) : isLoadingCard ? (
              <div className="database-empty">Loading player card…</div>
            ) : !card ? (
              <div className="database-empty">No card data available.</div>
            ) : (
              <>
                <div className="report-section">
                  <div className="report-section-header">
                    <span className="section-icon">♟</span>
                    <h3>{card.name}</h3>
                  </div>
                  <div className="report-section-body">
                    <div className="report-summary-bar">
                      <div className="summary-stat">
                        <div className="stat-value">{card.elo}</div>
                        <div className="stat-label">Rating</div>
                      </div>
                      <div className="summary-stat">
                        <div className="stat-value">{card.peakElo}</div>
                        <div className="stat-label">Peak</div>
                      </div>
                      <div className="summary-stat">
                        <div className="stat-value">{card.title || '—'}</div>
                        <div className="stat-label">Title</div>
                      </div>
                      <div className="summary-stat">
                        <div className="stat-value">{card.country || '—'}</div>
                        <div className="stat-label">Country</div>
                      </div>
                      <div className="summary-stat">
                        <div className="stat-value">{card.games.toLocaleString()}</div>
                        <div className="stat-label">Games</div>
                      </div>
                    </div>
                    <div className="win-bar" style={{ marginTop: '12px' }}>
                      <div className="w-white" style={{ width: `${card.winRate}%` }}></div>
                      <div className="w-draw" style={{ width: `${card.drawRate}%` }}></div>
                      <div className="w-black" style={{ width: `${card.lossRate}%` }}></div>
                    </div>
                    <div className="win-bar-labels">
                      <span>Win: {card.winRate}%</span>
                      <span>Draw: {card.drawRate}%</span>
                      <span>Loss: {card.lossRate}%</span>
                    </div>

                    <h4 style={{ margin: '16px 0 8px', fontSize: '14px' }}>Top Openings</h4>
                    <table className="stats-table">
                      <thead>
                        <tr>
                          <th>ECO</th>
                          <th>Opening</th>
                          <th className="number">Games</th>
                          <th className="number">Score</th>
                        </tr>
                      </thead>
                      <tbody>
                        {card.topOpenings.map((o, i) => (
                          <tr key={i}>
                            <td><strong>{o.eco}</strong></td>
                            <td>{o.name}</td>
                            <td className="number">{o.games}</td>
                            <td className="number">{o.score}%</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>

                    <div style={{ marginTop: '16px' }}>
                      <button
                        className="primary-btn"
                        onClick={handleGeneratePrep}
                        disabled={isGenerating}
                      >
                        {isGenerating ? 'Generating…' : 'Generate opponent prep report'}
                      </button>
                    </div>
                  </div>
                </div>

                {report && (
                  <div className="report-section">
                    <div className="report-section-header">
                      <span className="section-icon">📋</span>
                      <h3>Opponent Prep — {report.subject}</h3>
                    </div>
                    <div className="report-section-body">
                      <p style={{ marginBottom: '12px', fontSize: '13px', color: 'var(--text-dim)' }}>
                        {report.summary}
                      </p>
                      <table className="stats-table">
                        <thead>
                          <tr>
                            <th>Move</th>
                            <th className="number">Games</th>
                            <th className="number">W Score</th>
                            <th className="number">B Score</th>
                            <th>Assessment</th>
                            <th>Note</th>
                          </tr>
                        </thead>
                        <tbody>
                          {report.lines.map((line, i) => (
                            <tr key={i}>
                              <td><strong>{line.san}</strong></td>
                              <td className="number">{line.games.toLocaleString()}</td>
                              <td className="number" style={{ color: 'var(--accent-green)' }}>{line.whiteScore}%</td>
                              <td className="number" style={{ color: 'var(--accent-red)' }}>{line.blackScore}%</td>
                              <td>
                                <span className={`badge ${line.performance === 'good' ? 'badge-green' : line.performance === 'solid' ? 'badge-blue' : line.performance === 'risky' ? 'badge-red' : line.performance === 'rare' ? 'badge-yellow' : 'badge-gray'}`}>
                                  {line.performance}
                                </span>
                              </td>
                              <td style={{ fontSize: '12px', color: 'var(--text-dim)' }}>{line.note}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}