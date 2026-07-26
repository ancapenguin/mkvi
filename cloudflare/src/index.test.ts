import { describe, expect, it } from "vitest";
import { isRelayEnvelope, isSignalPayload } from "./index";

// The Rust side encodes identity material with the STANDARD base64 alphabet
// (STANDARD_NO_PAD), so "+" and "/" appear in real traffic. Accepting only
// base64url silently dropped roughly 93% of pairings in production: a signature
// is 86 characters, and (62/64)^86 is about 7%.
const standardKey = `${"a".repeat(41)}+/`;
const standardSignature = `${"b".repeat(84)}+/`;
const urlSafeKey = `${"a".repeat(41)}-_`;
const urlSafeSignature = `${"b".repeat(84)}-_`;
const relay = (payload: unknown) => ({ type: "relay", payload });
const candidate = { candidate: "candidate:1 1 udp 1 127.0.0.1 9 typ host", sdpMid: "0", sdpMLineIndex: 0, usernameFragment: "abcd" };

describe("identity envelopes", () => {
  it("accepts the standard base64 alphabet the Rust client actually sends", () => {
    expect(isSignalPayload({ kind: "identity", publicKey: standardKey, signature: standardSignature })).toBe(true);
  });

  it("accepts the base64url alphabet as well", () => {
    expect(isSignalPayload({ kind: "identity", publicKey: urlSafeKey, signature: urlSafeSignature })).toBe(true);
  });

  it("rejects wrong key and signature lengths", () => {
    for (const key of ["a".repeat(42), "a".repeat(44), ""]) {
      expect(isSignalPayload({ kind: "identity", publicKey: key, signature: standardSignature })).toBe(false);
    }
    for (const signature of ["b".repeat(85), "b".repeat(87), ""]) {
      expect(isSignalPayload({ kind: "identity", publicKey: standardKey, signature })).toBe(false);
    }
  });

  it("rejects characters outside both alphabets", () => {
    expect(isSignalPayload({ kind: "identity", publicKey: `${"a".repeat(42)}=`, signature: standardSignature })).toBe(false);
    expect(isSignalPayload({ kind: "identity", publicKey: `${"a".repeat(42)}.`, signature: standardSignature })).toBe(false);
    expect(isSignalPayload({ kind: "identity", publicKey: standardKey, signature: `${"b".repeat(85)} ` })).toBe(false);
  });

  it("rejects missing fields, wrong types and unknown extras", () => {
    expect(isSignalPayload({ kind: "identity", publicKey: standardKey })).toBe(false);
    expect(isSignalPayload({ kind: "identity", signature: standardSignature })).toBe(false);
    expect(isSignalPayload({ kind: "identity", publicKey: 1, signature: standardSignature })).toBe(false);
    expect(isSignalPayload({ kind: "identity", publicKey: standardKey, signature: standardSignature, rendezvous: "x" })).toBe(false);
  });
});

describe("offer and answer envelopes", () => {
  it("accepts exactly {kind, sdp} with a bounded session description", () => {
    for (const kind of ["offer", "answer"]) {
      expect(isSignalPayload({ kind, sdp: "v=0\r\n" })).toBe(true);
      expect(isSignalPayload({ kind, sdp: "s".repeat(32_768) })).toBe(true);
    }
  });

  it("rejects empty, oversized or decorated descriptions", () => {
    expect(isSignalPayload({ kind: "offer", sdp: "" })).toBe(false);
    expect(isSignalPayload({ kind: "offer", sdp: "s".repeat(32_769) })).toBe(false);
    expect(isSignalPayload({ kind: "offer", sdp: "v=0", file: "not-allowed" })).toBe(false);
    expect(isSignalPayload({ kind: "answer", sdp: 42 })).toBe(false);
  });
});

describe("ice envelopes", () => {
  it("accepts a candidate carrying only the four allowed keys", () => {
    expect(isSignalPayload({ kind: "ice", candidate })).toBe(true);
    expect(isSignalPayload({ kind: "ice", candidate: { candidate: "candidate:x", sdpMid: null, sdpMLineIndex: null } })).toBe(true);
  });

  it("rejects unknown keys, bad shapes and oversized candidates", () => {
    expect(isSignalPayload({ kind: "ice", candidate: { ...candidate, unknown: "x" } })).toBe(false);
    expect(isSignalPayload({ kind: "ice", candidate: { sdpMid: "0" } })).toBe(false);
    expect(isSignalPayload({ kind: "ice", candidate: { candidate: "c".repeat(2_049) } })).toBe(false);
    expect(isSignalPayload({ kind: "ice", candidate: { candidate: "c", sdpMLineIndex: -1 } })).toBe(false);
    expect(isSignalPayload({ kind: "ice", candidate: { candidate: "c", sdpMLineIndex: 1.5 } })).toBe(false);
    expect(isSignalPayload({ kind: "ice", candidate: null })).toBe(false);
    expect(isSignalPayload({ kind: "ice", candidate: [] })).toBe(false);
    expect(isSignalPayload({ kind: "ice", candidate, extra: 1 })).toBe(false);
  });
});

describe("isRelayEnvelope", () => {
  it("rejects anything that is not a relay envelope", () => {
    for (const value of [null, undefined, 7, "relay", [], {}, { type: "presence" }, { type: "relay" }]) {
      expect(isRelayEnvelope(value)).toBe(false);
    }
  });

  it("refuses to carry content, which is the whole point of the allow-list", () => {
    expect(isRelayEnvelope(relay({ kind: "chat", text: "mesaj" }))).toBe(false);
    expect(isRelayEnvelope(relay({ kind: "file", bytes: "x" }))).toBe(false);
    expect(isRelayEnvelope(relay({}))).toBe(false);
  });
});

// NARROWING GUARD. Every payload below is sent by a shipped client. Removing a
// field from isSignalPayload disconnects those clients with close(1008) and the
// user only sees "connection failed" - so these four must keep passing until it
// is proven that no client in the wild still sends them.
describe("protocol narrowing guard", () => {
  it("keeps accepting every payload kind a released client sends", () => {
    expect(isRelayEnvelope(relay({ kind: "identity", publicKey: standardKey, signature: standardSignature }))).toBe(true);
    expect(isRelayEnvelope(relay({ kind: "offer", sdp: "v=0\r\n" }))).toBe(true);
    expect(isRelayEnvelope(relay({ kind: "answer", sdp: "v=0\r\n" }))).toBe(true);
    expect(isRelayEnvelope(relay({ kind: "ice", candidate }))).toBe(true);
  });
});
