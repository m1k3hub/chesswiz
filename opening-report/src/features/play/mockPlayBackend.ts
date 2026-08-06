/**
 * mockPlayBackend — in-browser mock of the online-play server (Phase 2).
 *
 * Holds seeks/matches/moves in memory, validates moves with chess.js, and
 * synchronises across browser tabs via BroadcastChannel so two tabs can play
 * each other without a real server. Mirrors the `/api/play/*` REST + WS `/play`
 * contract defined in ONLINE_PLAY_PLAN.md; the MockScidbApiClient delegates
 * here, and usePlaySocket subscribes here for events.
 *
 * The "server" is the source of truth: submitMove validates against a chess.js
 * instance held per match; clocks are updated server-side (in the tab that made
 * the move) and broadcast as snapshots; the match creator's tab is the clock
 * arbiter that flags timeouts. BroadcastChannel does not deliver a message to
 * the posting context, so the acting tab updates its own state directly and
 * broadcasts for the other tab.
 */

import { Chess } from 'chess.js';
import type {
  PlaySeek,
  PlayMatch,
  PlayMove,
  PlayResult,
  PlayTimeControl,
  PlayVariant,
  PlayUser,
  PlayEvent,
} from '@/types';

const CHANNEL = 'scidb-play-mock';

import { getPlayGuestId } from './playIdentity';

function makeGuestUser(): PlayUser {
  // Reuse the single shared session identity so the mock agrees with the real
  // transport and with REST/WS guest ids (see playIdentity.ts).
  const id = getPlayGuestId();
  const name = 'Guest-' + id.slice(-4).toUpperCase();
  return { id, name, rating: 1500 };
}

function startFenFor(): string {
  // chess.js supports standard and Chess960 via FEN with castling rights. For
  // v1 mock we use the standard start; Chess960 start FEN parity is exercised
  // in Phase 4 against the scidb C++ bridge.
  return 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
}

function nowMs(): number {
  return Date.now();
}

interface MatchRecord {
  match: PlayMatch;
  moves: PlayMove[];
  chess: Chess;
  arbiterId: string; // creator's user id — the clock arbiter
}

type BroadcastMessage =
  | { kind: 'seek'; seek: PlaySeek }
  | { kind: 'seek-cancel'; seekId: string }
  | { kind: 'match'; match: PlayMatch }
  | { kind: 'move'; matchId: string; move: PlayMove; clocks: PlayMatch['clocks']; clockUpdatedAt: number; result: PlayResult | null }
  | { kind: 'finish'; matchId: string; result: PlayResult; clocks: PlayMatch['clocks'] }
  | { kind: 'sync-request' }
  | { kind: 'sync-state'; seeks: PlaySeek[]; matches: PlayMatch[] };

class MockPlayBackend {
  me: PlayUser;
  private seeks = new Map<string, PlaySeek>();
  private matches = new Map<string, MatchRecord>();
  private myGames: PlayMatch[] = [];
  private subscribers = new Set<(event: PlayEvent) => void>();
  private channel: BroadcastChannel | null = null;
  private timeoutTimer: ReturnType<typeof setInterval> | null = null;

  constructor() {
    this.me = makeGuestUser();
    if (typeof BroadcastChannel !== 'undefined') {
      this.channel = new BroadcastChannel(CHANNEL);
      this.channel.onmessage = (e) => this.onBroadcast(e.data as BroadcastMessage);
      // Ask existing tabs for current state.
      this.post({ kind: 'sync-request' });
    }
    // Clock arbiter loop: every 200ms, check matches where this tab is arbiter.
    this.timeoutTimer = setInterval(() => this.checkTimeouts(), 200);
    // Don't keep the Node/test process alive on this handle.
    (this.timeoutTimer as { unref?: () => void }).unref?.();
  }

  private post(msg: BroadcastMessage) {
    this.channel?.postMessage(msg);
  }

  private notify(event: PlayEvent) {
    this.subscribers.forEach((h) => h(event));
  }

