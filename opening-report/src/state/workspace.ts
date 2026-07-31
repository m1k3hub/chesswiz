import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { GameSummary, SavedWorkingSet, PlayMode, PlaySeek, PlayMatch, PlayMove } from '@/types';

export interface WorkspaceState {
  activeDatabaseId: string;
  activeGameId: string | null;
  activePanel: string;
  currentFen: string;
  pendingJobId: string | null;
  workingSet: GameSummary[];
  savedWorkingSets: SavedWorkingSet[];
  activeSearchJobId: string | null;
  activeEngineJobId: string | null;
  // Online play slice (Phase 0: mode flag + volatile fields).
  activePlayMode: PlayMode;
  activeMatchId: string | null;
  seeks: PlaySeek[];          // open seeks visible to the user
  mySeeks: PlaySeek[];        // this user's open seeks
  activeMatch: PlayMatch | null;
  activeMatchMoves: PlayMove[];   // synced move list for the active match
  connected: boolean;          // ws/play connection state
  pendingSeek: PlaySeek | null;
}

export interface WorkspaceActions {
  setActiveDatabaseId(id: string): void;
  setActiveGameId(id: string | null): void;
  setActivePanel(panel: string): void;
  setCurrentFen(fen: string): void;
  setPendingJobId(jobId: string | null): void;
  setWorkingSet(games: GameSummary[]): void;
  addWorkingSet(name: string): void;
  removeWorkingSet(id: string): void;
  renameWorkingSet(id: string, name: string): void;
  loadWorkingSet(id: string): void;
  setActiveSearchJobId(jobId: string | null): void;
  setActiveEngineJobId(jobId: string | null): void;
  setPlayMode(mode: PlayMode): void;
  setSeeks(seeks: PlaySeek[]): void;
  upsertSeek(seek: PlaySeek): void;
  removeSeek(id: string): void;
  setActiveMatch(match: PlayMatch | null): void;
  patchMatch(patch: Partial<PlayMatch>): void;
  appendActiveMatchMove(move: PlayMove): void;
  setActiveMatchMoves(moves: PlayMove[]): void;
  setPlayConnected(connected: boolean): void;
  reset(): void;
}

const STORAGE_KEY = 'scidb-beta.workspace';

const defaults: WorkspaceState = {
  activeDatabaseId: 'masters',
  activeGameId: null,
  activePanel: 'workspace',
  currentFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  pendingJobId: null,
  workingSet: [],
  savedWorkingSets: [],
  activeSearchJobId: null,
  activeEngineJobId: null,
  activePlayMode: 'analysis',
  activeMatchId: null,
  seeks: [],
  mySeeks: [],
  activeMatch: null,
  activeMatchMoves: [],
  connected: false,
  pendingSeek: null,
};

