import { useEffect, useState, useCallback } from 'react';
import { createApiClient } from '@/api/client';
import type { Repertoire, PrepReport, OpeningPrepRequest } from '@/types';

const api = createApiClient();

/**
 * RepertoireStudio — React modal for browsing repertoires and requesting
 * opening prep reports.
 *
 * Listens for the `scidb:open-repertoire-studio` custom event dispatched by
 * the database rail.
 */
export default function RepertoireStudio() {
  const [isOpen, setIsOpen] = useState(false);
  const [repertoires, setRepertoires] = useState<Repertoire[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [report, setReport] = useState<PrepReport | null>(null);
  const [isGenerating, setIsGenerating] = useState(false);
  const toast = window.ScidbWorkspace?.toast || console.log;

  const loadRepertoires = useCallback(async () => {
    setIsLoading(true);
    try {
      const reps = await api.listRepertoires();
      setRepertoires(reps);
      if (reps.length > 0 && !selectedId) setSelectedId(reps[0].id);
    } catch (err) {
      toast(`Failed to load repertoires: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    } finally {
      setIsLoading(false);
    }
  }, [selectedId, toast]);

  useEffect(() => {
    const handleOpen = () => {
      setIsOpen(true);
      setReport(null);
      loadRepertoires();
    };
    window.addEventListener('scidb:open-repertoire-studio', handleOpen);
    return () => window.removeEventListener('scidb:open-repertoire-studio', handleOpen);
  }, [loadRepertoires]);

  const selectedRep = repertoires.find((r) => r.id === selectedId);

  const handleGenerateReport = async () => {
    if (!selectedId) return;
    setIsGenerating(true);
    setReport(null);
    try {
      const payload: OpeningPrepRequest = { repertoireId: selectedId };
      const result = await api.createOpeningPrepReport(payload);
      setReport(result);
      toast(`Opening prep report generated for ${result.subject}`, 'success');
    } catch (err) {
      toast(`Prep report failed: ${err instanceof Error ? err.message : String(err)}`, 'warning');
    } finally {
      setIsGenerating(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div
      id="repertoire-studio-modal"
      className="modal"
      style={{ display: 'flex' }}
      onClick={(e) => { if (e.target === e.currentTarget) setIsOpen(false); }}
    >
      <div className="modal-content modal-large">
        <div className="modal-header">
          <div>
            <span className="eyebrow">PREPARATION</span>
            <h3>Repertoire studio</h3>
          </div>
          <button className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>
        <div className="modal-body" style={{ display: 'flex', gap: '20px' }}>
          {/* Left: repertoire list */}
          <div style={{ flex: '0 0 260px', overflowY: 'auto' }}>
            {isLoading ? (
              <div className="database-empty">Loading repertoires…</div>
            ) : repertoires.length === 0 ? (
              <div className="database-empty">No repertoires found.</div>
            ) : (
              repertoires.map((rep) => (
                <button
                  key={rep.id}
                  className={`database-row ${selectedId === rep.id ? 'selected' : ''}`}
                  style={{ width: '100%', marginBottom: '4px' }}
                  onClick={() => { setSelectedId(rep.id); setReport(null); }}
                >
                  <span className="database-icon">♫</span>
                  <span>
                    <strong>{rep.name}</strong>
                    <small>{rep.side === 'white' ? 'White' : 'Black'} · ECO {rep.eco} · {rep.moves.length} moves</small>
                  </span>
                </button>
              ))
            )}
          </div>

          {/* Right: detail + report */}
          <div style={{ flex: 1, overflowY: 'auto' }}>
            {!selectedRep ? (
              <div className="database-empty">Select a repertoire to view its moves.</div>
            ) : (
              <>
                <div className="report-section">
                  <div className="report-section-header">
                    <span className="section-icon">♫</span>
                    <h3>{selectedRep.name}</h3>
                  </div>
                  <div className="report-section-body">
                    <p style={{ marginBottom: '12px', fontSize: '13px', color: 'var(--text-dim)' }}>
                      Side: <strong>{selectedRep.side === 'white' ? 'White' : 'Black'}</strong> ·
                      ECO: <strong>{selectedRep.eco}</strong> ·
                      Updated: {new Date(selectedRep.updatedAt).toLocaleDateString()}
                    </p>
                    <div className="move-list" style={{ display: 'flex', flexWrap: 'wrap', gap: '4px' }}>
                      {selectedRep.moves.map((m, i) => (
                        <span key={i} className="move-cell">
                          {i % 2 === 0 && <span className="move-num">{Math.floor(i / 2) + 1}.</span>}
                          <span className="move-text">{m.san}</span>
                          {m.comment && <small style={{ color: 'var(--text-dim)', marginLeft: '4px' }}>{m.comment}</small>}
                        </span>
                      ))}
                    </div>
                    <div style={{ marginTop: '16px' }}>
                      <button
                        className="primary-btn"
                        onClick={handleGenerateReport}
                        disabled={isGenerating}
                      >
                        {isGenerating ? 'Generating…' : 'Generate opening prep report'}
                      </button>
                    </div>
                  </div>
                </div>

                {report && (
                  <div className="report-section">
                    <div className="report-section-header">
                      <span className="section-icon">📋</span>
                      <h3>Prep Report — {report.subject}</h3>
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