import 'peer_protocol.dart';

/// The 12 wire discriminators of the control channel.
///
/// Keeping them in an enum means the parser can dispatch with a `switch`
/// expression that the compiler proves exhaustive, and a typo cannot become an
/// unknown frame on the wire.
enum ControlMessageType {
  chat('chat'),
  fileOffer('file-offer'),
  fileAccept('file-accept'),
  fileDecline('file-decline'),
  fileComplete('file-complete'),
  fileCancel('file-cancel'),
  callOffer('call-offer'),
  callAccept('call-accept'),
  callDecline('call-decline'),
  callEnd('call-end'),
  pairConfirmed('pair-confirmed'),
  profile('profile');

  const ControlMessageType(this.wireName);

  /// The exact spelling that travels on the wire.
  final String wireName;

  /// Resolves a wire name, or `null` for an unknown frame type.
  static ControlMessageType? fromWireName(String wireName) {
    for (final ControlMessageType type in values) {
      if (type.wireName == wireName) return type;
    }
    return null;
  }
}

/// Media direction of a call offer.
enum CallMode {
  audio('audio'),
  video('video');

  const CallMode(this.wireName);

  final String wireName;

  static CallMode? fromWireName(String wireName) {
    for (final CallMode mode in values) {
      if (mode.wireName == wireName) return mode;
    }
    return null;
  }
}

/// Wire messages used only after a WebRTC DataChannel has been established.
///
/// ## Why a sealed class hierarchy and not one validated bag of fields
///
/// The wire schema is a union of twelve object shapes, where each shape *is* the
/// schema. Dart has no union types, and the two ways to fake one are both worse:
/// `Map<String, Object?>` re-creates the untyped bag the union exists to
/// prevent, and a single wide class with twelve nullable fields makes every
/// consumer re-derive which fields are meaningful for which variant. A sealed
/// hierarchy is the exact analogue — `sealed` gives the same exhaustiveness
/// guarantee in `switch` that the union gives in its `switch`, and every field
/// is `final` instead of a mutable property on a bag of untyped keys.
///
/// The one thing that is *not* enforced by the type system is the 32 hex
/// character shape of [id]; that is left to the parser too, so
/// `PeerControlMessage.fromJson` is the only supported constructor path.
sealed class PeerControlMessage {
  const PeerControlMessage({required this.id});

  /// Transfer id, always 32 lowercase hex characters on a parsed message.
  final String id;

  /// The wire discriminator of this variant.
  ControlMessageType get kind;

  /// The discriminator as it travels on the wire, i.e. `kind.wireName`.
  String get type => kind.wireName;

  /// The exact JSON shape that travels on the wire.
  ///
  /// Key order is type-first, and an absent optional field is **omitted** rather
  /// than written as `null` — a `null` on the wire is a value the peer has to
  /// distinguish from an absent one, and it makes an encoded frame differ from
  /// the one another implementation produces for the same message.
  Map<String, Object?> toJson();

  /// The fields that take part in equality, besides [id].
  List<Object?> get equalityFields;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PeerControlMessage) return false;
    if (other.runtimeType != runtimeType || other.id != id) return false;
    final List<Object?> mine = equalityFields;
    final List<Object?> theirs = other.equalityFields;
    if (mine.length != theirs.length) return false;
    for (int i = 0; i < mine.length; i += 1) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, id, Object.hashAll(equalityFields));

  @override
  String toString() => '$runtimeType(type: $type, id: $id, $equalityFields)';
}

/// Base of the four control frames that carry nothing but a transfer id:
/// `file-accept`, `file-complete`, `call-accept` and `call-end`.
///
/// One base class rather than four unrelated types, because all four are pure
/// acknowledgements: the parser passes them through untouched and the receiver
/// only ever dispatches on the id.
sealed class IdOnlyMessage extends PeerControlMessage {
  const IdOnlyMessage({required super.id});

  @override
  Map<String, Object?> toJson() => <String, Object?>{'type': type, 'id': id};

  @override
  List<Object?> get equalityFields => const <Object?>[];
}

final class ChatMessage extends PeerControlMessage {
  const ChatMessage({
    required super.id,
    required this.text,
    required this.sentAt,
  });

  @override
  ControlMessageType get kind => ControlMessageType.chat;

  final String text;

  /// A non-negative integral millisecond count, validated as one.
  ///
  /// The field is not merely "a number": a fractional or absurd timestamp is
  /// accepted by a `is num` check and then rendered as a message time, so the
  /// parser rejects anything that is not a whole, finite, non-negative value.
  /// Every writer sends the current epoch milliseconds, so nothing legitimate is
  /// refused.
  final int sentAt;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'id': id,
    'text': text,
    'sentAt': sentAt,
  };

  @override
  List<Object?> get equalityFields => <Object?>[text, sentAt];
}

