import { describe, it, expect, beforeEach } from 'vitest';
import { useWorkspaceStore } from '@/state/workspace';
import type { GameSummary } from '@/types';

const mockGames: GameSummary[] = [
  {
    id: 'g-001',
    white: 'Carlsen, Magnus',
    whiteElo: 2855,
    black: 'Nepomniachtchi, Ian',
    blackElo: 2782,
    event: 'WCh 2021',
    site: 'Dubai UAE',
    date: '2021.12.03',
    result: '½–½',
    eco: 'A45',
  },
  {
    id: 'g-002',
    white: 'Kasparov, Garry',
    whiteElo: 2810,
    black: 'Karpov, Anatoly',
    blackElo: 2725,
    event: 'Linares',
    site: 'Linares ESP',
    date: '1993.03.02',
    result: '1-0',
    eco: 'D37',
  },
];

describe('Working sets', () => {
  beforeEach(() => {
    useWorkspaceStore.setState({
      ...useWorkspaceStore.getState(),
      workingSet: [],
      savedWorkingSets: [],
    });
  });

  it('starts with empty savedWorkingSets', () => {
    expect(useWorkspaceStore.getState().savedWorkingSets).toEqual([]);
  });

  it('addWorkingSet stores current working set with a name and id', () => {
    useWorkspaceStore.setState({ workingSet: mockGames });
    useWorkspaceStore.getState().addWorkingSet('Carlsen games');

    const sets = useWorkspaceStore.getState().savedWorkingSets;
    expect(sets).toHaveLength(1);
    expect(sets[0].name).toBe('Carlsen games');
    expect(sets[0].games).toEqual(mockGames);
    expect(sets[0].id).toBeTruthy();
  });

  it('addWorkingSet uses a default name when empty', () => {
    useWorkspaceStore.setState({ workingSet: mockGames });
    useWorkspaceStore.getState().addWorkingSet('');

    const sets = useWorkspaceStore.getState().savedWorkingSets;
    expect(sets[0].name).toBe('Working set 1');
  });

  it('addWorkingSet appends without removing existing sets', () => {
    useWorkspaceStore.setState({ workingSet: mockGames });
    useWorkspaceStore.getState().addWorkingSet('Set A');
    useWorkspaceStore.getState().addWorkingSet('Set B');

    expect(useWorkspaceStore.getState().savedWorkingSets).toHaveLength(2);
  });

  it('removeWorkingSet removes by id', () => {
    useWorkspaceStore.setState({ workingSet: mockGames });
    useWorkspaceStore.getState().addWorkingSet('To delete');
    const id = useWorkspaceStore.getState().savedWorkingSets[0].id;

    useWorkspaceStore.getState().removeWorkingSet(id);
    expect(useWorkspaceStore.getState().savedWorkingSets).toHaveLength(0);
  });

  it('renameWorkingSet updates the name', () => {
    useWorkspaceStore.setState({ workingSet: mockGames });
    useWorkspaceStore.getState().addWorkingSet('Old name');
    const id = useWorkspaceStore.getState().savedWorkingSets[0].id;

    useWorkspaceStore.getState().renameWorkingSet(id, 'New name');
    expect(useWorkspaceStore.getState().savedWorkingSets[0].name).toBe('New name');
  });

  it('loadWorkingSet replaces current workingSet with saved games', () => {
    useWorkspaceStore.setState({ workingSet: mockGames });
    useWorkspaceStore.getState().addWorkingSet('Saved');
    const id = useWorkspaceStore.getState().savedWorkingSets[0].id;

    useWorkspaceStore.setState({ workingSet: [] });
    expect(useWorkspaceStore.getState().workingSet).toEqual([]);

    useWorkspaceStore.getState().loadWorkingSet(id);
    expect(useWorkspaceStore.getState().workingSet).toEqual(mockGames);
  });

  it('loadWorkingSet does nothing for unknown id', () => {
    useWorkspaceStore.setState({ workingSet: mockGames });
    useWorkspaceStore.getState().loadWorkingSet('nonexistent');
    expect(useWorkspaceStore.getState().workingSet).toEqual(mockGames);
  });

  it('persists savedWorkingSets in the store state', () => {
    useWorkspaceStore.setState({ workingSet: mockGames });
    useWorkspaceStore.getState().addWorkingSet('Persisted');
    const state = useWorkspaceStore.getState();
    expect(state.savedWorkingSets).toHaveLength(1);
    expect(state.savedWorkingSets[0].games).toHaveLength(2);
  });
});