/// Signaling payload types and the allow-list that guards them.
///
/// The Dart client must never put a byte on the wire that the Worker would
/// refuse, and it must never put a byte on the wire the Worker would ACCEPT but
/// that carries content. `isSignalPayload` is therefore a faithful mirror of
/// `isSignalPayload` in `cloudflare/src/index.ts`: a key-by-key allow-list, not
/// a set of suggestions. Adding a key to a payload is what turns the Worker into
/// a content tunnel, which is why `vectors/wire-v1.json` carries an explicit
/// `forbiddenKeys` list and both test suites execute it.
///
/// The base64 detail that killed ~93% of production pairings is preserved here:
/// `publicKey` and `signature` accept BOTH alphabets, standard (`+`, `/`) and
/// base64url (`-`, `_`), because Rust encodes them with `STANDARD_NO_PAD` while
/// the browser used base64url. A signature is 86 characters, so a base64url-only
/// filter dropped (62/64)^86 - about 93% - of every identity envelope. `session`
/// is deliberately stricter: it also travels in a URL query, so it stays
/// base64url only.
library;

import 'dart:convert';

/// Shape rules mirrored from the Worker.
final RegExp publicKeyPattern = RegExp(r'^[A-Za-z0-9+/_-]{43}$');
final RegExp signaturePattern = RegExp(r'^[A-Za-z0-9+/_-]{86}$');
final RegExp _opaqueIdPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

const int maxSessionDescriptionLength = 32768;
const int maxIceCandidateLength = 2048;
const int maxSdpMidLength = 64;
const int maxUsernameFragmentLength = 256;

/// The largest integer the Worker's `Number.isSafeInteger` accepts, so a media
/// index that survives this mirror also survives the server.
const int _maxSafeInteger = 9007199254740991;

/// One relayed signaling message. The four kinds are the only four the Worker
/// relays; there is no chat, no file, no display name.
sealed class SignalPayload {
  const SignalPayload();

  /// The `kind` discriminator written on the wire.
  String get kind;

  /// The exact JSON body. Key order is part of the contract: it is what
  /// `vectors/wire-v1.json` compares byte for byte in `relayOutbound`.
  Map<String, Object?> toJson();
}

/// A session description. Exactly `{kind, sdp}` on the wire.
final class OfferSignal extends SignalPayload {
  const OfferSignal(this.sdp);

  final String sdp;

  @override
  String get kind => 'offer';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind, 'sdp': sdp};
}

/// The answer to an [OfferSignal]. Exactly `{kind, sdp}` on the wire.
final class AnswerSignal extends SignalPayload {
  const AnswerSignal(this.sdp);

  final String sdp;

  @override
  String get kind => 'answer';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind, 'sdp': sdp};
}

/// An ICE candidate. Exactly `{kind, candidate}` on the wire.
final class IceSignal extends SignalPayload {
  const IceSignal(this.candidate);

  final IceCandidate candidate;

  @override
  String get kind => 'ice';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind, 'candidate': candidate.toJson()};
}

/// Ed25519 identity material. `session` is optional because identities sent by
/// 0.1.0 - 0.1.3 omit it entirely and must keep working; adding the field never
/// disconnects an old client, removing it would.
final class IdentitySignal extends SignalPayload {
  const IdentitySignal({required this.publicKey, required this.signature, this.session});

  final String publicKey;
  final String signature;

  /// The reconnect session the signature is bound to, when there is one.
  final String? session;

  @override
  String get kind => 'identity';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'publicKey': publicKey,
    'signature': signature,
    if (session != null) 'session': session,
  };
}

/// An ICE candidate and its optional association with a media section.
///
/// Keys are written in the order `candidate`, `sdpMid`, `sdpMLineIndex`,
/// `usernameFragment`, and absent optional keys are omitted rather than written
/// as null. Both rules are pinned by the `outbound-ice` vector.
final class IceCandidate {
  const IceCandidate({required this.candidate, this.sdpMid, this.sdpMLineIndex, this.usernameFragment});

  /// Rebuilds a candidate from a decoded JSON map. Only call this on a map that
  /// [isSignalPayload] has already accepted.
  factory IceCandidate.fromJson(Map<Object?, Object?> json) => IceCandidate(
    candidate: json['candidate']! as String,
    sdpMid: json['sdpMid'] as String?,
    sdpMLineIndex: (json['sdpMLineIndex'] as num?)?.toInt(),
    usernameFragment: json['usernameFragment'] as String?,
  );

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
  final String? usernameFragment;

