export interface Env {
  PAIRING_ROOM: DurableObjectNamespace;
  PEER_RENDEZVOUS: DurableObjectNamespace;
}

const CODE = /^[A-HJ-NP-Z2-9]{13,16}$/;
// 32 random bytes, base64url encoded. This is an unguessable bearer capability,
// not a user identifier. A pair derives and stores it locally after SAS approval.
const OPAQUE_ID = /^[A-Za-z0-9_-]{43}$/;
const PEER_TTL_MS = 30 * 24 * 60 * 60_000;

export default {
  fetch(request: Request, env: Env): Response {
    const url = new URL(request.url);
    if (url.pathname === "/health") return Response.json({ ok: true, service: "mkvi-signal" });
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("WebSocket required", { status: 426 });
    }
    if (url.pathname === "/v1/rendezvous") {
      const code = url.searchParams.get("code")?.toUpperCase() ?? "";
      if (!CODE.test(code)) return new Response("Invalid pairing code", { status: 400 });
      return env.PAIRING_ROOM.get(env.PAIRING_ROOM.idFromName(code)).fetch(request);
    }
    if (url.pathname === "/v1/peer") {
      const pair = url.searchParams.get("pair") ?? "";
      const device = url.searchParams.get("device") ?? "";
      if (!OPAQUE_ID.test(pair) || !OPAQUE_ID.test(device)) {
        return new Response("Invalid peer identifier", { status: 400 });
      }
      // Only the opaque pair capability routes to a DO. Device handles are kept
      // inside the DO solely to enforce its two-device membership limit.
      return env.PEER_RENDEZVOUS.get(env.PEER_RENDEZVOUS.idFromName(pair)).fetch(request);
    }
    return new Response("Not found", { status: 404 });
  },
};

/** Fifteen-minute, two-peer signaling room. Payloads are opaque relay envelopes. */
export class PairingRoom implements DurableObject {
  private readonly clients = new Set<WebSocket>();
  private readonly rateWindows = new Map<WebSocket, { startedAt: number; count: number }>();

  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const admitted = (await this.state.storage.get<number>("admitted")) ?? 0;
    if (admitted >= 2 || this.clients.size >= 2) return new Response("Pairing room is full", { status: 409 });
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    server.accept();
    this.clients.add(server);
    this.rateWindows.set(server, { startedAt: Date.now(), count: 0 });
    await this.state.storage.put("admitted", admitted + 1);
    await this.state.storage.setAlarm(Date.now() + 15 * 60_000);
    server.addEventListener("message", (event) => this.relay(server, event.data));
    server.addEventListener("close", () => this.disconnect(server));
    server.addEventListener("error", () => this.disconnect(server));
    server.send(JSON.stringify({ type: "room", peers: this.clients.size - 1 }));
    this.broadcast({ type: "presence", peers: this.clients.size }, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  async alarm(): Promise<void> {
    for (const client of this.clients) client.close(1000, "Pairing expired");
    this.clients.clear();
    this.rateWindows.clear();
    await this.state.storage.delete("admitted");
  }

  private relay(sender: WebSocket, data: unknown): void {
    const now = Date.now();
    const window = this.rateWindows.get(sender) ?? { startedAt: now, count: 0 };
    if (now - window.startedAt >= 60_000) { window.startedAt = now; window.count = 0; }
    if (++window.count > 120) return sender.close(1008, "Signaling rate exceeded");
    this.rateWindows.set(sender, window);
    if (typeof data !== "string" || data.length > 65_536) return sender.close(1009, "Invalid envelope");
    let message: unknown;
    try { message = JSON.parse(data); } catch { return sender.close(1003, "Invalid JSON"); }
    if (!isRelayEnvelope(message)) return sender.close(1008, "Disallowed signaling envelope");
    this.broadcast(message, sender);
  }

  private disconnect(client: WebSocket): void {
    this.clients.delete(client);
    this.rateWindows.delete(client);
    this.broadcast({ type: "presence", peers: this.clients.size });
  }

  private broadcast(message: unknown, except?: WebSocket): void {
    const encoded = JSON.stringify(message);
    for (const client of this.clients) if (client !== except) client.send(encoded);
  }
}

export function isRelayEnvelope(value: unknown): value is { type: "relay"; payload: unknown } {
  if (typeof value !== "object" || value === null) return false;
  const envelope = value as { type?: unknown; payload?: unknown };
  return envelope.type === "relay" && isSignalPayload(envelope.payload);
}

/** Signaling only: reject arbitrary JSON so the Worker cannot become a content tunnel. */
function isSignalPayload(value: unknown): boolean {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const payload = value as Record<string, unknown>;
  const keys = Object.keys(payload);
  if (payload.kind === "offer" || payload.kind === "answer") {
    return keys.length === 2 && keys.includes("sdp") && typeof payload.sdp === "string" && payload.sdp.length > 0 && payload.sdp.length <= 32_768;
  }
  if (payload.kind === "identity") {
    return keys.every((key) => key === "kind" || key === "publicKey" || key === "signature")
      && typeof payload.publicKey === "string" && OPAQUE_ID.test(payload.publicKey)
      && typeof payload.signature === "string" && /^[A-Za-z0-9_-]{86}$/.test(payload.signature);
  }
  if (payload.kind !== "ice" || keys.length !== 2 || !keys.includes("candidate") || typeof payload.candidate !== "object" || payload.candidate === null || Array.isArray(payload.candidate)) return false;
  const candidate = payload.candidate as Record<string, unknown>;
  return Object.keys(candidate).every((key) => key === "candidate" || key === "sdpMid" || key === "sdpMLineIndex" || key === "usernameFragment")
    && typeof candidate.candidate === "string" && candidate.candidate.length > 0 && candidate.candidate.length <= 2_048
    && (candidate.sdpMid === undefined || candidate.sdpMid === null || (typeof candidate.sdpMid === "string" && candidate.sdpMid.length <= 64))
    && (candidate.sdpMLineIndex === undefined || candidate.sdpMLineIndex === null || (typeof candidate.sdpMLineIndex === "number" && Number.isSafeInteger(candidate.sdpMLineIndex) && candidate.sdpMLineIndex >= 0))
    && (candidate.usernameFragment === undefined || (typeof candidate.usernameFragment === "string" && candidate.usernameFragment.length <= 256));
}

interface PeerRecord {
  devices: string[];
  expiresAt: number;
}

/**
 * Long-lived, pair-scoped signaling room used only after local SAS approval.
 * It retains two opaque device handles and a sliding expiry. SDP, ICE and
 * identity values remain opaque and are forwarded only to the other peer.
 */
export class PeerRendezvous implements DurableObject {
  private readonly rateWindows = new Map<WebSocket, { startedAt: number; count: number }>();

  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const device = new URL(request.url).searchParams.get("device") ?? "";
    // The edge worker validates this before dispatching; retain the check so a
    // direct DO request in a local/test environment cannot weaken the invariant.
    if (!OPAQUE_ID.test(device)) return new Response("Invalid device identifier", { status: 400 });

