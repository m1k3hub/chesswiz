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