  private onBroadcast(msg: BroadcastMessage) {
    switch (msg.kind) {
      case 'seek':
        if (!this.seeks.has(msg.seek.id)) {
          this.seeks.set(msg.seek.id, msg.seek);
          this.notify({ type: 'seek.created', seek: msg.seek });
        }
        break;
      case 'seek-cancel':
        if (this.seeks.delete(msg.seekId)) {
          this.notify({ type: 'seek.cancelled', seekId: msg.seekId });
        }
        break;
      case 'match': {
        const m = msg.match;
        if (!this.matches.has(m.id)) {
          const chess = new Chess(m.startFen);
          this.matches.set(m.id, {
            match: m,
            moves: [],
            chess,
            arbiterId: m.arbiterId ?? m.white.id,
          });
        }
        this.notify({ type: 'match.paired', match: msg.match });
        break;
      }
      case 'move': {
        const rec = this.matches.get(msg.matchId);
        if (!rec) break;
        // Apply to our chess instance (already validated by the sender).
        try {
          const uci = msg.move.uci;
          const from = uci.slice(0, 2);
          const to = uci.slice(2, 4);
          const promo = (uci[4] as 'q' | 'r' | 'b' | 'n' | undefined) || 'q';
          rec.chess.move({ from, to, promotion: promo });
        } catch {
          /* ignore — state advanced by snapshot */
        }
        rec.moves.push(msg.move);
        rec.match.ply = rec.moves.length;
        rec.match.clocks = msg.clocks;
        rec.match.clockUpdatedAt = msg.clockUpdatedAt;
        if (msg.result) {
          rec.match.status = 'finished';
          rec.match.result = msg.result;
          this.recordMyGame(rec.match);
        }
        this.notify({ type: 'match.move', matchId: msg.matchId, move: msg.move, clocks: msg.clocks, clockUpdatedAt: msg.clockUpdatedAt });
        if (msg.result) this.notify({ type: 'match.finish', matchId: msg.matchId, result: msg.result, clocks: msg.clocks });
        break;
      }
      case 'finish': {
        const rec = this.matches.get(msg.matchId);
        if (rec) {
          rec.match.status = 'finished';
          rec.match.result = msg.result;
          rec.match.clocks = msg.clocks;
          this.recordMyGame(rec.match);
        }
        this.notify({ type: 'match.finish', matchId: msg.matchId, result: msg.result, clocks: msg.clocks });
        break;
      }
      case 'sync-request':
        // Respond with our state so a newly-opened tab catches up.
        this.post({ kind: 'sync-state', seeks: [...this.seeks.values()], matches: [...this.matches.values()].map((r) => r.match) });
        break;
      case 'sync-state':
        for (const s of msg.seeks) if (!this.seeks.has(s.id)) {
          this.seeks.set(s.id, s);
          this.notify({ type: 'seek.created', seek: s });
        }
        for (const m of msg.matches) if (!this.matches.has(m.id)) {
          this.matches.set(m.id, { match: m, moves: [], chess: new Chess(m.startFen), arbiterId: m.arbiterId ?? m.white.id });
          if (this.isMine(m)) this.notify({ type: 'match.paired', match: m });
        }
        break;
    }
  }

  private isMine(m: PlayMatch): boolean {
    return m.white.id === this.me.id || m.black.id === this.me.id;
  }

  private recordMyGame(m: PlayMatch) {
    if (this.isMine(m) && !this.myGames.some((g) => g.id === m.id)) {
      this.myGames.unshift(m);
    }
  }

  // ---- public API (mirrors ScidbApiClient.play.*) ----

  listSeeks(): PlaySeek[] {
    return [...this.seeks.values()].filter((s) => s.owner.id !== this.me.id);
  }

  listMySeeks(): PlaySeek[] {
    return [...this.seeks.values()].filter((s) => s.owner.id === this.me.id);
  }

  createSeek(payload: {
    timeControl: PlayTimeControl;
    variant: PlayVariant;
    rated: boolean;
    color: 'w' | 'b' | 'random';
    ratingRange?: [number, number] | null;
    startFen?: string;
  }): PlaySeek {
    const seek: PlaySeek = {
      id: 'seek-' + Math.random().toString(36).slice(2, 10),
      owner: this.me,
      timeControl: payload.timeControl,
      variant: payload.variant,
      rated: payload.rated,
      color: payload.color,
      ratingRange: payload.ratingRange ?? null,
      startFen: payload.startFen,
      createdAt: nowMs(),
    };
    this.seeks.set(seek.id, seek);
    this.post({ kind: 'seek', seek });
    this.notify({ type: 'seek.created', seek });
    return seek;
  }

