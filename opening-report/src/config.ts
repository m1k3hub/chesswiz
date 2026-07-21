/**
 * Environment-aware configuration for the scidb-beta web frontend.
 *
 * Reads Vite env vars at build/dev time and exposes typed accessors.
 * Auth is opt-in: set VITE_ENABLE_AUTH=1 (or "true") to activate OIDC.
 */

export interface OidcConfig {
  authority: string;
  clientId: string;
  redirectUri: string;
  scope: string;
}

const ENABLED_VALUES = new Set(['1', 'true', 'yes', 'on']);

/**
 * Returns true when OIDC auth is enabled via the VITE_ENABLE_AUTH env var.
 */
export function isAuthEnabled(): boolean {
  const raw = import.meta.env?.VITE_ENABLE_AUTH;
  if (!raw) return false;
  return ENABLED_VALUES.has(String(raw).toLowerCase());
}

/**
 * Returns the OIDC configuration or null when auth is disabled / misconfigured.
 */
export function getOidcConfig(): OidcConfig | null {
  if (!isAuthEnabled()) return null;

  const authority = import.meta.env?.VITE_OIDC_AUTHORITY;
  const clientId = import.meta.env?.VITE_OIDC_CLIENT_ID;
  const redirectUri =
    import.meta.env?.VITE_OIDC_REDIRECT_URI ||
    (typeof window !== 'undefined' ? `${window.location.origin}/auth/callback` : '');

  if (!authority || !clientId) {
    console.warn(
      '[scidb-beta] Auth is enabled but VITE_OIDC_AUTHORITY or VITE_OIDC_CLIENT_ID is missing. ' +
        'Falling back to disabled auth.'
    );
    return null;
  }

  return {
    authority,
    clientId,
    redirectUri,
    scope: 'openid profile email',
  };
}

/**
 * Returns the API base URL from env or default.
 */
export function getApiBaseUrl(): string {
  return (
    import.meta.env?.VITE_SCIDB_API_BASE ||
    (typeof window !== 'undefined' ? window.SCIDB_API_BASE || '/api' : '/api')
  );
}