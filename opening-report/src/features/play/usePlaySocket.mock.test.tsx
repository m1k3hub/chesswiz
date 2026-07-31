import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { createElement } from 'react';
import { usePlaySocket } from './usePlaySocket';
import { mockPlay, __resetMockPlay } from './mockPlayBackend';
import { useWorkspaceStore } from '@/state/workspace';
import type { PlaySeek, PlayUser, PlayMatch, PlayMove } from '@/types';

const userA: PlayUser = { id: 'userA', name: 'Alice', rating: 1500 };
const userB: PlayUser = { id: 'userB', name: 'Bob', rating: 1500 };

let currentRoot: Root | null = null;

function mountSocket() {
  const container = document.createElement('div');
  document.body.appendChild(container);
  const root = createRoot(container);
  currentRoot = root;
  act(() => {
    root.render(createElement(() => {
      usePlaySocket();
      return null;
    }));
  });
  act(() => {});
}

afterEach(() => {
  const root = currentRoot;
  if (root) act(() => { root.unmount(); });
  currentRoot = null;
  document.body.innerHTML = '';
});

function foreignSeek(id: string, owner: PlayUser, color: 'w' | 'b' = 'w'): PlaySeek {
  return {
    id, owner,
    timeControl: { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2 },
    variant: 'standard', rated: false, color, ratingRange: null, createdAt: Date.now(),
  };
}

describe('usePlaySocket (Phase 2 mock event stream)', () => {
  beforeEach(() => {
    __resetMockPlay();
    mockPlay.__setMe(userA);
    useWorkspaceStore.getState().setActiveMatch(null);
    useWorkspaceStore.getState().setActiveMatchMoves([]);
    useWorkspaceStore.getState().setSeeks([]);
  });

  it('marks connected and reflects open seeks on mount', () => {
    mockPlay.__injectSeek(foreignSeek('s1', userB));
    mountSocket();
    expect(useWorkspaceStore.getState().connected).toBe(true);
    expect(useWorkspaceStore.getState().seeks.some((s) => s.id === 's1')).toBe(true);
  });

  it('sets activeMatch on match.paired for the local user', () => {
    mockPlay.__injectSeek(foreignSeek('s1', userB, 'w')); // userB white, me black
    mountSocket();
    mockPlay.acceptSeek('s1');
    const store = useWorkspaceStore.getState();
    expect(store.activeMatchId).toBeTruthy();
    expect(store.activeMatch?.white.id).toBe('userB');
    expect(store.activeMatch?.black.id).toBe('userA');
  });

  it('appends moves and patches the match on match.move for the active match', () => {
    mockPlay.__injectSeek(foreignSeek('s1', userB, 'w'));
    mountSocket();
    mockPlay.acceptSeek('s1');
    const matchId = useWorkspaceStore.getState().activeMatchId!;

    const move: PlayMove = {
      ply: 1, san: 'e4', uci: 'e2e4',
      fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
      clockMsAfter: 178000, latencyMs: 5,
    };
    act(() => {
      mockPlay.__emit({ type: 'match.move', matchId, move, clocks: { whiteMs: 178000, blackMs: 180000 }, clockUpdatedAt: Date.now() });
    });
    act(() => {});
    const store = useWorkspaceStore.getState();
    expect(store.activeMatchMoves).toHaveLength(1);
    expect(store.activeMatchMoves[0].uci).toBe('e2e4');
    expect(store.activeMatch?.ply).toBe(1);
  });

  it('patches finish and result on match.finish', () => {
    mockPlay.__injectSeek(foreignSeek('s1', userB, 'w'));
    mountSocket();
    mockPlay.acceptSeek('s1');
    const matchId = useWorkspaceStore.getState().activeMatchId!;
    act(() => {
      mockPlay.__emit({ type: 'match.finish', matchId, result: { kind: 'resign', winner: 'b' }, clocks: { whiteMs: 120000, blackMs: 90000 } });
    });
    act(() => {});
    const store = useWorkspaceStore.getState();
    expect(store.activeMatch?.status).toBe('finished');
    expect(store.activeMatch?.result).toEqual({ kind: 'resign', winner: 'b' });
  });

  it('ignores events for matches it is not part of', () => {
    mountSocket();
    const other: PlayMatch = {
      id: 'other', variant: 'standard',
      timeControl: { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2 },
      rated: false, white: userB, black: { id: 'userC', name: 'Carol', rating: 1500 },
      startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      ply: 0, status: 'playing', result: null,
      clocks: { whiteMs: 180000, blackMs: 180000 }, clockUpdatedAt: Date.now(),
      drawOfferSide: null, rematchOfferSide: null,
    };
    act(() => { mockPlay.__emit({ type: 'match.paired', match: other }); });
    act(() => {});
    expect(useWorkspaceStore.getState().activeMatchId).toBeNull();
  });
});