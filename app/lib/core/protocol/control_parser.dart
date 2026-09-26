import 'dart:convert';

import 'control_message.dart';
import 'peer_protocol.dart';
import 'peer_protocol_exception.dart';
import 'text_sanitizer.dart';
import 'transfer_id.dart';

/// Validates and decodes one control frame.
///
/// TS: `parseControl`. The order of the checks below is the order of the
/// original, because a frame that fails two rules must raise the same Turkish
/// message it raised in the Tauri build:
///
/// 1. the whole frame must fit in [PeerProtocol.maxMessageBytes] **UTF-8 bytes**;
/// 2. it must decode to a JSON object;
/// 3. `type` must be a string and `id` a bare 32 character lowercase hex id;
/// 4. the per-variant field rules, in the order the original tested them;
/// 5. everything else is "Geçersiz kontrol mesajı.".
///
/// ## Deviation: what a malformed frame raises
///
/// The original lets the JavaScript engine's own `SyntaxError` escape for input
/// that is not JSON at all, so a peer bug surfaces as an English engine message
/// while every protocol rule surfaces as a Turkish one. Dart's decoder raises
/// `FormatException`, which is not an `Error` and reads as a crash, so this port
/// folds it into [PeerProtocolException] with the Turkish message the rest of
/// the function uses. The decoder failure is kept in [PeerProtocolException.cause]
/// for the log. No accepted frame changes, and no rejected frame becomes
/// accepted.
PeerControlMessage parseControl(String raw) {
  if (utf8ByteLength(raw) > PeerProtocol.maxMessageBytes) {
    throw const PeerProtocolException(PeerProtocol.messageTooLarge);
  }
  final Map<String, Object?> message = _decodeControlObject(raw);

  final Object? typeValue = message['type'];
  final Object? idValue = message['id'];
  if (typeValue is! String || idValue is! String || !isTransferId(idValue)) {
    throw const PeerProtocolException(PeerProtocol.invalidControlMessage);
  }
  final String type = typeValue;
  final String id = idValue;

  // `chat`: a non-empty body that itself fits the byte budget, plus any
  // timestamp. `sentAt` is a non-negative integral millisecond count; 0.1.x
  // accepted any JSON number here, which let `1.5` and `-1e300` through into a
  // rendered message time.
  final Object? text = message['text'];
  final Object? sentAt = message['sentAt'];
  if (type == ControlMessageType.chat.wireName &&
      text is String &&
      sentAt is num &&
      sentAt.isFinite &&
      sentAt >= 0 &&
      sentAt == sentAt.roundToDouble() &&
      sentAt <= PeerProtocol.maxSafeInteger &&
      text.isNotEmpty &&
      utf8ByteLength(text) <= PeerProtocol.maxMessageBytes) {
    return ChatMessage(id: id, text: text, sentAt: sentAt.toInt());
  }

  // `file-offer`: the name and the media type are sanitised on the way in, so a
  // transfer that reaches the UI can never carry `../../` or a scripted type.
  final Object? name = message['name'];
  final Object? mime = message['mime'];
  final int? size = asJavaScriptSafeInteger(message['size']);
  if (type == ControlMessageType.fileOffer.wireName &&
      name is String &&
      mime is String &&
      size != null &&
      size > 0 &&
      size <= PeerProtocol.maxFileBytes) {
    return FileOfferMessage(
      id: id,
      name: safeName(name),
      mime: safeMime(mime),
      size: size,
    );
  }

  // `call-offer`
  if (type == ControlMessageType.callOffer.wireName) {
    final Object? mode = message['mode'];
    final CallMode? parsedMode = mode is String
        ? CallMode.fromWireName(mode)
        : null;
    if (parsedMode != null) return CallOfferMessage(id: id, mode: parsedMode);
  }

  // The four id-only frames are passed through untouched. `ControlMessageType`
  // resolved the same discriminator the original compared as a raw string.
  final ControlMessageType? kind = ControlMessageType.fromWireName(type);
  if (kind == ControlMessageType.fileAccept) return FileAcceptMessage(id: id);
  if (kind == ControlMessageType.fileComplete) {
    return FileCompleteMessage(id: id);
  }
  if (kind == ControlMessageType.callAccept) return CallAcceptMessage(id: id);
  if (kind == ControlMessageType.callEnd) return CallEndMessage(id: id);

  // `profile`: an empty name after sanitising is a rejected frame, not a frame
  // with an empty name. The original throws from the middle of this branch
  // rather than falling through, but the message is the same one the final
  // `throw` uses, so the two are indistinguishable to a caller.
  final Object? profileName = message['name'];
  if (type == ControlMessageType.profile.wireName && profileName is String) {
    final String profile = safeDisplayName(profileName);
    if (profile.isEmpty) {
      throw const PeerProtocolException(PeerProtocol.invalidControlMessage);
    }
    return ProfileMessage(id: id, name: profile);
  }

  // `pair-confirmed`
  if (type == ControlMessageType.pairConfirmed.wireName &&
      _isAbsentOrCapability(message, 'discovery')) {
    return PairConfirmedMessage(
      id: id,
      discovery: _optionalString(message, 'discovery'),
    );
  }

  // `file-decline` and `file-cancel`.
  //
  // Not mirrored: 0.1.x applies `safeReason` to the call decline and then
  // slices the file decline raw, one line apart. A file decline reason is shown
  // in a transfer row, so an unscrubbed one puts raw newlines, tabs and bidi
  // overrides into the interface. Both paths scrub here; the length cap is
  // unchanged so the wire contract still matches.
  if ((type == ControlMessageType.fileDecline.wireName ||
          type == ControlMessageType.fileCancel.wireName) &&
      _isAbsentOrString(message, 'reason')) {
    final String? reason = _optionalString(message, 'reason');
    final String? cut = reason == null ? null : safeReason(reason);
    return type == ControlMessageType.fileDecline.wireName
        ? FileDeclineMessage(id: id, reason: cut)
        : FileCancelMessage(id: id, reason: cut);
  }

  // `call-decline`: scrubbed, and rendered in the call UI.
  if (type == ControlMessageType.callDecline.wireName &&
      _isAbsentOrString(message, 'reason')) {
    final String? reason = _optionalString(message, 'reason');
    return CallDeclineMessage(
      id: id,
      reason: reason == null ? null : safeReason(reason),
    );
  }

  throw const PeerProtocolException(PeerProtocol.invalidControlMessage);
}

