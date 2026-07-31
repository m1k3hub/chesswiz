import { useEffect, useState } from 'react';
import type { PlayMatch } from '@/types';

/**
 * ClockWidget — displays both players' clocks, interpolating the active
 * side's clock downward between server snapshots (server-authoritative: the
 * snapshot arrives via match.move / match.finish events and overrides local
 * drift). Flag-fall (≤ 0) is decided by the server; here we just display.
 */
export interface ClockWidgetProps {
  match: PlayMatch;
  myColor: 'w' | 'b';
}

function format(ms: number): string {
  const total = Math.max(0, Math.ceil(ms / 1000));
  const m = Math.floor(total / 60);
  const s = total % 60;
  if (total >= 60) return `${m}:${s.toString().padStart(2, '0')}`;
  return `${s}.${Math.floor(Math.max(0, ms) % 1000 / 100)}s`;
}

export default function ClockWidget({ match, myColor }: ClockWidgetProps) {
  const [, force] = useState(0);

  useEffect(() => {
    const id = setInterval(() => force((n) => n + 1), 200);
    return () => clearInterval(id);
  }, []);

  const unlimited = match.timeControl.baseSeconds === 0;
  if (unlimited) {
    return (
      <div className="clock-widget">
        <div className="clock-row">White ∞</div>
        <div className="clock-row">Black ∞</div>
      </div>
    );
  }

  const now = Date.now();
  const elapsed = now - match.clockUpdatedAt;
  const turn = match.status === 'playing' ? (match.ply % 2 === 0 ? 'w' : 'b') : null;
  const whiteMs = turn === 'w' ? match.clocks.whiteMs - elapsed : match.clocks.whiteMs;
  const blackMs = turn === 'b' ? match.clocks.blackMs - elapsed : match.clocks.blackMs;

  return (
    <div className="clock-widget">
      <div className={`clock-row ${turn === 'w' ? 'active' : ''} ${myColor === 'w' ? 'mine' : ''}`}>
        <span className="clock-side">White</span>
        <span className={`clock-time ${whiteMs <= 0 ? 'flagged' : ''}`}>{format(whiteMs)}</span>
      </div>
      <div className={`clock-row ${turn === 'b' ? 'active' : ''} ${myColor === 'b' ? 'mine' : ''}`}>
        <span className="clock-side">Black</span>
        <span className={`clock-time ${blackMs <= 0 ? 'flagged' : ''}`}>{format(blackMs)}</span>
      </div>
    </div>
  );
}