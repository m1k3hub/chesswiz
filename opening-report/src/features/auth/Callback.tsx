import { useEffect, useState, type ReactNode } from 'react';
import { useAuth } from './AuthProvider';

/**
 * Callback — handles the OIDC signinRedirectCallback on the /auth/callback route.
 *
 * Renders a minimal loading spinner while the AuthProvider processes the
 * callback. On success the user is redirected to "/". On error an error
 * message is shown with a retry link.
 */
export default function Callback() {
  const { signinCallback, signinRedirect } = useAuth();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    signinCallback()
      .then(() => {
        if (!cancelled) {
          window.location.href = '/';
        }
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        const msg = err instanceof Error ? err.message : String(err);
        console.error('[scidb-beta] OIDC callback failed:', msg);
        setError(msg);
      });

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (error) {
    return (
      <div style={{ display: 'grid', placeItems: 'center', height: '100vh', gap: '16px' }}>
        <h2>Sign-in failed</h2>
        <p style={{ color: 'var(--accent-red, #f87171)' }}>{error}</p>
        <button className="primary-btn" onClick={() => void signinRedirect()}>
          Retry sign-in
        </button>
        <a href="/">Back to workspace</a>
      </div>
    );
  }

  return (
    <div style={{ display: 'grid', placeItems: 'center', height: '100vh', gap: '12px' }}>
      <Spinner />
      <p>Completing sign-in…</p>
    </div>
  );
}

function Spinner(): ReactNode {
  return (
    <div
      style={{
        width: '32px',
        height: '32px',
        border: '3px solid var(--border, #333)',
        borderTopColor: 'var(--accent, #e94560)',
        borderRadius: '50%',
        animation: 'spin 0.8s linear infinite',
      }}
    />
  );
}