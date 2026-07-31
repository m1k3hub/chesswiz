import { describe, it, expect } from 'vitest';
import { useWorkspaceStore, installGlobalWorkspaceBridge } from './workspace';

describe('Workspace state', () => {
  it('has default active database and game', () => {
    const state = useWorkspaceStore.getState();
    expect(state.activeDatabaseId).toBe('masters');
    expect(state.activeGameId).toBeNull();
  });

  it('updates active game', () => {
    useWorkspaceStore.setState({ activeGameId: 'g-001' });
    expect(useWorkspaceStore.getState().activeGameId).toBe('g-001');
  });

  it('exposes a global bridge', () => {
    installGlobalWorkspaceBridge();
    expect(window.ScidbWorkspace).toBeDefined();
    window.ScidbWorkspace?.setActiveDatabaseId('repertoire');
    expect(useWorkspaceStore.getState().activeDatabaseId).toBe('repertoire');
  });
});

describe('Play mode (Phase 0)', () => {
  it('defaults to analysis mode', () => {
    expect(useWorkspaceStore.getState().activePlayMode).toBe('analysis');
    expect(useWorkspaceStore.getState().activeMatch).toBeNull();
    expect(useWorkspaceStore.getState().seeks).toEqual([]);
    expect(useWorkspaceStore.getState().connected).toBe(false);
  });

  it('switches to play mode via setPlayMode', () => {
    useWorkspaceStore.getState().setPlayMode('play');
    expect(useWorkspaceStore.getState().activePlayMode).toBe('play');
    useWorkspaceStore.getState().setPlayMode('analysis');
    expect(useWorkspaceStore.getState().activePlayMode).toBe('analysis');
  });

  it('upserts and removes seeks', () => {
    const seek = {
      id: 's1',
      owner: { id: 'u1', name: 'Alice', rating: 1500 },
      timeControl: { kind: 'blitz' as const, baseSeconds: 180, incrementSeconds: 2 },
      variant: 'standard' as const,
      rated: false,
      color: 'w' as const,
      ratingRange: null,
      createdAt: Date.now(),
    };
    useWorkspaceStore.getState().upsertSeek(seek);
    expect(useWorkspaceStore.getState().seeks).toHaveLength(1);
    // upsert replaces by id
    useWorkspaceStore.getState().upsertSeek({ ...seek, rated: true });
    expect(useWorkspaceStore.getState().seeks).toHaveLength(1);
    expect(useWorkspaceStore.getState().seeks[0].rated).toBe(true);
    useWorkspaceStore.getState().removeSeek('s1');
    expect(useWorkspaceStore.getState().seeks).toHaveLength(0);
  });

  it('setActiveMatch sets both activeMatch and activeMatchId', () => {
    const match = {
      id: 'm1',
      variant: 'standard' as const,
      timeControl: { kind: 'blitz' as const, baseSeconds: 180, incrementSeconds: 2 },
      rated: false,
      white: { id: 'u1', name: 'Alice', rating: 1500 },
      black: { id: 'u2', name: 'Bob', rating: 1500 },
      startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      ply: 0,
      status: 'playing' as const,
      result: null,
      clocks: { whiteMs: 180000, blackMs: 180000 },
      clockUpdatedAt: Date.now(),
      drawOfferSide: null,
      rematchOfferSide: null,
    };
    useWorkspaceStore.getState().setActiveMatch(match);
    expect(useWorkspaceStore.getState().activeMatchId).toBe('m1');
    useWorkspaceStore.getState().patchMatch({ ply: 1 });
    expect(useWorkspaceStore.getState().activeMatch?.ply).toBe(1);
    useWorkspaceStore.getState().setActiveMatch(null);
    expect(useWorkspaceStore.getState().activeMatch).toBeNull();
    expect(useWorkspaceStore.getState().activeMatchId).toBeNull();
  });

  it('exposes play mode through the global bridge', () => {
    installGlobalWorkspaceBridge();
    window.ScidbWorkspace?.setPlayMode('play');
    expect(window.ScidbWorkspace?.getPlayMode()).toBe('play');
    window.ScidbWorkspace?.setPlayMode('analysis');
    expect(window.ScidbWorkspace?.getPlayMode()).toBe('analysis');
  });
});
