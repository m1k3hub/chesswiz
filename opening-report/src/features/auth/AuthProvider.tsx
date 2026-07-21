import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { UserManager, type User } from 'oidc-client-ts';
import { getOidcConfig, isAuthEnabled } from '@/config';
import { setAccessToken, setUserManager } from '@/api/auth';

export interface AuthContextValue {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  signinRedirect: () => Promise<void>;
  signoutRedirect: () => Promise<void>;
  signinCallback: () => Promise<User | void>;
}

const AuthDisabledContext: AuthContextValue = {
  user: null,
  isAuthenticated: false,
  isLoading: false,
  signinRedirect: async () => {},
  signoutRedirect: async () => {},
  signinCallback: async () => {},
};

const AuthContext = createContext<AuthContextValue>(AuthDisabledContext);

/**
 * AuthProvider wraps the application with OIDC authentication via oidc-client-ts.
 *
 * When auth is disabled (VITE_ENABLE_AUTH not set), the provider is a pass-through
 * that exposes no-op auth methods so the rest of the app can call useAuth()
 * unconditionally.
 */
export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(isAuthEnabled());

  const userManager = useMemo<UserManager | null>(() => {
    const cfg = getOidcConfig();
    if (!cfg) return null;
    const mgr = new UserManager({
      authority: cfg.authority,
      client_id: cfg.clientId,
      redirect_uri: cfg.redirectUri,
      scope: cfg.scope,
    });
    // Register the manager so auth.ts can trigger silent refresh
    setUserManager(mgr);
    return mgr;
  }, []);

  useEffect(() => {
    if (!userManager) {
      setIsLoading(false);
      return;
    }

    let cancelled = false;

    // Handle the OIDC redirect callback if present.
    userManager
      .signinRedirectCallback()
      .then((u) => {
        if (cancelled) return;
        setUser(u);
        setAccessToken(u.access_token, (u.expires_at ?? 0) * 1000);
        setIsLoading(false);
      })
      .catch(() => {
        // Not on the callback route — check for existing user.
        userManager
          .getUser()
          .then((u) => {
            if (cancelled) return;
            if (u && !u.expired) {
              setUser(u);
              setAccessToken(u.access_token, (u.expires_at ?? 0) * 1000);
            }
          })
          .catch(() => { /* user lookup failed; stay unauthenticated */ })
          .finally(() => {
            if (!cancelled) setIsLoading(false);
          });
      });

    return () => {
      cancelled = true;
    };
  }, [userManager]);

  const value = useMemo<AuthContextValue>(() => {
    if (!userManager) return AuthDisabledContext;

    return {
      user,
      isAuthenticated: !!user && !user.expired,
      isLoading,
      signinRedirect: () => userManager.signinRedirect(),
      signoutRedirect: () => userManager.signoutRedirect(),
      signinCallback: () => userManager.signinRedirectCallback() as Promise<User | void>,
    };
  }, [user, isLoading, userManager]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

/**
 * useAuth — access the current auth context.
 *
 * Returns a no-op context when auth is disabled so callers don't need to
 * branch on whether OIDC is configured.
 */
// eslint-disable-next-line react-refresh/only-export-components
export function useAuth(): AuthContextValue {
  return useContext(AuthContext);
}