import { describe, it, expect, beforeEach } from 'vitest';
import { mockPlay, __resetMockPlay } from './mockPlayBackend';
import type { PlaySeek, PlayUser } from '@/types';

const userA: PlayUser = { id: 'userA', name: 'Alice', rating: 1500 };
const userB: PlayUser = { id: 'userB', name: 'Bob', rating: 1500 };

function blitzSeek(owner: PlayUser, color: 'w' | 'b' | 'random' = 'w'): PlaySeek {
  return {
    id: 'seek-' + owner.id,
    owner,
    timeControl: { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2 },
    variant: 'standard',
    rated: false,
    color,
    ratingRange: null,
    createdAt: Date.now(),
  };
}

describe('MockPlayBackend (Phase 2)', () => {
  beforeEach(() => {
    __resetMockPlay();
    mockPlay.__setMe(userA);
  });

  it('creates, lists (excluding own), and cancels seeks', () => {
    const seek = mockPlay.createSeek({
      timeControl: { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2 },
      variant: 'standard', rated: false, color: 'random', ratingRange: null,
    });
    expect(mockPlay.listMySeeks()).toHaveLength(1);
    expect(mockPlay.listSeeks()).toHaveLength(0); // own seek excluded from open list
    mockPlay.cancelSeek(seek.id);
    expect(mockPlay.listMySeeks()).toHaveLength(0);
  });

  it('accepts a foreign seek and pairs a match', () => {
    mockPlay.__injectSeek(blitzSeek(userB, 'w')); // userB white, me (userA) black
    const match = mockPlay.acceptSeek('seek-userB');
    expect(match.white.id).toBe('userB');
    expect(match.black.id).toBe('userA');
    expect(match.status).toBe('playing');
    expect(match.clocks.whiteMs).toBe(180000);
    expect(mockPlay.getMatch(match.id)).toBeTruthy();
  });

  it('rejects accepting own seek', () => {
    const seek = mockPlay.createSeek({
      timeControl: { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2 },
      variant: 'standard', rated: false, color: 'w', ratingRange: null,
    });
    expect(() => mockPlay.acceptSeek(seek.id)).toThrow(/own seek/);
  });

  it('submitMove rejects illegal moves and not-your-turn moves', () => {
    mockPlay.__injectSeek(blitzSeek(userB, 'w'));
    const match = mockPlay.acceptSeek('seek-userB'); // me is black
    // It is white's turn; me is black → not my turn.
    expect(() => mockPlay.submitMove(match.id, 'e7e5')).toThrow(/not your turn/);
    // Switch to white and try an illegal move.
    mockPlay.__setMe(userB);
    expect(() => mockPlay.submitMove(match.id, 'e2e5')).toThrow(/illegal move/);
  });

  it('applies legal moves, decrements the mover clock, and detects fool\u2019s mate', () => {
    mockPlay.__injectSeek(blitzSeek(userB, 'w')); // userB white, userA black
    const match = mockPlay.acceptSeek('seek-userB');
    const before = match.clocks.whiteMs;

    // 1. f3 (white) — clock accounting: new = old - elapsed + increment.
    mockPlay.__setMe(userB);
    let r = mockPlay.submitMove(match.id, 'f2f3');
    expect(r.move.san).toBe('f3');
    expect(match.ply).toBe(1);
    // An instant move with a 2s increment ≈ old + 2000 (elapsed ~0).
    expect(match.clocks.whiteMs).toBeGreaterThan(before);

    // 1... e5 (black)
    mockPlay.__setMe(userA);
    mockPlay.submitMove(match.id, 'e7e5');

    // 2. g4 (white)
    mockPlay.__setMe(userB);
    mockPlay.submitMove(match.id, 'g2g4');

    // 2... Qh4# (black) → checkmate, black wins
    mockPlay.__setMe(userA);
    r = mockPlay.submitMove(match.id, 'd8h4');
    expect(r.result).toEqual({ kind: 'mate', winner: 'b' });
    expect(match.status).toBe('finished');
    expect(match.result).toEqual({ kind: 'mate', winner: 'b' });
  });

  it('resign finishes the match with the opponent as winner', () => {
    mockPlay.__injectSeek(blitzSeek(userB, 'w'));
    const match = mockPlay.acceptSeek('seek-userB'); // me = black
    const result = mockPlay.resign(match.id);
    expect(result).toEqual({ kind: 'resign', winner: 'w' });
    expect(match.status).toBe('finished');
  });

  it('records finished games in my games', () => {
    mockPlay.__injectSeek(blitzSeek(userB, 'w'));
    const match = mockPlay.acceptSeek('seek-userB');
    mockPlay.resign(match.id);
    const games = mockPlay.listMyGames();
    expect(games.some((g) => g.id === match.id)).toBe(true);
  });
});