/**
 * playIdentity — a single source of truth for the local player's guest id.
 *
 * The backend play flow (Phases 3-7) identifies the local player by the guest
 * id it mints and echoes back in the `X-Play-Guest-Id` response header. The
 * mock backend historically kept the id in sessionStorage. Both must agree so
 * that move color assignment, "is my match", and seek ownership all compare
 * against the SAME id regardless of transport.
 *
 * We always persist the id in sessionStorage under `scidb-play-guest-id` so
 * the mock and the real transport agree within one tab. The REST client and
 * WebSocket mirror this id back to the server; the server adopts it verbatim
 * (it only re-mints when the header is absent or malformed), keeping the
 * round trip consistent.
 */

const GUEST_KEY = 'scidb-play-guest-id';

/** Stable local guest id for this browsing session (created lazily). */
export function getPlayGuestId(): string {
  if (typeof sessionStorage === 'undefined') return '';
  let id = sessionStorage.getItem(GUEST_KEY);
  if (!id) {
    id = 'guest-' + Math.random().toString(36).slice(2, 10);
    sessionStorage.setItem(GUEST_KEY, id);
  }
  return id;
}

/** True when the given player id is the local player. */
export function isLocalPlayer(playerId: string | undefined | null): boolean {
  if (!playerId) return false;
  return playerId === getPlayGuestId();
}
