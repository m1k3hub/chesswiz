import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import Callback from './features/auth/Callback';
import { AuthProvider } from './features/auth/AuthProvider';
import { installGlobalWorkspaceBridge } from './state/workspace';
import { createApiClient } from './api/client';
import './index.css';

// Global configuration for legacy vanilla JS modules.
declare global {
  interface Window {
    SCIDB_CONFIG?: { apiBaseUrl?: string };
    SCIDB_API_BASE?: string;
    ScidbApi?: ReturnType<typeof createApiClient>;
  }
}

window.SCIDB_CONFIG = { apiBaseUrl: window.SCIDB_API_BASE || '/api' };
window.ScidbApi = createApiClient();

installGlobalWorkspaceBridge();

// Detect the OIDC callback route (/auth/callback) and render the Callback
// component instead of the full workspace App.
const isCallbackRoute =
  typeof window !== 'undefined' &&
  (window.location.pathname === '/auth/callback' || window.location.pathname === '/callback');

const rootElement = document.getElementById('root');
if (rootElement) {
  createRoot(rootElement).render(
    <StrictMode>
      <AuthProvider>
        {isCallbackRoute ? <Callback /> : <App />}
      </AuthProvider>
    </StrictMode>
  );
}