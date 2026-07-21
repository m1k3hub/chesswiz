/** Vite client types */
/// <reference types="vite/client" />

/** React act() environment flag for test setup. */
// eslint-disable-next-line no-var
declare var IS_REACT_ACT_ENVIRONMENT: boolean;

interface ImportMetaEnv {
  readonly VITE_SCIDB_API_BASE?: string;
  readonly VITE_OIDC_AUTHORITY?: string;
  readonly VITE_OIDC_CLIENT_ID?: string;
  readonly VITE_OIDC_REDIRECT_URI?: string;
  readonly VITE_ENABLE_AUTH?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}