  cancelSeek(id: string): void {
    if (this.seeks.delete(id)) {
      this.post({ kind: 'seek-cancel', seekId: id });
      this.notify({ type: 'seek.cancelled', seekId: id });
    }
  }

  acceptSeek(seekId: string): PlayMatch {
    const seek = this.seeks.get(seekId);
    if (!seek) throw new Error('seek not found');
    if (seek.owner.id === this.me.id) throw new Error('cannot accept own seek');
    const sf = seek.startFen || startFenFor();
    let white = seek.owner;
    let black = this.me;
    if (seek.color === 'b') { white = this.me; black = seek.owner; }
    else if (seek.color === 'random' && Math.random() < 0.5) { white = this.me; black = seek.owner; }
    const baseMs = seek.timeControl.baseSeconds * 1000;
    const match: PlayMatch = {
      id: 'match-' + Math.random().toString(36).slice(2, 10),
      variant: seek.variant,
      timeControl: seek.timeControl,
      rated: seek.rated,
      white,
      black,
      startFen: sf,
      ply: 0,
      status: 'playing',
      result: null,
      clocks: { whiteMs: baseMs, blackMs: baseMs },
      clockUpdatedAt: nowMs(),
      drawOfferSide: null,
      rematchOfferSide: null,
      arbiterId: white.id, // creator (seek owner) arbitrates clocks
    };
    this.matches.set(match.id, { match, moves: [], chess: new Chess(sf), arbiterId: white.id });
    this.seeks.delete(seekId);
    this.post({ kind: 'seek-cancel', seekId });
    this.post({ kind: 'match', match });
    this.notify({ type: 'seek.cancelled', seekId });
    this.notify({ type: 'match.paired', match });
    return match;
  }

  submitMove(matchId: string, uci: string): { move: PlayMove; match: PlayMatch; result: PlayResult | null } {
    const rec = this.matches.get(matchId);
    if (!rec) throw new Error('match not found');
    if (rec.match.status === 'finished') throw new Error('match finished');
    const side = rec.chess.turn();
    const myColor = rec.match.white.id === this.me.id ? 'w' : rec.match.black.id === this.me.id ? 'b' : null;
    if (myColor !== side) throw new Error('not your turn');
    const from = uci.slice(0, 2);
    const to = uci.slice(2, 4);
    const promo = (uci[4] as 'q' | 'r' | 'b' | 'n' | undefined) || 'q';
    let move;
    try {
      move = rec.chess.move({ from, to, promotion: promo });
    } catch {
      throw new Error('illegal move');
    }
    if (!move) throw new Error('illegal move');

    // Server-authoritative clock update.
    const now = nowMs();
    const elapsed = now - rec.match.clockUpdatedAt;
    if (side === 'w') rec.match.clocks.whiteMs = Math.max(0, rec.match.clocks.whiteMs - elapsed + rec.match.timeControl.incrementSeconds * 1000);
    else rec.match.clocks.blackMs = Math.max(0, rec.match.clocks.blackMs - elapsed + rec.match.timeControl.incrementSeconds * 1000);
    rec.match.clockUpdatedAt = now;

    const pm: PlayMove = {
      ply: rec.moves.length + 1,
      san: move.san,
      uci: move.from + move.to + (move.promotion || ''),
      fen: rec.chess.fen(),
      clockMsAfter: side === 'w' ? rec.match.clocks.whiteMs : rec.match.clocks.blackMs,
      latencyMs: 0,
    };
    rec.moves.push(pm);
    rec.match.ply = rec.moves.length;

    let result: PlayResult | null = null;
    if (rec.chess.isCheckmate()) result = { kind: 'mate', winner: side }; // mover wins
    else if (rec.chess.isStalemate()) result = { kind: 'draw', reason: 'stalemate' };
    else if (rec.chess.isInsufficientMaterial()) result = { kind: 'draw', reason: 'insufficient' };
    else if (rec.chess.isThreefoldRepetition()) result = { kind: 'draw', reason: 'threefold' };
    else if (rec.chess.isDraw()) result = { kind: 'draw', reason: 'fifty' };

    if (result) {
      rec.match.status = 'finished';
      rec.match.result = result;
      this.recordMyGame(rec.match);
      this.post({ kind: 'move', matchId, move: pm, clocks: rec.match.clocks, clockUpdatedAt: now, result });
      this.notify({ type: 'match.move', matchId, move: pm, clocks: rec.match.clocks, clockUpdatedAt: now });
      this.notify({ type: 'match.finish', matchId, result, clocks: rec.match.clocks });
    } else {
      this.post({ kind: 'move', matchId, move: pm, clocks: rec.match.clocks, clockUpdatedAt: now, result: null });
      this.notify({ type: 'match.move', matchId, move: pm, clocks: rec.match.clocks, clockUpdatedAt: now });
    }
    return { move: pm, match: rec.match, result };
  }

