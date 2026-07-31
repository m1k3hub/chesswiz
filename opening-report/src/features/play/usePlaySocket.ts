import { useEffect } from 'react';
import { useWorkspaceStore } from '@/state/workspace';
import { mockPlay } from './mockPlayBackend';
import { createApiClient } from '@/api/client';
import { getSharedPlaySocket } from './playSocket';

const api = createApiClient();

/**
 * usePlaySocket — Phase 2 mock event stream.
 *
 * Subscribes to the mock play backend and mirrors seeks, the active match,
 * and synced moves into the workspace play slice. In Phase 4 this will
 * subscribe to the real `/api/ws/play` WebSocket and apply the same PlayEvent
 * union; the slice contract stays identical, so only the transport changes.
 *
 * The board (PlayBoardPanel) reacts to `activeMatchMoves` to apply opponent
 * moves via `ChessBoardHandle.applyExternalMove`.
 */
export function usePlaySocket(): void {
  useEffect(() => {
    let cancelled = false;

    const refreshSeeks = () => {
      if (cancelled) return;
      useWorkspaceStore.getState().setSeeks(mockPlay.listSeeks());
    };
    const refreshMyGames = () => {
      api.listMyGames().then((games) => {
        if (!cancelled) useWorkspaceStore.getState().setActivePanel(useWorkspaceStore.getState().activePanel);
        // myGames are kept in the mock; the lobby reads them via api.listMyGames()
        void games;
      }).catch(() => {});
    };

    const socket = getSharedPlaySocket();
    const unsub = socket.subscribe((event) => {
      if (cancelled) return;
      const store = useWorkspaceStore.getState();
      switch (event.type) {
        case 'seek.created':
          if (event.seek.id) refreshSeeks();
          break;
        case 'seek.cancelled':
          store.removeSeek(event.seekId);
          refreshSeeks();
          break;
        case 'match.paired': {
          const m = event.match;
          if (m.white.id === mockPlay.me.id || m.black.id === mockPlay.me.id) {
            store.setActiveMatch(m);
            api.getMatchMoves(m.id).then((moves) => {
              if (!cancelled) useWorkspaceStore.getState().setActiveMatchMoves(moves ?? []);
            }).catch(() => {});
          }
          break;
        }
        case 'match.move': {
          if (event.matchId === useWorkspaceStore.getState().activeMatchId) {
            store.appendActiveMatchMove(event.move);
            store.patchMatch({
              ply: store.activeMatchMoves.length + 1,
              clocks: event.clocks,
              clockUpdatedAt: event.clockUpdatedAt,
            });
          }
          break;
        }
        case 'match.finish': {
          if (event.matchId === useWorkspaceStore.getState().activeMatchId) {
            store.patchMatch({ status: 'finished', result: event.result, clocks: event.clocks });
          }
          refreshMyGames();
          break;
        }
        case 'match.offer': {
          if (event.matchId === useWorkspaceStore.getState().activeMatchId) {
            const patch = event.offer === 'draw'
              ? { drawOfferSide: event.side }
              : event.offer === 'rematch'
                ? { rematchOfferSide: event.side }
                : {};
            useWorkspaceStore.getState().patchMatch(patch);
          }
          break;
        }
        case 'match.offer.response': {
          if (event.matchId === useWorkspaceStore.getState().activeMatchId) {
            // Decline clears the offer; accept draw/rematch are resolved by the
            // subsequent match.finish / match.paired events.
            if (!event.accepted) {
              useWorkspaceStore.getState().patchMatch(
                event.offer === 'draw' ? { drawOfferSide: null } : { rematchOfferSide: null },
              );
            }
          }
          break;
        }
        case 'match.chat':
          // Chat is off by default in v1; no UI surface. (Phase 7+ adds a chat pane.)
          break;
        default:
          break;
      }
    });

    useWorkspaceStore.getState().setPlayConnected(true);
    refreshSeeks();

    return () => {
      cancelled = true;
      unsub();
      useWorkspaceStore.getState().setPlayConnected(false);
    };
  }, []);
}