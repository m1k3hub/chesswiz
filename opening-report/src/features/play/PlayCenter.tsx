import { useEffect, useState, lazy, Suspense } from 'react';
import { useWorkspaceStore } from '@/state/workspace';
import ShellFallback from '@/components/ShellFallback';
import { usePlaySocket } from './usePlaySocket';

const SeekLobby = lazy(() => import('./SeekLobby'));
const PlayBoardPanel = lazy(() => import('./PlayBoardPanel'));

/**
 * PlayCenter — online-play workspace entry point.
 *
 * Opens via the `scidb:open-play` custom event (Header "Play" nav). Phase 2
 * ships a mock-backed lobby + live board: create/accept seeks (synced across
 * tabs via the mock backend), play a full game with server-authoritative
 * clocks, resign, and review finished games. The live server arrives in
 * Phase 3+; the slice contract is identical, so only the transport changes.
 */
export default function PlayCenter() {
  const [isOpen, setIsOpen] = useState(false);
  const activePlayMode = useWorkspaceStore((s) => s.activePlayMode);
  const setPlayMode = useWorkspaceStore((s) => s.setPlayMode);
  const activeMatch = useWorkspaceStore((s) => s.activeMatch);
  const connected = useWorkspaceStore((s) => s.connected);

  // Wire the (mock) event stream into the play slice while Play is mounted.
  usePlaySocket();

  useEffect(() => {
    const handleOpen = () => {
      setIsOpen(true);
      setPlayMode('play');
    };
    window.addEventListener('scidb:open-play', handleOpen);
    return () => window.removeEventListener('scidb:open-play', handleOpen);
  }, [setPlayMode]);

  if (!isOpen) return null;

  const close = () => setIsOpen(false);

  return (
    <div
      id="play-center"
      className="modal"
      style={{ display: 'flex' }}
      onClick={(e) => {
        if (e.target === e.currentTarget) close();
      }}
    >
      <div className="modal-content play-center-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">PLAY</span>
            <h3>Online play</h3>
          </div>
          <button className="modal-close" onClick={close}>✕</button>
        </div>

        <div className="play-toolbar">
          <button
            className="ghost-btn"
            onClick={() => setPlayMode('analysis')}
            disabled={activePlayMode === 'analysis'}
            title="Board returns to free analysis behaviour"
          >
            Analysis mode
          </button>
          <button
            className="ghost-btn"
            onClick={() => setPlayMode('play')}
            disabled={activePlayMode === 'play'}
            title="Board enforces play rules: legal-only, no takeback"
          >
            Play mode
          </button>
          <span className="play-mode-indicator">
            <i className={connected ? 'dot dot-on' : 'dot dot-off'} /> Board mode: <code>{activePlayMode}</code>
          </span>
        </div>

        <Suspense fallback={<ShellFallback />}>
          {activeMatch ? <PlayBoardPanel /> : <SeekLobby />}
        </Suspense>

        <p className="play-footnote">
          Phase 2: mock backend (in-browser, synced across tabs). Live server,
          ratings, and offers arrive in later phases.
        </p>
      </div>
    </div>
  );
}