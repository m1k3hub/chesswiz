/**
 * OpeningReport — React component that fetches and renders the full opening report.
 *
 * Listens for `scidb:generate-report` custom events dispatched by the BoardPanel
 * Generate button. Receives moves and FEN from the event detail (provided by
 * the ChessBoard ref), calls the typed ReportEngine, and renders all 12 report
 * sections as React components.
 */

import { useEffect, useRef, useState, useCallback } from 'react';
import { Chart, registerables } from 'chart.js';
import { ReportEngine } from './ReportEngine';
import type { ReportProgress } from './ReportEngine';
import type { ReportData, MoveEntry } from '@/types';
import type { GenerateReportDetail } from '@/components/BoardPanel';
import {
  formatWDL,
  getPieceSymbol,
  parsePGNHeaders,
  calculateFashionIndex,
  getFashionLabel,
} from './chess-helpers';

Chart.register(...registerables);

type Status = 'idle' | 'loading' | 'complete' | 'error';

const engine = new ReportEngine();

export default function OpeningReport() {
  const [status, setStatus] = useState<Status>('idle');
  const [data, setData] = useState<ReportData | null>(null);
  const [error, setError] = useState<string>('');
  const [progress, setProgress] = useState<ReportProgress | null>(null);
  const chartRef = useRef<Chart | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  const handleGenerate = useCallback(async (detail: GenerateReportDetail) => {
    const moves: MoveEntry[] = detail.moves.map((m) => ({ san: m.san, uci: m.uci }));
    const fen = detail.fen;
    if (moves.length === 0) {
      setStatus('error');
      setError('Please make at least one move on the board before generating a report.');
      return;
    }

    setStatus('loading');
    setError('');
    setProgress({ step: 'start', message: 'Generating Opening Report…' });

    // Hide the placeholder
    const placeholder = document.getElementById('report-placeholder');
    if (placeholder) placeholder.style.display = 'none';

    try {
      const result = await engine.generate(moves, fen, {
        source: detail.source,
        speed: detail.speed,
        ratingRange: detail.ratingRange,
      }, (p) => setProgress(p));
      setData(result);
      setStatus('complete');
    } catch (err) {
      setStatus('error');
      setError(err instanceof Error ? err.message : String(err));
    }
  }, []);

  useEffect(() => {
    const handler = (e: Event) => {
      const detail = (e as CustomEvent<GenerateReportDetail>).detail;
      if (detail) handleGenerate(detail);
    };
    window.addEventListener('scidb:generate-report', handler);
    return () => window.removeEventListener('scidb:generate-report', handler);
  }, [handleGenerate]);

  // Render fashion chart when data changes
  useEffect(() => {
    if (status !== 'complete' || !data) return;
    const canvas = canvasRef.current;
    if (!canvas) return;

    const yearly = data.historicalData.yearlyData;
    if (yearly.length === 0) return;

    if (chartRef.current) chartRef.current.destroy();

    const isDark = document.body.getAttribute('data-theme') !== 'light';
    const textColor = isDark ? '#8892b0' : '#6c757d';
    const gridColor = isDark ? '#233' : '#dee2e6';

    chartRef.current = new Chart(canvas, {
      type: 'bar',
      data: {
        labels: yearly.map((y) => String(y.year)),
        datasets: [{
          label: 'Top Games by Year',
          data: yearly.map((y) => y.count),
          backgroundColor: 'rgba(78, 168, 222, 0.6)',
          borderColor: 'rgba(78, 168, 222, 1)',
          borderWidth: 1,
        }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              title: (items) => `Year ${items[0]?.label ?? ''}`,
              label: (item) => `${item.parsed.y} top games`,
            },
          },
        },
        scales: {
          x: { ticks: { color: textColor, font: { size: 11 } }, grid: { color: gridColor } },
          y: { ticks: { color: textColor, font: { size: 11 } }, grid: { color: gridColor }, beginAtZero: true },
        },
      },
    });

    return () => {
      if (chartRef.current) {
        chartRef.current.destroy();
        chartRef.current = null;
      }
    };
  }, [status, data]);

  if (status === 'idle') return null;

  if (status === 'loading') {
    return (
      <div className="loading-overlay" style={{ display: 'flex', position: 'relative', minHeight: '200px', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', gap: '12px' }}>
        <div className="spinner"></div>
        <div className="loading-text">Generating Opening Report…</div>
        <div className="loading-subtext">{progress?.message ?? ''}</div>
      </div>
    );
  }

  if (status === 'error') {
    return (
      <div className="report-section">
        <div className="report-section-header">
          <span className="section-icon">❌</span>
          <h3>Error Generating Report</h3>
        </div>
        <div className="report-section-body">
          <p style={{ color: 'var(--accent-red)', fontSize: '14px' }}>{error}</p>
          <p style={{ marginTop: '10px', color: 'var(--text-dim)', fontSize: '13px' }}>
            Make sure you have a valid position on the board and try again.
            If using Lichess data, check your internet connection.
          </p>
        </div>
      </div>
    );
  }

  if (!data) return null;

  const totalGames = data.mainData.white + data.mainData.draws + data.mainData.black;
  const wdl = formatWDL(data.mainData.white, data.mainData.draws, data.mainData.black);
  const whiteScore = totalGames > 0 ? ((data.mainData.white + 0.5 * data.mainData.draws) / totalGames * 100).toFixed(1) : '50.0';
  const blackScore = (100 - parseFloat(whiteScore)).toFixed(1);
  const decisive = totalGames > 0 ? (((data.mainData.white + data.mainData.black) / totalGames) * 100).toFixed(1) : '0';
  const drawRate = totalGames > 0 ? ((data.mainData.draws / totalGames) * 100).toFixed(1) : '0';
  const movesStr = data.moves.map((m) => m.san).join(' ');
  const fashionIndex = calculateFashionIndex(data.historicalData.yearlyData);
  const fashion = getFashionLabel(fashionIndex);
  const turn = data.mainData.turn || 'white';

  return (
    <div id="report-content" style={{ display: 'block' }}>
      {/* Title */}
      <div className="report-title">
        <h2>{data.openingInfo.name}</h2>
        <span className="eco-code">ECO {data.openingInfo.eco}</span>
        <div className="opening-moves">{movesStr}</div>
        <div className="game-count">
          {totalGames.toLocaleString()} games in database
          {data.options.source === 'masters' ? ' (Masters)' : ` (Lichess ${data.options.speed})`}
        </div>
      </div>

      {/* Summary bar */}
      <div className="report-section">
        <div className="report-section-body">
          <div className="report-summary-bar">
            <div className="summary-stat">
              <div className="stat-value">{totalGames.toLocaleString()}</div>
              <div className="stat-label">Total Games</div>
            </div>
            <div className="summary-stat">
              <div className="stat-value" style={{ color: 'var(--accent-green)' }}>{whiteScore}%</div>
              <div className="stat-label">White Score</div>
            </div>
            <div className="summary-stat">
              <div className="stat-value" style={{ color: 'var(--accent-red)' }}>{blackScore}%</div>
              <div className="stat-label">Black Score</div>
            </div>
            <div className="summary-stat">
              <div className="stat-value">{drawRate}%</div>
              <div className="stat-label">Draw Rate</div>
            </div>
            <div className="summary-stat">
              <div className="stat-value">{decisive}%</div>
              <div className="stat-label">Decisive</div>
            </div>
            <div className="summary-stat">
              <div className="stat-value">{data.mainData.moves?.length ?? 0}</div>
              <div className="stat-label">Move Options</div>
            </div>
          </div>
          <div className="win-bar">
            <div className="w-white" style={{ width: `${wdl.whitePct}%` }}></div>
            <div className="w-draw" style={{ width: `${wdl.drawPct}%` }}></div>
            <div className="w-black" style={{ width: `${wdl.blackPct}%` }}></div>
          </div>
          <div className="win-bar-labels">
            <span>White: {wdl.whitePct}%</span>
            <span>Draw: {wdl.drawPct}%</span>
            <span>Black: {wdl.blackPct}%</span>
          </div>
        </div>
      </div>

      {/* Move statistics */}
      <MoveStats data={data} turn={turn} totalGames={totalGames} />

      {/* Historical development & fashion index */}
      <div className="report-section">
        <div className="report-section-header">
          <span className="section-icon">📈</span>
          <h3>Historical Development & Fashion Index</h3>
        </div>
        <div className="report-section-body">
          <div style={{ display: 'flex', gap: '20px', marginBottom: '16px', alignItems: 'center' }}>
            <div>
              <span className={`badge ${fashion.color}`}>Fashion: {fashion.label}</span>
            </div>
            <div style={{ fontSize: '13px', color: 'var(--text-dim)' }}>
              {fashionIndex}% of top games played in the last 5 years
            </div>
          </div>
          {data.historicalData.yearlyData.length > 0 ? (
            <div className="chart-container">
              <canvas ref={canvasRef}></canvas>
            </div>
          ) : (
            <p style={{ color: 'var(--text-dim)' }}>
              Historical data is limited for this position. The chart shows the distribution of top games by year.
            </p>
          )}
          <p style={{ marginTop: '12px', fontSize: '13px', color: 'var(--text-dim)' }}>
            The chart above shows the distribution of top-level games over time,
            illustrating how the popularity of this variation has evolved.
          </p>
        </div>
      </div>

      {/* Pioneers */}
      <Pioneers data={data} />

      {/* Elo-segmented statistics */}
      <EloStats data={data} />

      {/* Variation characterization */}
      <div className="report-section">
        <div className="report-section-header">
          <span className="section-icon">🎭</span>
          <h3>Variation Characterization — Strategic Themes</h3>
        </div>
        <div className="report-section-body">
          <p style={{ marginBottom: '14px', fontSize: '13px', color: 'var(--text-dim)' }}>
            The system automatically describes the strategic traits of this variation —
            pawn structures, piece activity, king safety, and positional character.
          </p>
          <div className="characterization-grid">
            {data.characterization.map((trait, i) => (
              <div className="char-card" key={i}>
                <div className="char-icon">{trait.icon}</div>
                <div className="char-title">{trait.title}</div>
                <div className="char-desc">{trait.desc}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Main lines & critical lines */}
      <MainLines data={data} turn={turn} totalGames={totalGames} />

      {/* Maneuvers */}
      <div className="report-section">
        <div className="report-section-header">
          <span className="section-icon">♟</span>
          <h3>Typical Piece Maneuvers & Pawn Advances</h3>
        </div>
        <div className="report-section-body">
          <p style={{ marginBottom: '14px', fontSize: '13px', color: 'var(--text-dim)' }}>
            Recurring piece routes and pawn advances extracted from top games.
            These show the typical plans and strategic regroupings in this variation.
          </p>
          <div className="maneuver-list">
            {data.maneuvers.length === 0 ? (
              <p style={{ color: 'var(--text-dim)' }}>Insufficient game data to extract piece maneuvers.</p>
            ) : (
              data.maneuvers.map((m) => (
                <div className="maneuver-item" key={m.key}>
                  <span className="piece-symbol">{getPieceSymbol(m.piece, m.color)}</span>
                  <span className="maneuver-path">{m.pathStr}</span>
                  <span className="maneuver-games">{m.games} games</span>
                  <span className={`success-badge ${m.successLabel === 'good' ? 'good' : ''}`}>{m.frequency}%</span>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      {/* Instructive games */}
      <InstructiveGames data={data} />

      {/* Tactical training */}
      <TacticalTraining data={data} />

      {/* Transpositions */}
      {data.transpositions.length > 0 && (
        <div className="report-section">
          <div className="report-section-header">
            <span className="section-icon">🔀</span>
            <h3>Transpositions</h3>
          </div>
          <div className="report-section-body">
            <p style={{ marginBottom: '14px', fontSize: '13px', color: 'var(--text-dim)' }}>
              Different move orders that lead to the same position.
              Knowing these helps you avoid or steer into this variation.
            </p>
            <div className="transposition-list">
              {data.transpositions.map((trans, i) => (
                <div className="transposition-item" key={i}>
                  <div className="trans-moves">{trans.moves}</div>
                  <div className="trans-name">{trans.description}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Repertoire suggestions */}
      <RepertoireSuggestion data={data} turn={turn} totalGames={totalGames} />
    </div>
  );
}

// ===== Sub-components =====

function MoveStats({ data, turn, totalGames }: { data: ReportData; turn: string; totalGames: number }) {
  const moves = data.mainData.moves || [];
  const sortedMoves = [...moves].sort((a, b) => (b.white + b.draws + b.black) - (a.white + a.draws + b.black));

  return (
    <div className="report-section">
      <div className="report-section-header">
        <span className="section-icon">📊</span>
        <h3>Move Statistics — Best Moves for {turn === 'white' ? 'White' : 'Black'}</h3>
      </div>
      <div className="report-section-body">
        <p style={{ marginBottom: '12px', color: 'var(--text-dim)', fontSize: '13px' }}>
          The best moves are computed based on game count, success rates, Elo performance,
          and recent popularity. The critical line follows the most statistically promising moves for both sides.
        </p>
        <table className="stats-table">
          <thead>
            <tr>
              <th>Move</th>
              <th className="number">Games</th>
              <th className="number">Freq.</th>
              <th>W / D / B</th>
              <th className="number">{turn === 'white' ? 'White' : 'Black'} Score</th>
              <th className="number">Avg Elo</th>
            </tr>
          </thead>
          <tbody>
            {sortedMoves.slice(0, 15).map((move) => {
              const total = move.white + move.draws + move.black;
              const wdl = formatWDL(move.white, move.draws, move.black);
              const score = turn === 'white'
                ? ((move.white + 0.5 * move.draws) / total * 100).toFixed(1)
                : ((move.black + 0.5 * move.draws) / total * 100).toFixed(1);
              const freq = total > 0 ? (total / totalGames * 100).toFixed(1) : '0';
              return (
                <tr key={move.uci}>
                  <td><strong>{move.san}</strong></td>
                  <td className="number">{total.toLocaleString()}</td>
                  <td className="number">{freq}%</td>
                  <td>
                    <div className="win-bar" style={{ minWidth: '120px', height: '14px' }}>
                      <div className="w-white" style={{ width: `${wdl.whitePct}%` }}></div>
                      <div className="w-draw" style={{ width: `${wdl.drawPct}%` }}></div>
                      <div className="w-black" style={{ width: `${wdl.blackPct}%` }}></div>
                    </div>
                  </td>
                  <td className="number">{score}%</td>
                  <td className="number">{move.averageRating ? Math.round(move.averageRating) : '—'}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function Pioneers({ data }: { data: ReportData }) {
  const playerStats: Record<string, { games: number; wins: number; draws: number; losses: number; elo: number }> = {};

  for (const game of data.gamesWithPgn) {
    if (!game.pgn) continue;
    const headers = parsePGNHeaders(game.pgn);
    const white = headers.White || 'Unknown';
    const black = headers.Black || 'Unknown';
    const whiteElo = parseInt(headers.WhiteElo) || 0;
    const blackElo = parseInt(headers.BlackElo) || 0;
    const result = headers.Result || '*';

    if (!playerStats[white]) playerStats[white] = { games: 0, wins: 0, draws: 0, losses: 0, elo: whiteElo };
    playerStats[white].games++;
    if (result === '1-0') playerStats[white].wins++;
    else if (result === '0-1') playerStats[white].losses++;
    else playerStats[white].draws++;

    if (!playerStats[black]) playerStats[black] = { games: 0, wins: 0, draws: 0, losses: 0, elo: blackElo };
    playerStats[black].games++;
    if (result === '0-1') playerStats[black].wins++;
    else if (result === '1-0') playerStats[black].losses++;
    else playerStats[black].draws++;
  }

  const sortedPlayers = Object.entries(playerStats).sort((a, b) => b[1].games - a[1].games).slice(0, 12);

  return (
    <div className="report-section">
      <div className="report-section-header">
        <span className="section-icon">👑</span>
        <h3>Pioneers & Notable Players</h3>
      </div>
      <div className="report-section-body">
        <p style={{ marginBottom: '14px', fontSize: '13px', color: 'var(--text-dim)' }}>
          These players have used this variation in their games. Click a player to see their games in this line.
        </p>
        <div className="pioneer-list">
          {sortedPlayers.length === 0 ? (
            <p style={{ color: 'var(--text-dim)' }}>No notable player data available.</p>
          ) : (
            sortedPlayers.map(([name, stats]) => {
              const score = stats.games > 0 ? ((stats.wins + 0.5 * stats.draws) / stats.games * 100).toFixed(0) : '0';
              const scoreClass = parseFloat(score) >= 60 ? 'good' : parseFloat(score) < 40 ? 'bad' : '';
              return (
                <div className="pioneer-card" key={name}>
                  <div className="pioneer-name">{name}</div>
                  <div className="pioneer-games">{stats.games} game{stats.games !== 1 ? 's' : ''} {stats.elo > 0 ? `Elo ${stats.elo}` : ''}</div>
                  <div className={`pioneer-score ${scoreClass}`}>{score}% score</div>
                </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}

function EloStats({ data }: { data: ReportData }) {
  const segments = data.eloData.filter((seg) => {
    const total = seg.data.white + seg.data.draws + seg.data.black;
    return total > 0;
  });

  return (
    <div className="report-section">
      <div className="report-section-header">
        <span className="section-icon">🎚</span>
        <h3>Elo-Segmented Performance Statistics</h3>
      </div>
      <div className="report-section-body">
        <p style={{ marginBottom: '14px', fontSize: '13px', color: 'var(--text-dim)' }}>
          How this opening performs at different rating levels. What fails at grandmaster level
          can score brilliantly for club players — and vice versa.
        </p>
        <table className="stats-table elo-table">
          <thead>
            <tr>
              <th>Elo Range</th>
              <th className="number">Games</th>
              <th>W / D / B</th>
              <th className="number">White Score</th>
              <th className="number">Black Score</th>
              <th className="number">Draw Rate</th>
              <th>Top Move</th>
            </tr>
          </thead>
          <tbody>
            {segments.length === 0 ? (
              <tr><td colSpan={7} style={{ textAlign: 'center', color: 'var(--text-dim)' }}>No Elo-segmented data available.</td></tr>
            ) : (
              segments.map((seg) => {
                const d = seg.data;
                const total = d.white + d.draws + d.black;
                const wdl = formatWDL(d.white, d.draws, d.black);
                const whiteScore = ((d.white + 0.5 * d.draws) / total * 100).toFixed(1);
                const blackScore = (100 - parseFloat(whiteScore)).toFixed(1);
                const drawRate = (d.draws / total * 100).toFixed(1);
                const topMove = d.moves && d.moves.length > 0
                  ? [...d.moves].sort((a, b) => (b.white + b.draws + b.black) - (a.white + a.draws + a.black))[0].san
                  : '—';
                return (
                  <tr key={seg.range.label}>
                    <td className="elo-range">{seg.range.label}</td>
                    <td className="number">{total.toLocaleString()}</td>
                    <td>
                      <div className="win-bar" style={{ minWidth: '100px', height: '12px' }}>
                        <div className="w-white" style={{ width: `${wdl.whitePct}%` }}></div>
                        <div className="w-draw" style={{ width: `${wdl.drawPct}%` }}></div>
                        <div className="w-black" style={{ width: `${wdl.blackPct}%` }}></div>
                      </div>
                    </td>
                    <td className="number" style={{ color: 'var(--accent-green)' }}>{whiteScore}%</td>
                    <td className="number" style={{ color: 'var(--accent-red)' }}>{blackScore}%</td>
                    <td className="number">{drawRate}%</td>
                    <td><strong>{topMove}</strong></td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function MainLines({ data, turn, totalGames }: { data: ReportData; turn: string; totalGames: number }) {
  const moves = data.mainData.moves || [];
  const sorted = [...moves].sort((a, b) => {
    const aTotal = a.white + a.draws + a.black;
    const bTotal = b.white + b.draws + b.black;
    if (aTotal === 0 || bTotal === 0) return bTotal - aTotal;
    const aScore = turn === 'white' ? (a.white + 0.5 * a.draws) / aTotal : (a.black + 0.5 * a.draws) / aTotal;
    const bScore = turn === 'white' ? (b.white + 0.5 * b.draws) / bTotal : (b.black + 0.5 * b.draws) / bTotal;
    return bScore - aScore;
  });

  const maxGames = Math.max(...sorted.map((m) => m.white + m.draws + m.black), 0);
  const mainLine = sorted.find((m) => m.white + m.draws + m.black === maxGames);
  const criticalLine = sorted.find((m) => m.white + m.draws + m.black > 10) || sorted[0];

  const renderLine = (move: typeof sorted[0] | undefined, label: string, cls: string) => {
    if (!move) return null;
    const total = move.white + move.draws + move.black;
    const score = turn === 'white'
      ? ((move.white + 0.5 * move.draws) / total * 100).toFixed(1)
      : ((move.black + 0.5 * move.draws) / total * 100).toFixed(1);
    return (
      <div className="tree-line">
        <div className="tree-line-header">{label}</div>
        <span className={`tree-move ${cls}`}>
          <span className="move-notation">{move.san}</span>
          <span className="move-stats">{total} games, {score}% score</span>
        </span>
      </div>
    );
  };

  return (
    <div className="report-section">
      <div className="report-section-header">
        <span className="section-icon">🟢</span>
        <h3>Main Lines & Critical Variations</h3>
      </div>
      <div className="report-section-body">
        <p style={{ marginBottom: '14px', fontSize: '13px', color: 'var(--text-dim)' }}>
          The main line is the most frequently played continuation.
          The critical line is where both sides make the statistically most promising moves.
        </p>
        <div className="move-tree">
          {renderLine(mainLine, '🟢 Main Line (Most Popular)', 'main')}
          {renderLine(criticalLine, '★ Critical Line (Best Scoring)', 'critical')}
          <div className="tree-line">
            <div className="tree-line-header">All Candidate Moves</div>
            {sorted.slice(0, 12).map((move) => {
              const total = move.white + move.draws + move.black;
              if (total === 0) return null;
              const score = turn === 'white'
                ? ((move.white + 0.5 * move.draws) / total * 100).toFixed(1)
                : ((move.black + 0.5 * move.draws) / total * 100).toFixed(1);
              const freq = (total / totalGames * 100).toFixed(1);
              return (
                <span className="tree-move" key={move.uci}>
                  <span className="move-notation">{move.san}</span>
                  <span className="move-stats">{total} games ({freq}%) • {score}%</span>
                </span>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}

function InstructiveGames({ data }: { data: ReportData }) {
  const games = data.gamesWithPgn.filter((g) => g.pgn).slice(0, 10);

  const handleGameClick = (game: typeof games[0]) => {
    if (game.pgn) {
      const headers = parsePGNHeaders(game.pgn);
      window.dispatchEvent(new CustomEvent('scidb:open-game-viewer', {
        detail: { pgn: game.pgn, title: `${headers.White} vs ${headers.Black}` },
      }));
    }
  };

  return (
    <div className="report-section">
      <div className="report-section-header">
        <span className="section-icon">🎓</span>
        <h3>Instructive Study Games</h3>
      </div>
      <div className="report-section-body">
        <p style={{ marginBottom: '14px', fontSize: '13px', color: 'var(--text-dim)' }}>
          These are clear games in which a strong player demonstrates how to handle this opening.
          Click any game to replay it move by move.
        </p>
        <div className="game-list">
          {games.length === 0 ? (
            <p style={{ color: 'var(--text-dim)' }}>No instructive games available.</p>
          ) : (
            games.map((game, idx) => {
              const headers = parsePGNHeaders(game.pgn!);
              const result = headers.Result || '*';
              const resultClass = result === '1-0' ? 'badge-green' : result === '0-1' ? 'badge-red' : 'badge-gray';
              const resultText = result === '1-0' ? '1–0' : result === '0-1' ? '0–1' : '½–½';
              const year = game.month ? game.month.substring(0, 4) : (headers.Date ? headers.Date.substring(0, 4) : '');
              return (
                <div className="game-entry" key={game.id} onClick={() => handleGameClick(game)} style={{ cursor: 'pointer' }}>
                  <div className="game-num">{idx + 1}.</div>
                  <div className="game-players">
                    <div className="player-names">{headers.White || 'White'} vs {headers.Black || 'Black'}</div>
                    <div className="game-meta">{headers.Event || ''} {year}</div>
                  </div>
                  <div className="game-result">
                    <span className={`badge ${resultClass}`}>{resultText}</span>
                  </div>
                  <div className="game-elo">
                    {headers.WhiteElo ? `W: ${headers.WhiteElo}` : ''}<br />
                    {headers.BlackElo ? `B: ${headers.BlackElo}` : ''}
                  </div>
                </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}

function TacticalTraining({ data }: { data: ReportData }) {
  const tactics = data.tactics;

  const handleTacticClick = (index: number) => {
    window.dispatchEvent(new CustomEvent('scidb:open-tactics', {
      detail: { tactics, startIndex: index },
    }));
  };

  return (
    <div className="report-section">
      <div className="report-section-header">
        <span className="section-icon">⚡</span>
        <h3>Tactical Training — Typical Motifs</h3>
      </div>
      <div className="report-section-body">
        <p style={{ marginBottom: '14px', fontSize: '13px', color: 'var(--text-dim)' }}>
          Interactive tactical exercises extracted from real games in this opening.
          Solve them to train the recurring motifs specific to this variation.
        </p>
        <div className="tactics-grid">
          {tactics.length === 0 ? (
            <p style={{ color: 'var(--text-dim)' }}>No tactical positions extracted from the available games.</p>
          ) : (
            tactics.map((tactic, idx) => (
              <div className="tactic-card" key={idx} onClick={() => handleTacticClick(idx)} style={{ cursor: 'pointer' }}>
                <div className="tactic-num">Exercise {idx + 1}</div>
                <div className="tactic-motif">{tactic.motif}</div>
                <div className="tactic-fen">{tactic.fen.split(' ')[0].substring(0, 40)}…</div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}

function RepertoireSuggestion({ data, turn, totalGames }: { data: ReportData; turn: string; totalGames: number }) {
  const moves = data.mainData.moves || [];
  let bestMove: typeof moves[0] | null = null;
  let bestScore = -1;

  for (const move of moves) {
    const moveTotal = move.white + move.draws + move.black;
    if (moveTotal < 5) continue;
    const score = turn === 'white'
      ? (move.white + 0.5 * move.draws) / moveTotal
      : (move.black + 0.5 * move.draws) / moveTotal;
    if (score > bestScore) {
      bestScore = score;
      bestMove = move;
    }
  }

  const sideName = turn === 'white' ? 'White' : 'Black';

  return (
    <div className="report-section">
      <div className="report-section-header">
        <span className="section-icon">📚</span>
        <h3>Repertoire Suggestion</h3>
      </div>
      <div className="report-section-body">
        <div className="repertoire-box">
          <div className="rep-title">Ready-made Repertoire</div>
          <div className="rep-content">
            {bestMove ? (
              <>
                <strong>Recommended for {sideName}:</strong> {bestMove.san}<br />
                Score: {(bestScore * 100).toFixed(1)}% in {bestMove.white + bestMove.draws + bestMove.black} games
                ({((bestMove.white + bestMove.draws + bestMove.black) / totalGames * 100).toFixed(1)}% frequency).<br /><br />
                <strong>Why:</strong> This move achieves the best practical results based on
                database statistics, combining strong scoring percentage with adequate sample size.
                Study the instructive games above to understand the resulting middlegame plans.
              </>
            ) : (
              'No clear recommendation — insufficient data. Try the main line and study the instructive games.'
            )}
          </div>
        </div>
      </div>
    </div>
  );
}