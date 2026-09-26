/// The encrypted peer record and the store that reads it.
///
/// `src/services/local-security.ts:30-43` is the TypeScript original. Two things
/// are structurally different here, and both of them are the white pairing
/// screen:
///
/// 1. `loadKnownPeer()` returns `KnownPeer | null`, and a REJECTED promise also
///    leaves `knownPeer` null on the React side (`src/App.tsx:153-165`: the
///    `.catch` only called `setNotice`). So "this device has never paired" and
///    "the store could not be read" were the same value, and
///    `src/App.tsx:545` gated the pairing screen on it. [PeerReadResult] has
///    three answers, not two, and none of them is a nullable peer.
/// 2. Nothing here is allowed to throw out of `readPeer()`. A throw is still
///    legal, and [SessionBootstrap] maps it to
///    [PeerStoreUnavailable], but a store that expresses failure as a value
///    cannot be forgotten at a call site.
library;

import 'dart:convert';

import 'package:mkvi/core/protocol/text_sanitizer.dart';

/// One paired peer.
///
/// MKVI pairs one device with exactly one peer, so this is a single value and
/// not a list. `src/services/local-security.ts:36-43` already narrows the
/// stored list to `peers[0]`, and a multi-peer shape would only let the UI lie
/// about how many people are on the other end.
final class KnownPeer {
  const KnownPeer({
    required this.publicKey,
    required this.discoveryId,
    required this.announcedName,
    required this.pairedAtMs,
  });

  /// Builds the record a finished pairing writes, with the `src/App.tsx:438`
  /// downgrade fixed.
  ///
  /// The TypeScript original wrote
  /// `display_name: peerAnnouncedName || defaultPeerName`, and
  /// `peerAnnouncedName` is only set once the peer's `profile` frame arrives.
  /// Re-pairing therefore replaced a name the user had been looking at for
  /// months with the placeholder `"Kişi"` every single time the channel came
  /// up before the profile did. [freshAnnouncedName] may be null or empty here,
  /// and [previousAnnouncedName] survives that.
  factory KnownPeer.forPairing({
    required String publicKey,
    required String discoveryId,
    required int pairedAtMs,
    String? freshAnnouncedName,
    String? previousAnnouncedName,
  }) => KnownPeer(
    publicKey: publicKey,
    discoveryId: discoveryId,
    announcedName: resolveStoredAnnouncedName(
      fresh: freshAnnouncedName,
      stored: previousAnnouncedName ?? '',
    ),
    pairedAtMs: pairedAtMs,
  );

  /// The placeholder shown when a peer has never announced a name. TS:
  /// `defaultPeerName` at `src/App.tsx:31`.
  static const String defaultAnnouncedName = 'Kişi';

  /// The peer's Ed25519 public key. This is the peer's identity; every alias
  /// is scoped to it and nothing else.
  final String publicKey;

  /// The pair capability that routes to the Durable Object. Also a bearer
  /// secret, which is why it is never put on a log line or an event stream.
  final String discoveryId;

  /// The name the peer announced for ITSELF, or the placeholder.
  ///
  /// This is the identity of the peer, and it is the only name that is ever
  /// persisted. A local alias is not a peer attribute and must never land
  /// here; see [PeerAliasStore].
  final String announcedName;

  /// Unix milliseconds, matching the `paired_at_ms` the Rust command expects.
  final int pairedAtMs;

  /// The record exactly as the store holds it.
  ///
  /// Snake case and the four original key names, because the crate that
  /// encrypts and decrypts this record is not Dart: renaming a key here would
  /// read as a record that does not exist.
  Map<String, Object?> toJson() => <String, Object?>{
    'public_key': publicKey,
    'discovery_id': discoveryId,
    'display_name': announcedName,
    'paired_at_ms': pairedAtMs,
  };

  /// The bytes handed to the store's encryption. This is the "serialized
  /// form" a test asserts against: a local alias must never appear in it.
  String encode() => jsonEncode(toJson());

  KnownPeer copyWith({
    String? publicKey,
    String? discoveryId,
    String? announcedName,
    int? pairedAtMs,
  }) => KnownPeer(
    publicKey: publicKey ?? this.publicKey,
    discoveryId: discoveryId ?? this.discoveryId,
    announcedName: announcedName ?? this.announcedName,
    pairedAtMs: pairedAtMs ?? this.pairedAtMs,
  );

  @override
  String toString() =>
      'KnownPeer(${maskCapability(discoveryId)}, $announcedName)';
}

/// Hides a bearer capability in a log line without hiding the fact that there
/// is one. `src/App.tsx` had no equivalent, which is how a discovery id ended
/// up in a user-facing notice more than once.
String maskCapability(String capability) =>
    capability.length <= 6 ? '***' : '${capability.substring(0, 6)}…';

/// The announced name a finished pairing persists.
///
/// A fresh, sanitised, non-empty name always wins. Otherwise the previously
/// stored one is kept, even when that one is the placeholder: downgrading a
/// known name to `"Kişi"` because a `profile` frame was late is the defect
/// this function exists to remove.
String resolveStoredAnnouncedName({
  required String? fresh,
  required String stored,
}) {
  final String candidate = fresh == null ? '' : safeDisplayName(fresh);
  if (candidate.isNotEmpty) return candidate;
  return stored;
}

