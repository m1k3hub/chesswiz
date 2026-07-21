/**
 * workspace.e2e.test.tsx — Vitest + jsdom end-to-end test.
 *
 * Renders the Shell component and verifies that clicking the database rail
 * buttons dispatches the correct custom events. This test does NOT use
 * Playwright — it runs entirely in jsdom via Vitest.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';

// Mock the API client so no network calls happen.
vi.mock('@/api/client', () => ({
  createApiClient: () => ({
    listDatabases: vi.fn().mockResolvedValue([
      { id: 'masters', name: 'Master Games', format: 'SCI', games: 100, readOnly: true },
    ]),
    getEngines: vi.fn().mockResolvedValue([]),
    getWorkspace: vi.fn().mockResolvedValue({}),
  }),
}));

// Mock BoardPanel and ReportPanel to avoid complex board/engine dependencies.
vi.mock('@/components/BoardPanel', () => ({ default: () => null }));
vi.mock('@/components/ReportPanel', () => ({ default: () => null }));
vi.mock('@/components/ShellFallback', () => ({ default: () => null }));

// Mock the auth provider to avoid OIDC initialization in jsdom.
vi.mock('@/features/auth/AuthProvider', () => ({
  AuthProvider: ({ children }: { children: React.ReactNode }) => children,
  useAuth: () => ({ user: null, isAuthenticated: false, isLoading: false, signinRedirect: async () => {}, signoutRedirect: async () => {}, signinCallback: async () => {} }),
}));

// Mock auth buttons.
vi.mock('@/features/auth/LoginButton', () => ({ default: () => null }));
vi.mock('@/features/auth/LogoutButton', () => ({ default: () => null }));

// Mock config to disable auth.
vi.mock('@/config', () => ({ isAuthEnabled: () => false, getOidcConfig: () => null }));

// Mock all lazy-loaded modal components so Shell renders without dynamic imports.
vi.mock('@/features/database/DatabaseModal', () => ({ default: () => null }));
vi.mock('@/features/games/GameSwitcherModal', () => ({ default: () => null }));
vi.mock('@/features/search/SearchCenterModal', () => ({ default: () => null }));
vi.mock('@/features/tree/OpeningTreeModal', () => ({ default: () => null }));
vi.mock('@/features/working-sets/WorkingSetsModal', () => ({ default: () => null }));
vi.mock('@/features/indexes/IndexBrowserModal', () => ({ default: () => null }));
vi.mock('@/features/repertoire/RepertoireStudio', () => ({ default: () => null }));
vi.mock('@/features/players/PlayerCenter', () => ({ default: () => null }));
vi.mock('@/features/maintenance/MaintenanceCenter', () => ({ default: () => null }));
vi.mock('@/features/crosstable/CrosstableModal', () => ({ default: () => null }));
vi.mock('@/features/games/GameEditorModal', () => ({ default: () => null }));
vi.mock('@/features/tactics/TacticsModal', () => ({ default: () => null }));
vi.mock('@/features/games/GameViewerModal', () => ({ default: () => null }));
vi.mock('@/features/jobs/JobCenter', () => ({ default: () => null }));

import Shell from '@/components/Shell';
import { installGlobalWorkspaceBridge } from '@/state/workspace';

// Install the global workspace bridge so DatabaseRail's toast calls work.
installGlobalWorkspaceBridge();

/** Rail button label → expected custom event name. */
const RAIL_EVENT_MAP: Record<string, string> = {
  'My databases': 'scidb:open-database-manager',
  'Search games': 'scidb:open-game-switcher',
  'Search center': 'scidb:open-search-center',
  'Opening explorer': 'scidb:open-opening-tree',
  'Job center': 'scidb:open-job-center',
  'Working sets': 'scidb:open-working-sets',
  'Maintenance': 'scidb:open-maintenance',
  'Crosstable': 'scidb:open-crosstable',
  'Index browser': 'scidb:open-index-browser',
  'Repertoire': 'scidb:open-repertoire-studio',
  'Player center': 'scidb:open-player-center',
};

function findButtonByText(container: HTMLElement, text: string): HTMLButtonElement | null {
  const buttons = container.querySelectorAll('button.rail-item');
  for (const btn of buttons) {
    if (btn.textContent && btn.textContent.includes(text)) {
      return btn as HTMLButtonElement;
    }
  }
  return null;
}

describe('Shell workspace e2e (jsdom)', () => {
  let container: HTMLDivElement;
  let root: Root;

  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(() => {
    act(() => {
      root.unmount();
    });
    if (container.parentNode) {
      container.parentNode.removeChild(container);
    }
  });

  /** Render Shell and flush all pending async effects (DatabaseRail API call, etc.). */
  async function renderShell() {
    await act(async () => {
      root.render(<Shell />);
    });
    // Flush the async useEffect from DatabaseRail (listDatabases promise).
    await act(async () => {});
  }

  it('renders the header and main layout', async () => {
    await renderShell();

    const header = container.querySelector('#app-header');
    expect(header).toBeTruthy();

    const layout = container.querySelector('#main-layout');
    expect(layout).toBeTruthy();

    const rail = container.querySelector('.side-rail');
    expect(rail).toBeTruthy();
  });

  it('renders all expected rail buttons', async () => {
    await renderShell();

    for (const label of Object.keys(RAIL_EVENT_MAP)) {
      const btn = findButtonByText(container, label);
      expect(btn, `Expected rail button "${label}" to be rendered`).toBeTruthy();
    }
  });

  // Test each rail button individually to keep tests focused.
  for (const [label, expectedEvent] of Object.entries(RAIL_EVENT_MAP)) {
    it(`clicking "${label}" dispatches ${expectedEvent}`, async () => {
      let received = false;
      const handler = () => { received = true; };
      window.addEventListener(expectedEvent, handler);

      await renderShell();

      const btn = findButtonByText(container, label);
      expect(btn).toBeTruthy();

      act(() => {
        btn!.click();
      });

      expect(received, `Expected ${expectedEvent} to fire when clicking "${label}"`).toBe(true);
      window.removeEventListener(expectedEvent, handler);
    });
  }

  it('clicking "Reports" does not dispatch a custom event (toast only)', async () => {
    const events = ['scidb:open-database-manager', 'scidb:open-game-switcher'];
    const seen: string[] = [];
    const handlers = events.map((evt) => {
      const h = () => { seen.push(evt); };
      window.addEventListener(evt, h);
      return { evt, h };
    });

    await renderShell();

    const btn = findButtonByText(container, 'Reports');
    expect(btn).toBeTruthy();

    act(() => {
      btn!.click();
    });

    expect(seen.length).toBe(0);
    handlers.forEach(({ evt, h }) => window.removeEventListener(evt, h));
  });
});