  resign(matchId: string): PlayResult {
    const rec = this.matches.get(matchId);
    if (!rec) throw new Error('match not found');
    const myColor = rec.match.white.id === this.me.id ? 'w' : 'b';
    const result: PlayResult = { kind: 'resign', winner: myColor === 'w' ? 'b' : 'w' };
    rec.match.status = 'finished';
    rec.match.result = result;
    this.recordMyGame(rec.match);
    this.post({ kind: 'finish', matchId, result, clocks: rec.match.clocks });
    this.notify({ type: 'match.finish', matchId, result, clocks: rec.match.clocks });
    return result;
  }

  getMatch(matchId: string): PlayMatch | null {
    return this.matches.get(matchId)?.match ?? null;
  }

  getMatchMoves(matchId: string): PlayMove[] {
    return [...(this.matches.get(matchId)?.moves ?? [])];
  }
  // ---- Phase 5: offers, abort, chat (mirror the server) ----

  private _sanitizeChat(text: string): string {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML.slice(0, 280);
  }

  offer(matchId: string, kind: 'draw' | 'rematch' | 'takeback'): void {
    const rec = this.matches.get(matchId);
    if (!rec) throw new Error('match not found');
    if (kind === 'takeback') throw new Error('takeback not supported in v1');
    const color = rec.match.white.id === this.me.id ? 'w' : 'b';
    if (kind === 'rematch') {
      if (rec.match.status !== 'finished') throw new Error('rematch only after game over');
      rec.match.rematchOfferSide = color;
    } else {
      if (rec.match.status !== 'playing') throw new Error('match finished');
      rec.match.drawOfferSide = color;
    }
    this.notify({ type: 'match.offer', matchId, offer: kind, side: color });
  }

  respondOffer(matchId: string, accept: boolean): void {
    const rec = this.matches.get(matchId);
    if (!rec) throw new Error('match not found');
    const color = rec.match.white.id === this.me.id ? 'w' : 'b';
    const pending = rec.match.drawOfferSide
      ? (rec.match.drawOfferSide !== color ? 'draw' : null)
      : rec.match.rematchOfferSide
        ? (rec.match.rematchOfferSide !== color ? 'rematch' : null)
        : null;
    if (!pending) throw new Error('no pending offer');
    if (!accept) {
      if (pending === 'draw') rec.match.drawOfferSide = null;
      else rec.match.rematchOfferSide = null;
      this.notify({ type: 'match.offer.response', matchId, offer: pending, accepted: false, side: color });
      return;
    }
    this.notify({ type: 'match.offer.response', matchId, offer: pending, accepted: true, side: color });
    if (pending === 'draw') {
      rec.match.status = 'finished';
      rec.match.result = { kind: 'draw', reason: 'agreement' };
      rec.match.drawOfferSide = null;
      this.recordMyGame(rec.match);
      this.notify({ type: 'match.finish', matchId, result: rec.match.result, clocks: rec.match.clocks });
    } else if (pending === 'rematch') {
      rec.match.rematchOfferSide = null;
      const old = rec.match;
      const baseMs = old.timeControl.baseSeconds * 1000;
      const newMatch: PlayMatch = {
        id: 'match-' + Math.random().toString(36).slice(2, 10),
        variant: old.variant,
        timeControl: old.timeControl,
        rated: old.rated,
        white: old.black,
        black: old.white,
        startFen: old.startFen,
        ply: 0,
        status: 'playing',
        result: null,
        clocks: { whiteMs: baseMs, blackMs: baseMs },
        clockUpdatedAt: nowMs(),
        drawOfferSide: null,
        rematchOfferSide: null,
      };
      this.matches.set(newMatch.id, { match: newMatch, moves: [], chess: new Chess(newMatch.startFen), arbiterId: newMatch.white.id });
      this.notify({ type: 'match.paired', match: newMatch });
    }
  }