final class FileOfferMessage extends PeerControlMessage {
  const FileOfferMessage({
    required super.id,
    required this.name,
    required this.mime,
    required this.size,
  });

  @override
  ControlMessageType get kind => ControlMessageType.fileOffer;

  /// Already run through [safeName] by `parseControl`.
  final String name;

  /// Already run through [safeMime] by `parseControl`.
  final String mime;

  /// Declared size in bytes, `0 < size <= PeerProtocol.maxFileBytes`.
  final int size;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'id': id,
    'name': name,
    'mime': mime,
    'size': size,
  };

  @override
  List<Object?> get equalityFields => <Object?>[name, mime, size];
}

final class FileAcceptMessage extends IdOnlyMessage {
  const FileAcceptMessage({required super.id});

  @override
  ControlMessageType get kind => ControlMessageType.fileAccept;
}

final class FileDeclineMessage extends PeerControlMessage {
  const FileDeclineMessage({required super.id, this.reason});

  @override
  ControlMessageType get kind => ControlMessageType.fileDecline;

  /// The peer's reason, already scrubbed by `safeReason` and capped at
  /// [PeerProtocol.maxReasonLength] on the parse path, which is the only
  /// supported way to build this message from the wire.
  final String? reason;

  @override
  Map<String, Object?> toJson() => _withOptionalReason(type, id, reason);

  @override
  List<Object?> get equalityFields => <Object?>[reason];
}

final class FileCompleteMessage extends IdOnlyMessage {
  const FileCompleteMessage({required super.id});

  @override
  ControlMessageType get kind => ControlMessageType.fileComplete;
}

final class FileCancelMessage extends PeerControlMessage {
  const FileCancelMessage({required super.id, this.reason});

  @override
  ControlMessageType get kind => ControlMessageType.fileCancel;

  final String? reason;

  @override
  Map<String, Object?> toJson() => _withOptionalReason(type, id, reason);

  @override
  List<Object?> get equalityFields => <Object?>[reason];
}

final class CallOfferMessage extends PeerControlMessage {
  const CallOfferMessage({required super.id, required this.mode});

  @override
  ControlMessageType get kind => ControlMessageType.callOffer;

  final CallMode mode;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'id': id,
    'mode': mode.wireName,
  };

  @override
  List<Object?> get equalityFields => <Object?>[mode];
}

final class CallAcceptMessage extends IdOnlyMessage {
  const CallAcceptMessage({required super.id});

  @override
  ControlMessageType get kind => ControlMessageType.callAccept;
}

final class CallDeclineMessage extends PeerControlMessage {
  const CallDeclineMessage({required super.id, this.reason});

  @override
  ControlMessageType get kind => ControlMessageType.callDecline;

  /// Already run through [safeReason] by `parseControl`, unlike a file decline.
  final String? reason;

  @override
  Map<String, Object?> toJson() => _withOptionalReason(type, id, reason);

  @override
  List<Object?> get equalityFields => <Object?>[reason];
}

final class CallEndMessage extends IdOnlyMessage {
  const CallEndMessage({required super.id});

  @override
  ControlMessageType get kind => ControlMessageType.callEnd;
}

final class PairConfirmedMessage extends PeerControlMessage {
  const PairConfirmedMessage({required super.id, this.discovery});

  @override
  ControlMessageType get kind => ControlMessageType.pairConfirmed;

  /// The 43 character WebRTC capability, echoed back once the human-verification
  /// step completed over the encrypted channel. `null` when the peer omitted it.
  final String? discovery;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'id': id,
    if (discovery != null) 'discovery': discovery,
  };

  @override
  List<Object?> get equalityFields => <Object?>[discovery];
}

/// Each device announces the name it chose for itself; the peer may still alias
/// it locally. The `name` is run through `safeDisplayName` by the parser.
final class ProfileMessage extends PeerControlMessage {
  const ProfileMessage({required super.id, required this.name});

  @override
  ControlMessageType get kind => ControlMessageType.profile;

  final String name;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'id': id,
    'name': name,
  };

  @override
  List<Object?> get equalityFields => <Object?>[name];
}

/// Builds the JSON of a decline/cancel frame, omitting an absent reason so the
/// frame is byte-identical to what `JSON.stringify` produced for `undefined`.
Map<String, Object?> _withOptionalReason(
  String type,
  String id,
  String? reason,
) => <String, Object?>{'type': type, 'id': id, 'reason': ?reason};
