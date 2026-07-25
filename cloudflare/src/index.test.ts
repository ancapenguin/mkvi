import { describe, expect, it } from "vitest";
import { isRelayEnvelope } from "./index";

const publicKey = "a".repeat(43);
const signature = "b".repeat(86);

describe("signaling envelope validation", () => {
  it("permits only bounded, known signaling payloads", () => {
    expect(isRelayEnvelope({ type: "relay", payload: { kind: "offer", sdp: "v=0\r\n" } })).toBe(true);
    expect(isRelayEnvelope({ type: "relay", payload: { kind: "ice", candidate: { candidate: "candidate:1 1 udp 1 127.0.0.1 9 typ host", sdpMid: "0", sdpMLineIndex: 0 } } })).toBe(true);
    expect(isRelayEnvelope({ type: "relay", payload: { kind: "identity", publicKey, signature } })).toBe(true);
  });

  it("rejects arbitrary content, extra fields, and malformed identities", () => {
    expect(isRelayEnvelope({ type: "relay", payload: { kind: "chat", text: "sunucudan içerik aktarımı" } })).toBe(false);
    expect(isRelayEnvelope({ type: "relay", payload: { kind: "offer", sdp: "v=0", file: "not-allowed" } })).toBe(false);
    expect(isRelayEnvelope({ type: "relay", payload: { kind: "identity", publicKey, signature: "short" } })).toBe(false);
    expect(isRelayEnvelope({ type: "relay", payload: { kind: "ice", candidate: { candidate: "x", unknown: "not-allowed" } } })).toBe(false);
  });
});
