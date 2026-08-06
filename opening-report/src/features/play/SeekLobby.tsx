import { useEffect, useState, useCallback } from 'react';
import { createApiClient } from '@/api/client';
import { useWorkspaceStore } from '@/state/workspace';
import type { PlaySeek, PlayMatch } from '@/types';
import { isLocalPlayer } from './playIdentity';

const api = createApiClient();

/**
 * SeekLobby — the pre-match lobby: create a seek, see open seeks from other
 * tabs, accept one to start a match, and review finished games. Shown when
 * there is no active match. Two tabs see each other's seeks because the mock
 * backend syncs via BroadcastChannel.
 */
const TIME_CONTROLS = [
  { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2, label: 'Blitz 3+2' },
  { kind: 'rapid', baseSeconds: 600, incrementSeconds: 0, label: 'Rapid 10+0' },
  { kind: 'bullet', baseSeconds: 60, incrementSeconds: 0, label: 'Bullet 1+0' },
  { kind: 'unlimited', baseSeconds: 0, incrementSeconds: 0, label: 'Unlimited' },
] as const;

export default function SeekLobby() {
  const seeks = useWorkspaceStore((s) => s.seeks);
  const setSeeks = useWorkspaceStore((s) => s.setSeeks);
  const [mySeeks, setMySeeks] = useState<PlaySeek[]>([]);
  const [myGames, setMyGames] = useState<PlayMatch[]>([]);
  const [databases, setDatabases] = useState<{ id: string; name: string }[]>([]);
  const [tcIndex, setTcIndex] = useState(0);
  const [rated, setRated] = useState(false);
  const [busy, setBusy] = useState(false);
  const toast = window.ScidbWorkspace?.toast || console.log;

  const refresh = useCallback(async () => {
    setSeeks(await api.listSeeks());
    setMySeeks(await api.listMySeeks());
    setMyGames(await api.listMyGames());
    try { setDatabases((await api.listDatabases()).map((d) => ({ id: d.id, name: d.name }))); } catch { /* ignore */ }
  }, [setSeeks]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const handleCreate = () => {
    if (busy) return;
    const tc = TIME_CONTROLS[tcIndex];
    setBusy(true);
    api
      .createSeek({
        timeControl: { kind: tc.kind, baseSeconds: tc.baseSeconds, incrementSeconds: tc.incrementSeconds },
        variant: 'standard',
        rated,
        color: 'random',
        ratingRange: null,
      })
      .then(() => refresh())
      .then(() => toast('Seek created — waiting for an opponent', 'accent'))
      .catch((e) => toast(`Create seek failed: ${e instanceof Error ? e.message : String(e)}`, 'warning'))
      .finally(() => setBusy(false));
  };

  const handleCancel = (id: string) => {
    api.cancelSeek(id).then(() => refresh()).catch(() => {});
  };

  const handleArchive = (g: PlayMatch) => {
    const dbId = databases[0]?.id;
    if (!dbId) { toast('Open or create a database first', 'warning'); return; }
    api.archiveMatch(g.id, dbId)
      .then((r) => toast(`Archiving as PGN… (job ${r.jobId})`, 'accent'))
      .catch((e) => toast(`Archive failed: ${e instanceof Error ? e.message : String(e)}`, 'warning'));
  };

  const handleAccept = (seek: PlaySeek) => {
    if (busy) return;
    setBusy(true);
    api
      .acceptSeek(seek.id)
      .then(() => toast('Match starting…', 'success'))
      .catch((e) => toast(`Accept failed: ${e instanceof Error ? e.message : String(e)}`, 'warning'))
      .finally(() => setBusy(false));
  };

  return (
    <div className="seek-lobby">
      <div className="lobby-section">
        <h4>New seek</h4>
        <div className="lobby-row">
          <select value={tcIndex} onChange={(e) => setTcIndex(Number(e.target.value))}>
            {TIME_CONTROLS.map((tc, i) => (
              <option key={tc.label} value={i}>{tc.label}</option>
            ))}
          </select>
          <label className="lobby-check">
            <input type="checkbox" checked={rated} onChange={(e) => setRated(e.target.checked)} /> Rated
          </label>
          <button className="primary-btn" onClick={handleCreate} disabled={busy}>＋ Create seek</button>
        </div>
      </div>

      <div className="lobby-section">
        <h4>Open seeks ({seeks.length})</h4>
        {seeks.length === 0 ? (
          <p className="lobby-empty">No open seeks. Create one, or open a second browser tab to play yourself.</p>
        ) : (
          <ul className="seek-list">
            {seeks.map((s) => (
              <li key={s.id} className="seek-row">
                <span className="seek-owner">{s.owner.name}</span>
                <span className="seek-tc">{s.timeControl.kind} · {s.variant}</span>
                {s.rated && <span className="seek-rated">rated</span>}
                <button className="small-btn" onClick={() => handleAccept(s)} disabled={busy}>Accept</button>
              </li>
            ))}
          </ul>
        )}
      </div>

      {mySeeks.length > 0 && (
        <div className="lobby-section">
          <h4>My seeks ({mySeeks.length})</h4>
          <ul className="seek-list">
            {mySeeks.map((s) => (
              <li key={s.id} className="seek-row">
                <span className="seek-owner">waiting…</span>
                <span className="seek-tc">{s.timeControl.kind}</span>
                <button className="small-btn" onClick={() => handleCancel(s.id)}>Cancel</button>
              </li>
            ))}
          </ul>
        </div>
      )}

      {myGames.length > 0 && (
        <div className="lobby-section">
          <h4>My games ({myGames.length})</h4>
          <ul className="seek-list">
            {myGames.map((g) => {
              const r = g.result;
              const mine = isLocalPlayer(g.white.id) ? 'w' : 'b';
              let outcome = '';
              if (r?.kind === 'mate' || r?.kind === 'resign' || r?.kind === 'timeout') outcome = r.winner === mine ? 'Win' : 'Loss';
              else if (r?.kind === 'draw') outcome = 'Draw';
              return (
                <li key={g.id} className="seek-row">
                  <span className="seek-owner">{g.white.name} vs {g.black.name}</span>
                  <span className="seek-tc">{g.timeControl.kind}</span>
                  <span className={`seek-outcome ${outcome.toLowerCase()}`}>{outcome}</span>
                  <button className="small-btn" onClick={() => handleArchive(g)}>Archive</button>
                </li>
              );
            })}
          </ul>
        </div>
      )}
    </div>
  );
}