  abort(matchId: string): PlayResult {
    const rec = this.matches.get(matchId);
    if (!rec) throw new Error('match not found');
    if (rec.match.status !== 'playing') throw new Error('match finished');
    if (rec.moves.length > 1) throw new Error('too many moves to abort');
    const result: PlayResult = { kind: 'aborted' };
    rec.match.status = 'finished';
    rec.match.result = result;
    this.recordMyGame(rec.match);
    this.notify({ type: 'match.finish', matchId, result, clocks: rec.match.clocks });
    return result;
  }

  chat(matchId: string, text: string): { side: 'w' | 'b'; text: string } {
    const rec = this.matches.get(matchId);
    if (!rec) throw new Error('match not found');
    const clean = this._sanitizeChat(text);
    if (!clean.trim()) throw new Error('empty message');
    const side = rec.match.white.id === this.me.id ? 'w' : 'b';
    this.notify({ type: 'match.chat', matchId, side, text: clean });
    return { side, text: clean };
  }


  listMyGames(): PlayMatch[] {
    return [...this.myGames];
  }

  getMyRating(): { variant: PlayVariant; timeControl: string; rating: number; rd: number; vol: number }[] {
    return [{ variant: 'standard', timeControl: 'blitz', rating: this.me.rating, rd: 350, vol: 0.06 }];
  }

  private checkTimeouts() {
    for (const rec of this.matches.values()) {
      if (rec.match.status !== 'playing') continue;
      if (rec.arbiterId !== this.me.id) continue; // only arbiter flags
      const side = rec.chess.turn();
      const elapsed = nowMs() - rec.match.clockUpdatedAt;
      const remaining = (side === 'w' ? rec.match.clocks.whiteMs : rec.match.clocks.blackMs) - elapsed;
      if (rec.match.timeControl.baseSeconds > 0 && remaining <= 0) {
        const result: PlayResult = { kind: 'timeout', winner: side === 'w' ? 'b' : 'w' };
        rec.match.status = 'finished';
        rec.match.result = result;
        if (side === 'w') rec.match.clocks.whiteMs = 0; else rec.match.clocks.blackMs = 0;
        rec.match.clockUpdatedAt = nowMs();
        this.recordMyGame(rec.match);
        this.post({ kind: 'finish', matchId: rec.match.id, result, clocks: rec.match.clocks });
        this.notify({ type: 'match.finish', matchId: rec.match.id, result, clocks: rec.match.clocks });
      }
    }
  }

  // ---- event subscription (for usePlaySocket) ----

  subscribe(handler: (event: PlayEvent) => void): () => void {
    this.subscribers.add(handler);
    return () => { this.subscribers.delete(handler); };
  }


  // ---- test helpers (not part of the public API) ----
  __setMe(user: PlayUser) { this.me = user; }
  __injectSeek(seek: PlaySeek) { this.seeks.set(seek.id, seek); }
  __emit(event: PlayEvent) { this.notify(event); }

  reset() {
    this.seeks.clear();
    this.matches.clear();
    this.myGames = [];
    this.subscribers.clear();
    // Re-derive the local identity from the shared session id so repeated
    // (test) resets never drift away from isLocalPlayer()/getPlayGuestId().
    this.me = makeGuestUser();
  }
}

/** Module singleton — shared by all MockScidbApiClient instances in this tab. */
export const mockPlay = new MockPlayBackend();

// Reset helper for tests.
export function __resetMockPlay() {
  mockPlay.reset();
}