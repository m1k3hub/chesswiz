/**
 * ShellFallback — lightweight loading indicator for lazy-loaded feature modals.
 *
 * Rendered by Suspense while a dynamic import is in flight. Kept intentionally
 * minimal (no external dependencies) so it does not pull extra modules into the
 * main chunk.
 */
export default function ShellFallback() {
  return (
    <div
      role="status"
      aria-label="Loading"
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '1rem',
        color: 'var(--text-dim, #8e949b)',
        fontSize: '13px',
      }}
    >
      <span className="shell-fallback-spinner" aria-hidden="true">
        ⟳
      </span>
      &nbsp;Loading…
    </div>
  );
}