    const now = Date.now();
    let record = await this.state.storage.get<PeerRecord>("peer-record");
    if (record && record.expiresAt <= now) {
      this.closeAll(4001, "Peer discovery expired");
      await this.state.storage.delete("peer-record");
      record = undefined;
    }
    if (!record) record = { devices: [], expiresAt: now + PEER_TTL_MS };
    if (!record.devices.includes(device)) {
      if (record.devices.length >= 2) return new Response("Peer device limit reached", { status: 403 });
      record.devices.push(device);
    }
    record.expiresAt = now + PEER_TTL_MS;
    await this.state.storage.put("peer-record", record);
    await this.state.storage.setAlarm(record.expiresAt);

    // One live socket per device makes presence unambiguous; reconnects replace
    // stale WebViews without consuming another one of the two peer slots.
    for (const socket of this.state.getWebSockets(device)) socket.close(4000, "Superseded connection");
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    server.serializeAttachment({ device });
    this.state.acceptWebSocket(server, [device]);
    this.rateWindows.set(server, { startedAt: now, count: 0 });
    server.send(JSON.stringify({ type: "ready", online: this.onlineDevices() }));
    this.broadcastPresence(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const now = Date.now();
    const window = this.rateWindows.get(socket) ?? { startedAt: now, count: 0 };
    if (now - window.startedAt >= 60_000) { window.startedAt = now; window.count = 0; }
    if (++window.count > 120) return socket.close(1008, "Signaling rate exceeded");
    this.rateWindows.set(socket, window);
    if (typeof message !== "string" || message.length > 65_536) return socket.close(1009, "Invalid envelope");
    let relay: unknown;
    try { relay = JSON.parse(message); } catch { return socket.close(1003, "Invalid JSON"); }
    if (!isRelayEnvelope(relay)) return socket.close(1008, "Disallowed signaling envelope");
    for (const peer of this.state.getWebSockets()) if (peer !== socket) peer.send(message);
  }

  webSocketClose(socket: WebSocket): void {
    this.rateWindows.delete(socket);
    this.broadcastPresence();
  }

  webSocketError(socket: WebSocket): void {
    this.rateWindows.delete(socket);
    this.broadcastPresence();
  }

  async alarm(): Promise<void> {
    const record = await this.state.storage.get<PeerRecord>("peer-record");
    if (!record) return;
    if (record.expiresAt > Date.now()) return this.state.storage.setAlarm(record.expiresAt);
    this.closeAll(4001, "Peer discovery expired");
    await this.state.storage.delete("peer-record");
  }

  private onlineDevices(): number {
    return new Set(this.state.getWebSockets().map((socket) => this.deviceOf(socket))).size;
  }

  private deviceOf(socket: WebSocket): string {
    const attachment = socket.deserializeAttachment();
    return typeof attachment === "object" && attachment !== null && typeof attachment.device === "string"
      ? attachment.device
      : "";
  }

  private broadcastPresence(except?: WebSocket): void {
    const encoded = JSON.stringify({ type: "presence", online: this.onlineDevices() });
    for (const socket of this.state.getWebSockets()) if (socket !== except) socket.send(encoded);
  }

  private closeAll(code: number, reason: string): void {
    for (const socket of this.state.getWebSockets()) socket.close(code, reason);
  }
}