/// Decodes a control frame that arrived as bytes instead of as a string.
///
/// The TypeScript transport only ever sees a string on the data channel
/// (`typeof data === "string"`), so this is the port's own entry point for
/// transports that hand over the raw buffer. It keeps the original order: the
/// byte budget is checked before a single byte is decoded, and `parseControl`
/// then repeats the check harmlessly on the decoded text.
PeerControlMessage parseControlBytes(List<int> bytes) {
  if (bytes.length > PeerProtocol.maxMessageBytes) {
    throw const PeerProtocolException(PeerProtocol.messageTooLarge);
  }
  final String raw;
  try {
    raw = utf8.decode(bytes);
  } on FormatException catch (error) {
    // Strict decoding: a frame that is not valid UTF-8 is a rejected frame, not
    // one silently repaired into U+FFFD.
    throw PeerProtocolException(PeerProtocol.invalidControlMessage, error);
  }
  return parseControl(raw);
}

/// Encodes a control frame exactly as the TypeScript `JSON.stringify(message)`
/// did, for a transport that has to put bytes on the wire.
String encodeControl(PeerControlMessage message) =>
    jsonEncode(message.toJson());

Map<String, Object?> _decodeControlObject(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    throw PeerProtocolException(PeerProtocol.invalidControlMessage, error);
  }
  if (decoded is! Map<String, Object?>) {
    throw const PeerProtocolException(PeerProtocol.invalidControlMessage);
  }
  return decoded;
}

/// `Number.isSafeInteger(value) ? value : null`, then narrowed to an `int`.
///
/// This is the single most important difference between a Dart and a JavaScript
/// parse of the same frame. JSON has one number type; JavaScript stores it as a
/// double and therefore silently loses precision above 2^53, while Dart keeps
/// 64-bit integers exactly and only falls back to `double` once the literal no
/// longer fits. The `maxSafeInteger` bound is re-imposed here so that, for
/// example, a declared size of 2^53 or 2^63 is rejected by both.
///
/// The bound is checked *before* [num.toInt], because `toInt` clamps instead of
/// throwing: `9223372036854775808.0.toInt()` is `9223372036854775807` on the
/// Dart VM, which would turn an overflowing size into a merely huge one.
int? asJavaScriptSafeInteger(Object? value) {
  if (value is int) {
    return value >= -PeerProtocol.maxSafeInteger &&
            value <= PeerProtocol.maxSafeInteger
        ? value
        : null;
  }
  if (value is double) {
    // `JSON.parse("1e400")` is Infinity in JavaScript and in Dart alike, and
    // `Number.isSafeInteger(Infinity)` is false, so reject before the compare.
    if (!value.isFinite) return null;
    // `JSON.parse("1.5")` is 1.5 in both languages, and a fractional declared
    // size is not a safe integer in either.
    if (value != value.roundToDouble()) return null;
    if (value < -PeerProtocol.maxSafeInteger ||
        value > PeerProtocol.maxSafeInteger) {
      return null;
    }
    return value.toInt();
  }
  // A string, a bool, null or an absent key: not a number at all.
  return null;
}

/// Mirrors the TypeScript `x === undefined || (typeof x === "string" && test(x))`.
///
/// `containsKey` is what makes this faithful. In JavaScript an absent key and an
/// explicit `null` are different — `null === undefined` is false — so
/// `{"type":"pair-confirmed","id":ID,"discovery":null}` was *rejected* by the
/// original. In Dart both read back as `null`, so the distinction has to be made
/// explicitly or the port would quietly accept frames the Tauri build refuses.
bool _isAbsentOrCapability(Map<String, Object?> message, String key) {
  if (!message.containsKey(key)) return true;
  final Object? value = message[key];
  return value is String && PeerProtocol.capabilityPattern.hasMatch(value);
}

/// The same distinction for a plain optional string field.
bool _isAbsentOrString(Map<String, Object?> message, String key) =>
    !message.containsKey(key) || message[key] is String;

String? _optionalString(Map<String, Object?> message, String key) {
  final Object? value = message[key];
  return value is String ? value : null;
}