export const useWorkspaceStore = create<WorkspaceState & WorkspaceActions>()(
  persist(
    (set) => ({
      ...defaults,
      setActiveDatabaseId: (id) => set({ activeDatabaseId: id }),
      setActiveGameId: (id) => set({ activeGameId: id }),
      setActivePanel: (panel) => set({ activePanel: panel }),
      setCurrentFen: (fen) => set({ currentFen: fen }),
      setPendingJobId: (jobId) => set({ pendingJobId: jobId }),
      setWorkingSet: (games) => set({ workingSet: games }),
    addWorkingSet: (name) => set((state) => ({
      savedWorkingSets: [
        ...state.savedWorkingSets,
        {
          id: `ws-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
          name: name || `Working set ${state.savedWorkingSets.length + 1}`,
          games: state.workingSet,
        },
      ],
    })),
    removeWorkingSet: (id) => set((state) => ({
      savedWorkingSets: state.savedWorkingSets.filter((ws) => ws.id !== id),
    })),
    renameWorkingSet: (id, name) => set((state) => ({
      savedWorkingSets: state.savedWorkingSets.map((ws) =>
        ws.id === id ? { ...ws, name } : ws
      ),
    })),
    loadWorkingSet: (id) => {
      const ws = useWorkspaceStore.getState().savedWorkingSets.find((w) => w.id === id);
      if (ws) set({ workingSet: ws.games });
    },
      setActiveSearchJobId: (jobId) => set({ activeSearchJobId: jobId }),
      setActiveEngineJobId: (jobId) => set({ activeEngineJobId: jobId }),
      setPlayMode: (mode) => set({ activePlayMode: mode }),
      setSeeks: (seeks) => set({ seeks }),
      upsertSeek: (seek) => set((state) => {
        const exists = state.seeks.some((s) => s.id === seek.id);
        return { seeks: exists ? state.seeks.map((s) => (s.id === seek.id ? seek : s)) : [...state.seeks, seek] };
      }),
      removeSeek: (id) => set((state) => ({ seeks: state.seeks.filter((s) => s.id !== id) })),
      setActiveMatch: (match) => set({ activeMatch: match, activeMatchId: match?.id ?? null, activeMatchMoves: [] }),
      patchMatch: (patch) => set((state) => ({
        activeMatch: state.activeMatch ? { ...state.activeMatch, ...patch } : state.activeMatch,
      })),
      appendActiveMatchMove: (move) => set((state) => ({
        activeMatchMoves: [...state.activeMatchMoves, move],
      })),
      setActiveMatchMoves: (moves) => set({ activeMatchMoves: moves }),
      setPlayConnected: (connected) => set({ connected }),
      reset: () => set(defaults),
    }),
    {
      name: STORAGE_KEY,
      // Do not persist volatile play state (matches/seeks are session-only).
      // activePlayMode is persisted so a deliberate switch to play survives reload.
      partialize: (state) => ({
        activeDatabaseId: state.activeDatabaseId,
        activeGameId: state.activeGameId,
        activePanel: state.activePanel,
        currentFen: state.currentFen,
        pendingJobId: state.pendingJobId,
        workingSet: state.workingSet,
        savedWorkingSets: state.savedWorkingSets,
        activeSearchJobId: state.activeSearchJobId,
        activeEngineJobId: state.activeEngineJobId,
        activePlayMode: state.activePlayMode,
      }),
    }
  )
);

// Bridge for legacy vanilla JS modules that expect a global ScidbWorkspace object.
declare global {
  interface Window {
    ScidbWorkspace?: {
      getState: () => WorkspaceState;
      setState: (patch: Partial<WorkspaceState>) => WorkspaceState;
      setActiveDatabaseId: (id: string) => void;
      setActiveGameId: (id: string | null) => void;
      setActivePanel: (panel: string) => void;
      setCurrentFen: (fen: string) => void;
      setPendingJobId: (jobId: string | null) => void;
      setActiveSearchJobId: (jobId: string | null) => void;
      setActiveEngineJobId: (jobId: string | null) => void;
      getPlayMode: () => PlayMode;
      setPlayMode: (mode: PlayMode) => void;
      subscribe: (listener: (state: WorkspaceState) => void) => () => void;
      toast: (message: string, tone?: 'neutral' | 'accent' | 'warning' | 'success') => void;
      getWorkingSet: () => GameSummary[];
      setWorkingSet: (games: GameSummary[]) => void;
      addWorkingSet: (name: string) => void;
      removeWorkingSet: (id: string) => void;
      renameWorkingSet: (id: string, name: string) => void;
      loadWorkingSet: (id: string) => void;
      promoteWorkingSet: () => void;
    };
  }
}

let toastContainer: HTMLDivElement | null = null;

let toastTimer = 0;

function showToast(message: string, tone: 'neutral' | 'accent' | 'warning' | 'success' = 'neutral') {
  if (!toastContainer) {
    toastContainer = document.createElement('div');
    toastContainer.id = 'workspace-toast';
    document.body.appendChild(toastContainer);
  }
  toastContainer.dataset.tone = tone;
  toastContainer.textContent = message;
  toastContainer.classList.add('visible');
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toastContainer?.classList.remove('visible'), 2600);
}

export function installGlobalWorkspaceBridge() {
  window.ScidbWorkspace = {
    getState: () => useWorkspaceStore.getState(),
    setState: (patch) => {
      useWorkspaceStore.setState(patch);
      return useWorkspaceStore.getState();
    },
    setActiveDatabaseId: (id) => useWorkspaceStore.setState({ activeDatabaseId: id }),
    setActiveGameId: (id) => useWorkspaceStore.setState({ activeGameId: id }),
    setActivePanel: (panel) => useWorkspaceStore.setState({ activePanel: panel }),
    setCurrentFen: (fen) => useWorkspaceStore.setState({ currentFen: fen }),
    setPendingJobId: (jobId) => useWorkspaceStore.setState({ pendingJobId: jobId }),
    setActiveSearchJobId: (jobId) => useWorkspaceStore.setState({ activeSearchJobId: jobId }),
    setActiveEngineJobId: (jobId) => useWorkspaceStore.setState({ activeEngineJobId: jobId }),
    getPlayMode: () => useWorkspaceStore.getState().activePlayMode,
    setPlayMode: (mode) => useWorkspaceStore.setState({ activePlayMode: mode }),
    subscribe: (listener) => {
      listener(useWorkspaceStore.getState());
      return useWorkspaceStore.subscribe(listener);
    },
    toast: showToast,
    getWorkingSet: () => [...useWorkspaceStore.getState().workingSet],
    setWorkingSet: (games) => useWorkspaceStore.setState({ workingSet: games }),
    addWorkingSet: (name) => useWorkspaceStore.getState().addWorkingSet(name),
    removeWorkingSet: (id) => useWorkspaceStore.getState().removeWorkingSet(id),
    renameWorkingSet: (id, name) => useWorkspaceStore.getState().renameWorkingSet(id, name),
    loadWorkingSet: (id) => useWorkspaceStore.getState().loadWorkingSet(id),
    promoteWorkingSet: () => {
      const { workingSet } = useWorkspaceStore.getState();
      if (workingSet.length === 0) {
        showToast('Working set is empty — run a search first', 'accent');
        return;
      }
      useWorkspaceStore.setState({ activePanel: 'game-switcher' });
      showToast(`Promoted working set with ${workingSet.length} games`, 'accent');
    },
  };
}
