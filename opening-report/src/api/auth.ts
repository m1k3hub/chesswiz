/**
 * Bearer-token interceptor for the API client.
 *
 * Provides a mutable token store that the AuthProvider updates when the user
 * signs in/out. The `authHeaders()` helper merges an Authorization header into
 * any existing headers so that `httpRequest` includes it automatically.
 *
 * The `ensureFreshToken()` helper checks token expiry and triggers a silent
 * refresh via the UserManager before each API request.
 */

import type { UserManager, User } from 'oidc-client-ts';

let accessToken: string | null = null;
let tokenExpiresAt = 0; // epoch ms
let userManager: UserManager | null = null;
let refreshPromise: Promise<string | null> | null = null;

/** Buffer (ms) — refresh the token if it expires within this window. */
const REFRESH_BUFFER_MS = 60_000; // 1 minute

/**
 * Set the current access token (called by AuthProvider on sign-in).
 */
export function setAccessToken(token: string | null, expiresAt?: number): void {
  accessToken = token;
  tokenExpiresAt = expiresAt ?? 0;
}

/**
 * Get the current access token (for testing or manual use).
 */
export function getAccessToken(): string | null {
  return accessToken;
}

/**
 * Register the UserManager so `ensureFreshToken` can trigger silent refresh.
 */
export function setUserManager(mgr: UserManager | null): void {
  userManager = mgr;
}

/**
 * Returns true if the current token will expire within REFRESH_BUFFER_MS.
 */
export function isTokenExpiringSoon(): boolean {
  if (!accessToken || !tokenExpiresAt) return false;
  return Date.now() + REFRESH_BUFFER_MS >= tokenExpiresAt;
}

/**
 * Ensure the access token is fresh. If it's about to expire and a
 * UserManager is registered, this triggers a silent refresh (signinSilent)
 * and updates the stored token. Returns the current (possibly refreshed) token.
 *
 * This is called before each HTTP request by the API client.
 */
export async function ensureFreshToken(): Promise<string | null> {
  if (!isTokenExpiringSoon() || !userManager) {
    return accessToken;
  }

  // Coalesce concurrent refresh calls
  if (refreshPromise) {
    return refreshPromise;
  }

  refreshPromise = (async () => {
    try {
      const user: User | null = await userManager!.signinSilent();
      if (user) {
        setAccessToken(user.access_token, (user.expires_at ?? 0) * 1000);
      }
      return accessToken;
    } catch (err) {
      console.warn('[scidb-beta] Silent token refresh failed:', err);
      return accessToken;
    } finally {
      refreshPromise = null;
    }
  })();

  return refreshPromise;
}

/**
 * Returns headers with an Authorization Bearer token appended when available.
 * Also ensures the token is fresh before attaching it.
 */
export async function authHeaders(extra?: Record<string, string>): Promise<Record<string, string>> {
  await ensureFreshToken();
  const headers: Record<string, string> = { ...(extra || {}) };
  if (accessToken) {
    headers['Authorization'] = `Bearer ${accessToken}`;
  }
  return headers;
}