  Map<String, Object?> toJson() => <String, Object?>{
    'candidate': candidate,
    if (sdpMid != null) 'sdpMid': sdpMid,
    if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
    if (usernameFragment != null) 'usernameFragment': usernameFragment,
  };
}

/// The envelope the client sends: `{"type":"relay","payload":{...}}` and nothing
/// else. The client never sends `presence`, `room` or `ready`; those are the
/// server's own messages.
final class SignalingEnvelope {
  const SignalingEnvelope(this.payload);

  /// The only type a client is allowed to send.
  static const String relayType = 'relay';

  final SignalPayload payload;

  Map<String, Object?> toJson() => <String, Object?>{'type': relayType, 'payload': payload.toJson()};

  /// The exact bytes to put on the wire.
  String encode() => jsonEncode(toJson());
}

/// Rebuilds a typed [SignalPayload] from a decoded JSON map.
///
/// Returns null when the map is not a payload the Worker would relay, so the
/// caller can treat it as a malformed message instead of guessing a type.
SignalPayload? decodeSignalPayload(Object? value) {
  if (!isSignalPayload(value)) return null;
  final Map<Object?, Object?> payload = value! as Map<Object?, Object?>;
  final Object? kind = payload['kind'];
  return switch (kind) {
    'offer' => OfferSignal(payload['sdp']! as String),
    'answer' => AnswerSignal(payload['sdp']! as String),
    'identity' => IdentitySignal(
      publicKey: payload['publicKey']! as String,
      signature: payload['signature']! as String,
      session: payload['session'] as String?,
    ),
    'ice' => IceSignal(IceCandidate.fromJson(payload['candidate']! as Map<Object?, Object?>)),
    _ => null,
  };
}

/// Whether [value] is a signaling payload the Worker relays.
///
/// A key-by-key mirror of `isSignalPayload` in `cloudflare/src/index.ts`. Only
/// the shape is decided here; authenticity is settled by the Ed25519
/// verification each peer performs locally.
bool isSignalPayload(Object? value) {
  if (value is! Map) return false;
  final Object? kind = value['kind'];

  if (kind == 'offer' || kind == 'answer') {
    if (value.length != 2) return false;
    final Object? sdp = value['sdp'];
    return sdp is String && sdp.isNotEmpty && sdp.length <= maxSessionDescriptionLength;
  }

  if (kind == 'identity') {
    const Set<Object?> allowed = <Object?>{'kind', 'publicKey', 'signature', 'session'};
    if (!value.keys.every(allowed.contains)) return false;
    final Object? publicKey = value['publicKey'];
    final Object? signature = value['signature'];
    if (publicKey is! String || !publicKeyPattern.hasMatch(publicKey)) return false;
    if (signature is! String || !signaturePattern.hasMatch(signature)) return false;
    // `containsKey` rather than a null check: an explicit `"session": null` is
    // not the same as an absent session, and the Worker rejects it.
    if (value.containsKey('session')) {
      final Object? session = value['session'];
      if (session is! String || !_opaqueIdPattern.hasMatch(session)) return false;
    }
    return true;
  }

  if (kind != 'ice' || value.length != 2) return false;
  final Object? rawCandidate = value['candidate'];
  if (rawCandidate is! Map) return false;

  const Set<Object?> allowed = <Object?>{'candidate', 'sdpMid', 'sdpMLineIndex', 'usernameFragment'};
  if (!rawCandidate.keys.every(allowed.contains)) return false;

  final Object? line = rawCandidate['candidate'];
  if (line is! String || line.isEmpty || line.length > maxIceCandidateLength) return false;

  final Object? sdpMid = rawCandidate['sdpMid'];
  if (sdpMid != null && (sdpMid is! String || sdpMid.length > maxSdpMidLength)) return false;

  final Object? index = rawCandidate['sdpMLineIndex'];
  if (index != null) {
    if (index is! int) return false;
    if (index < 0 || index > _maxSafeInteger) return false;
  }

  // Unlike sdpMid, an explicit null usernameFragment is rejected.
  if (rawCandidate.containsKey('usernameFragment')) {
    final Object? fragment = rawCandidate['usernameFragment'];
    if (fragment is! String || fragment.length > maxUsernameFragmentLength) return false;
  }
  return true;
}

/// Whether [value] is an envelope the Worker will relay from a client.
bool isRelayEnvelope(Object? value) =>
    value is Map && value['type'] == SignalingEnvelope.relayType && isSignalPayload(value['payload']);
