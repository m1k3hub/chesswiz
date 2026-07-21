import { useAuth } from './AuthProvider';

/**
 * LoginButton — triggers the OIDC sign-in redirect when auth is enabled.
 *
 * Renders nothing when auth is disabled (the fallback avatar is shown by Header).
 */
export default function LoginButton() {
  const { isAuthenticated, isLoading, signinRedirect } = useAuth();

  if (isLoading) {
    return <button className="avatar" disabled>…</button>;
  }
  if (isAuthenticated) return null;

  return (
    <button
      className="avatar"
      title="Sign in"
      onClick={() => void signinRedirect()}
    >
      ⏵ Sign in
    </button>
  );
}