import { useEffect, useState } from 'react';
import { isAuthEnabled } from '@/config';
import { useAuth } from '@/features/auth/AuthProvider';
import LoginButton from '@/features/auth/LoginButton';
import LogoutButton from '@/features/auth/LogoutButton';

/**
 * Header — top navigation bar for the scidb-beta workspace.
 */
export default function Header() {
  const { isAuthenticated } = useAuth();
  const authEnabled = isAuthEnabled();
  const [theme, setTheme] = useState(() => {
    if (typeof document === 'undefined') return 'dark';
    return document.body.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
  });

  useEffect(() => {
    document.body.setAttribute('data-theme', theme);
    localStorage.setItem('scidb-beta.theme', theme);
  }, [theme]);

  useEffect(() => {
    const saved = localStorage.getItem('scidb-beta.theme');
    if (saved === 'light' || saved === 'dark') {
      setTheme(saved);
    }
  }, []);

  return (
    <header id="app-header">
      <div className="header-left">
        <span className="brand-mark">♞</span>
        <div>
          <h1>
            scidb<span>-beta</span>
          </h1>
          <small>chess database studio</small>
        </div>
      </div>
      <nav className="top-nav">
        <button className="top-nav-item active">Workspace</button>
        <button className="top-nav-item">Databases</button>
        <button className="top-nav-item">Reports</button>
      </nav>
      <div className="header-right">
        <span className="sync-status">
          <i></i> Local workspace
        </span>
        <button
          id="theme-toggle"
          className="btn-icon"
          title="Toggle dark/light"
          onClick={() => setTheme((t) => (t === 'light' ? 'dark' : 'light'))}
        >
          {theme === 'light' ? '☀️' : '☾'}
        </button>
        {authEnabled ? (
          isAuthenticated ? (
            <LogoutButton />
          ) : (
            <LoginButton />
          )
        ) : (
          <button className="avatar">MT</button>
        )}
      </div>
    </header>
  );
}
