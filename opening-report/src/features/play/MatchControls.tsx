import { useState } from 'react';
import { createApiClient } from '@/api/client';
import { mockPlay } from './mockPlayBackend';
import type { PlayMatch } from '@/types';

const api = createApiClient();

/**
 * MatchControls — draw / rematch / abort / resign controls for an active match
 * (Phase 5). Resign, draw (offer + accept/decline), abort, and rematch are all
 * wired. The opponent's pending offer surfaces inline with Accept/Decline
 * buttons. Abort is only available before the second move (no rated effect).
 * Chat is intentionally omitted from this control strip — it is off by default
 * in v1 and arrives via a dedicated, rate-limited path when enabled.
 */
export interface MatchControlsProps {
  match: PlayMatch;
}

function myColor(match: PlayMatch, meId: string): 'w' | 'b' {
  return match.white.id === meId ? 'w' : 'b';
}

export default function MatchControls({ match }: MatchControlsProps) {
  const [busy, setBusy] = useState(false);
  const toast = window.ScidbWorkspace?.toast || console.log;
  const meId = mockPlay.me.id;
  const color = myColor(match, meId);
  const finished = match.status === 'finished';

  // Opponent's pending offer (the side != mine).
  const oppDraw = match.drawOfferSide && match.drawOfferSide !== color ? 'draw' : null;
  const oppRematch = match.rematchOfferSide && match.rematchOfferSide !== color ? 'rematch' : null;
  const pendingOffer = oppDraw || oppRematch;

  const run = async (fn: () => Promise<unknown>, msg: string) => {
    if (busy) return;
    setBusy(true);
    try {
      await fn();
      toast(msg, 'accent');
    } catch (e) {
      toast(`${e instanceof Error ? e.message : String(e)}`, 'warning');
    } finally {
      setBusy(false);
    }
  };

  const handleOffer = (kind: 'draw' | 'rematch') =>
    run(() => api.offerMatch(match.id, kind), kind === 'draw' ? 'Draw offered' : 'Rematch offered');

  const handleRespond = (accept: boolean) =>
    run(() => api.respondOffer(match.id, accept), accept ? 'Offer accepted' : 'Offer declined');

  const handleAbort = () => {
    if (!window.confirm('Abort this game? (only before the second move; no rated effect)')) return;
    run(() => api.abortMatch(match.id), 'Game aborted');
  };

  const handleResign = () => {
    if (finished || busy) return;
    if (!window.confirm('Resign this game?')) return;
    run(() => api.resignMatch(match.id), 'Resigned');
  };

  if (finished) {
    return null; // PlayBoardPanel shows the result banner when finished.
  }

  return (
    <div className="match-controls">
      {pendingOffer ? (
        <>
          <span className="offer-prompt">
            Opponent offers {pendingOffer}
          </span>
          <button className="ghost-btn" onClick={() => handleRespond(true)} disabled={busy}>Accept</button>
          <button className="ghost-btn" onClick={() => handleRespond(false)} disabled={busy}>Decline</button>
        </>
      ) : (
        <>
          <button className="ghost-btn" onClick={() => handleOffer('draw')} disabled={busy} title="Offer a draw">Draw</button>
          <button
            className="ghost-btn"
            onClick={() => handleOffer('rematch')}
            disabled={busy}
            title={finished ? 'Offer rematch' : 'Rematch is available after the game ends'}
            style={!finished ? { opacity: 0.5 } : undefined}
          >
            Rematch
          </button>
          <button className="ghost-btn" onClick={handleAbort} disabled={busy} title="Abort (only before the 2nd move)">Abort</button>
          <button className="ghost-btn" onClick={handleResign} disabled={busy}>Resign</button>
        </>
      )}
    </div>
  );
}