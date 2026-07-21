import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { createElement } from 'react';
import { isAuthEnabled, getOidcConfig } from '@/config';
import { AuthProvider, useAuth } from './AuthProvider';
import LoginButton from './LoginButton';

async function renderToDiv(element: ReturnType<typeof createElement>): Promise<{ container: HTMLDivElement; unmount: () => void }> {
  const container = document.createElement('div');
  document.body.appendChild(container);
  const root: Root = createRoot(container);
  await act(async () => {
    root.render(element);
  });
  // Flush any pending async effects from AuthProvider's useEffect.
  await act(async () => {});
  return {
    container,
    unmount: () => {
      act(() => root.unmount());
    },
  };
}

describe('auth config helpers', () => {
  beforeEach(() => {
    vi.resetModules();
  });

  it('isAuthEnabled returns false when VITE_ENABLE_AUTH is unset', () => {
    expect(isAuthEnabled()).toBe(false);
  });

  it('isAuthEnabled returns true when VITE_ENABLE_AUTH=1', () => {
    vi.stubEnv('VITE_ENABLE_AUTH', '1');
    expect(isAuthEnabled()).toBe(true);
    vi.unstubAllEnvs();
  });

  it('isAuthEnabled returns true when VITE_ENABLE_AUTH=true (case-insensitive)', () => {
    vi.stubEnv('VITE_ENABLE_AUTH', 'TRUE');
    expect(isAuthEnabled()).toBe(true);
    vi.unstubAllEnvs();
  });

  it('getOidcConfig returns null when auth is disabled', () => {
    expect(getOidcConfig()).toBeNull();
  });

  it('getOidcConfig returns config when all env vars are set', () => {
    vi.stubEnv('VITE_ENABLE_AUTH', '1');
    vi.stubEnv('VITE_OIDC_AUTHORITY', 'https://idp.example.com');
    vi.stubEnv('VITE_OIDC_CLIENT_ID', 'scidb-beta');
    vi.stubEnv('VITE_OIDC_REDIRECT_URI', 'https://app.example.com/auth/callback');

    const cfg = getOidcConfig();
    expect(cfg).not.toBeNull();
    expect(cfg!.authority).toBe('https://idp.example.com');
    expect(cfg!.clientId).toBe('scidb-beta');
    expect(cfg!.redirectUri).toBe('https://app.example.com/auth/callback');
    expect(cfg!.scope).toContain('openid');

    vi.unstubAllEnvs();
  });

  it('getOidcConfig returns null when authority is missing', () => {
    vi.stubEnv('VITE_ENABLE_AUTH', '1');
    vi.stubEnv('VITE_OIDC_CLIENT_ID', 'scidb-beta');
    // VITE_OIDC_AUTHORITY not set
    expect(getOidcConfig()).toBeNull();
    vi.unstubAllEnvs();
  });
});

describe('LoginButton', () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('renders sign-in button when unauthenticated', async () => {
    const { container, unmount } = await renderToDiv(
      createElement(AuthProvider, null, createElement(LoginButton))
    );
    const button = container.querySelector('button.avatar');
    expect(button).not.toBeNull();
    expect(button!.textContent).toContain('Sign in');
    unmount();
  });
});

describe('useAuth hook', () => {
  it('returns disabled context when auth is not enabled', async () => {
    let captured: { isAuthenticated: boolean; isLoading: boolean } | null = null;

    function Consumer() {
      const auth = useAuth();
      captured = { isAuthenticated: auth.isAuthenticated, isLoading: auth.isLoading };
      return null;
    }

    const { unmount } = await renderToDiv(
      createElement(AuthProvider, null, createElement(Consumer))
    );

    expect(captured).not.toBeNull();
    expect(captured!.isAuthenticated).toBe(false);
    expect(captured!.isLoading).toBe(false);
    unmount();
  });
});