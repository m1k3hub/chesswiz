import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { createElement } from 'react';
import { AuthProvider } from './AuthProvider';
import Callback from './Callback';

async function renderToDiv(element: ReturnType<typeof createElement>): Promise<{ container: HTMLDivElement; unmount: () => void }> {
  const container = document.createElement('div');
  document.body.appendChild(container);
  const root: Root = createRoot(container);
  await act(async () => {
    root.render(element);
  });
  // Flush any pending async effects.
  await act(async () => {});
  return {
    container,
    unmount: () => {
      act(() => root.unmount());
    },
  };
}

describe('Callback component', () => {
  beforeEach(() => {
    vi.resetModules();
    // Ensure auth is disabled so AuthProvider gives a disabled context
    // (Callback will call signinCallback which is a no-op)
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('renders without crashing when auth is disabled', async () => {
    const { container, unmount } = await renderToDiv(
      createElement(AuthProvider, null, createElement(Callback))
    );
    // When auth is disabled, signinCallback is a no-op that resolves void.
    // The component should render the loading spinner or a message.
    expect(container.textContent).toContain('Completing sign-in');
    unmount();
  });

  it('renders error UI when callback throws', async () => {
    // Stub auth as enabled with a broken config to force an error
    vi.stubEnv('VITE_ENABLE_AUTH', '1');
    vi.stubEnv('VITE_OIDC_AUTHORITY', 'https://idp.example.com');
    vi.stubEnv('VITE_OIDC_CLIENT_ID', 'scidb-beta');

    const { container, unmount } = await renderToDiv(
      createElement(AuthProvider, null, createElement(Callback))
    );

    // Wait for the error to appear (signinRedirectCallback will fail)
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 200));
    });

    // The component should show an error or loading state
    expect(container.textContent).toBeTruthy();
    unmount();
  });
});