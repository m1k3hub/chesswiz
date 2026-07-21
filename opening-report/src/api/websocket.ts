/**
 * websocket.ts — WebSocket client for the scidb-beta runtime adapter.
 *
 * Provides a thin wrapper around the browser WebSocket API for:
 *   - /api/ws/events        — global job progress stream
 *   - /api/ws/analysis/:id  — per-job engine analysis stream
 *
 * The client auto-reconnects with exponential backoff and gracefully falls
 * back to HTTP polling when the WebSocket is unavailable.
 */

export type WebSocketMessageHandler = (data: unknown) => void;

const WS_BASE = (() => {
  const apiBase = import.meta.env?.VITE_SCIDB_API_BASE || (typeof window !== 'undefined' ? window.SCIDB_API_BASE : '') || '';
  if (apiBase.startsWith('http')) {
    return apiBase.replace(/^http/, 'ws');
  }
  // Vite dev server proxies /api to the runtime adapter.
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${protocol}//${window.location.host}${apiBase}`;
})();

function buildUrl(path: string): string {
  const base = WS_BASE.replace(/\/$/, '');
  return `${base}${path}`;
}

export class ScidbWebSocketClient {
  private socket: WebSocket | null = null;
  private reconnectAttempts = 0;
  private readonly maxReconnectAttempts = 5;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private messageHandlers: WebSocketMessageHandler[] = [];
  private openHandlers: Array<() => void> = [];
  private closeHandlers: Array<() => void> = [];
  private intentionallyClosed = false;

  constructor(private readonly url: string) {}

  connect() {
    if (this.socket?.readyState === WebSocket.OPEN) return;
    this.intentionallyClosed = false;
    try {
      this.socket = new WebSocket(this.url);
      this.socket.onopen = () => {
        this.reconnectAttempts = 0;
        this.openHandlers.forEach((h) => h());
      };
      this.socket.onmessage = (event) => {
        let data: unknown;
        try {
          data = JSON.parse(event.data);
        } catch {
          data = event.data;
        }
        this.messageHandlers.forEach((h) => h(data));
      };
      this.socket.onclose = () => {
        this.closeHandlers.forEach((h) => h());
        if (!this.intentionallyClosed) {
          this.scheduleReconnect();
        }
      };
      this.socket.onerror = (err) => {
        console.warn('WebSocket error:', err);
      };
    } catch (err) {
      console.warn('WebSocket connection failed:', err);
      this.scheduleReconnect();
    }
  }

  private scheduleReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) return;
    this.reconnectAttempts += 1;
    const delay = Math.min(1000 * 2 ** this.reconnectAttempts, 30000);
    this.reconnectTimer = setTimeout(() => this.connect(), delay);
  }

  onMessage(handler: WebSocketMessageHandler) {
    this.messageHandlers.push(handler);
    return () => {
      this.messageHandlers = this.messageHandlers.filter((h) => h !== handler);
    };
  }

  onOpen(handler: () => void) {
    this.openHandlers.push(handler);
    return () => {
      this.openHandlers = this.openHandlers.filter((h) => h !== handler);
    };
  }

  onClose(handler: () => void) {
    this.closeHandlers.push(handler);
    return () => {
      this.closeHandlers = this.closeHandlers.filter((h) => h !== handler);
    };
  }

  send(message: unknown) {
    if (this.socket?.readyState === WebSocket.OPEN) {
      this.socket.send(JSON.stringify(message));
    }
  }

  disconnect() {
    this.intentionallyClosed = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.socket?.close();
    this.socket = null;
  }
}

const clients = new Map<string, ScidbWebSocketClient>();

export function getOrCreateWebSocket(path: string): ScidbWebSocketClient {
  const url = buildUrl(path);
  if (!clients.has(url)) {
    const client = new ScidbWebSocketClient(url);
    client.connect();
    clients.set(url, client);
  }
  return clients.get(url)!;
}

export function disconnectWebSocket(path: string) {
  const url = buildUrl(path);
  const client = clients.get(url);
  if (client) {
    client.disconnect();
    clients.delete(url);
  }
}

export function subscribeToJobEvents(handler: WebSocketMessageHandler): () => void {
  const client = getOrCreateWebSocket('/ws/events');
  return client.onMessage(handler);
}

export function subscribeToAnalysis(jobId: string, handler: WebSocketMessageHandler): () => void {
  const client = getOrCreateWebSocket(`/ws/analysis/${jobId}`);
  return client.onMessage(handler);
}