/// The three answers a peer read can have.
///
/// [PeerAbsent] and [PeerUnreadable] are separate cases on purpose, and that
/// separation IS the fix for the white pairing screen: the pairing screen is
/// reachable from [PeerAbsent] alone.
sealed class PeerReadResult {
  const PeerReadResult();
}

/// No pairing has ever been completed on this device. The only read result
/// that may lead to the pairing screen.
final class PeerAbsent extends PeerReadResult {
  const PeerAbsent();
}

/// A peer was paired and is readable.
final class PeerFound extends PeerReadResult {
  const PeerFound(this.peer);

  final KnownPeer peer;
}

/// A peer WAS paired and cannot be read.
///
/// This is not "there is no peer", and it must never be rendered as though it
/// were. [failure] carries Turkish text the user can act on.
final class PeerUnreadable extends PeerReadResult {
  const PeerUnreadable(this.failure);

  final PeerReadFailure failure;
}

/// Why a paired device could not be read. Each case is separately actionable,
/// because "the store did not open" and "the key is gone" need different things
/// from the user.
sealed class PeerReadFailure {
  const PeerReadFailure();

  /// One Turkish sentence saying what happened.
  String get message;

  /// One Turkish sentence saying what the user can do about it.
  String get recovery;

  @override
  String toString() => message;
}

/// The bridge to the encrypted store is unavailable: a missing plugin, a
/// revoked permission, a process that has not finished starting.
final class PeerStoreUnavailable extends PeerReadFailure {
  const PeerStoreUnavailable();

  @override
  String get message =>
      'Kayıtlı eş bilgisi okunamadı: güvenli depoya erişilemiyor.';

  @override
  String get recovery =>
      'Uygulamayı yeniden başlat. Sorun sürerse cihazdaki güvenli depoyu kontrol et.';
}

/// The record exists but will not decrypt: the pairing key on this device no
/// longer matches the one the record was written with.
final class PeerDecryptFailed extends PeerReadFailure {
  const PeerDecryptFailed();

  @override
  String get message =>
      'Kayıtlı eş bilgisi çözülemedi: bu cihazdaki anahtar kaydı açamıyor.';

  @override
  String get recovery =>
      'Bu cihazda eşleşme anahtarı değişmiş. Yeni bir cihaz eşleştirmen gerekiyor.';
}

/// The keyring has no entry for this record at all: the OS keystore was reset,
/// or the app's key was removed.
final class PeerKeyringEntryMissing extends PeerReadFailure {
  const PeerKeyringEntryMissing();

  @override
  String get message =>
      'Kayıtlı eş bilgisi bulunamadı: cihaz kasasındaki anahtar kayıp.';

  @override
  String get recovery =>
      'İşletim sistemi kasası sıfırlanmış olabilir. Yeni bir cihaz eşleştirmen gerekiyor.';
}

/// The row is present and shaped wrong: truncated by a crash, written by a
/// future build, or hand-edited.
final class PeerRecordCorrupt extends PeerReadFailure {
  const PeerRecordCorrupt();

  @override
  String get message => 'Kayıtlı eş bilgisi bozuk: eş kaydı okunamadı.';

  @override
  String get recovery => 'Eş kaydı silip yeni bir cihaz eşleştirmen gerekiyor.';
}

/// The encrypted peer store.
///
/// The Rust bridge behind `src/services/local-security.ts` does not exist in
/// the Flutter port yet, so this is an interface and a test injects a fake.
/// Production will implement it over `flutter_secure_storage` plus the same
/// `mkvi_core` record format; nothing above this line changes when it arrives.
abstract class PeerStore {
  /// Reads the stored peer. Must not throw; see the library header.
  Future<PeerReadResult> readPeer();

  /// Encrypts and writes [peer], replacing whatever was stored.
  Future<void> writePeer(KnownPeer peer);
}

/// Decodes one stored value into a [PeerReadResult], mapping every rejection to
/// [PeerRecordCorrupt] rather than throwing.
///
/// `jsonDecode` hands back `Map<String, dynamic>`; this takes
/// `Map<Object?, Object?>` so no `dynamic` is ever written in this library, and
/// so a row with unexpected key types becomes a state instead of a
/// `TypeError` escaping a `Future`.
///
/// An absent `display_name` is NOT corruption: a record written by 0.1.0 before
/// the name was persisted decodes to an empty announced name, which the UI then
/// shows as [KnownPeer.defaultAnnouncedName].
PeerReadResult decodeStoredPeer(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return const PeerUnreadable(PeerRecordCorrupt());
  }
  final Object? publicKey = value['public_key'];
  final Object? discoveryId = value['discovery_id'];
  if (publicKey is! String || publicKey.isEmpty) {
    return const PeerUnreadable(PeerRecordCorrupt());
  }
  if (discoveryId is! String || discoveryId.isEmpty) {
    return const PeerUnreadable(PeerRecordCorrupt());
  }
  final Object? displayName = value['display_name'];
  final Object? pairedAt = value['paired_at_ms'];
  return PeerFound(
    KnownPeer(
      publicKey: publicKey,
      discoveryId: discoveryId,
      // A stored name is peer-supplied text written by some build of this app,
      // so it is sanitised on the way out of the store as well as on the way
      // in. Sanitising on read means no future call site can forget.
      announcedName: displayName is String ? safeDisplayName(displayName) : '',
      pairedAtMs: pairedAt is num ? pairedAt.toInt() : 0,
    ),
  );
}
