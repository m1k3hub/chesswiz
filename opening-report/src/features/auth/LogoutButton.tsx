import { useAuth } from './AuthProvider';

/**
 * LogoutButton — triggers the OIDC sign-out redirect when auth is enabled.
 *
 * Renders nothing when the user is not authenticated.
 */
export default function LogoutButton() {
  const { isAuthenticated, user, signoutRedirect } = useAuth();

  if (!isAuthenticated) return null;

  const initials = (user?.profile?.name || user?.profile?.email || 'U')
    .slice(0, 2)
    .toUpperCase();

  return (
    <button
      className="avatar"
      title={`Signed in as ${user?.profile?.name || user?.profile?.email || 'user'} — click to sign out`}
      onClick={() => void signoutRedirect()}
    >
      {initials}
    </button>
  );
}