/// Single source of truth for every constant of the MKVI peer wire protocol.
///
/// This file is the **only** place a wire number or a wire string is written
/// down. Nothing else in `lib/core/protocol` may hard-code one, and a limit that
/// lives in two places is a limit that will be changed in one of them.
///
/// Why one file rather than a module per concern: a protocol constant that is
/// *partly* private is a constant nobody can find, and a constant duplicated
/// between a "public limits" table and a "private frame" table is how a port
/// silently drifts. Collapsing them removes both failure modes.
///
/// The values here are a **wire contract**, not preferences. The signaling
/// envelope is pinned separately by `vectors/wire-v1.json`; these are the peer
/// channel's numbers, and both ends of a call must agree on them byte for byte.
/// Changing one is a breaking change for every deployed client, not a refactor.
library;

/// Wire limits, frame layout and the user-visible strings of the protocol.
final class PeerProtocol {
  const PeerProtocol._();

  // ---------------------------------------------------------------------
  // Control channel
  // ---------------------------------------------------------------------

  /// Largest control frame, measured in UTF-8 **bytes**.
  static const int maxMessageBytes = 32 * 1024;

  /// A self-chosen display name is a label, not a payload channel; keep it short.
  static const int maxDisplayNameLength = 40;

  /// Cap for the free-text `reason` of decline/cancel frames.
  static const int maxReasonLength = 256;

  /// Cap for a sanitised file name.
  static const int maxFileNameLength = 160;

  /// Cap for a validated media type.
  static const int maxMimeLength = 128;

  /// Raw bytes of a transfer id.
  static const int transferIdBytes = 16;

  /// Hex characters of a transfer id. Derived rather than written, so the
  /// pattern and the id length cannot disagree.
  static const int transferIdLength = transferIdBytes * 2;

  /// Largest offerable file.
  static const int maxFileBytes = 512 * 1024 * 1024;

  /// How many announced-but-unfinished receives one peer may hold.
  ///
  /// Small on purpose. Every announced-but-unfinished receive is an open file
  /// handle and a promise of disk, and MKVI is a two-person app where a person
  /// rarely has more than a couple of files genuinely in flight. Two is a cap
  /// that a user hits rather than a number they have to reason about.
  static const int maxConcurrentReceives = 2;

  /// `2^53 - 1`, the largest integer a double can hold exactly.
  ///
  /// Dart's `int` is 64-bit, so a declared file size has to be checked against
  /// this bound by hand. Without the check a peer could declare a size that the
  /// sender computed in floating point and the receiver would compute in
  /// integers, and the two would disagree about whether the transfer is
  /// complete.
  static const int maxSafeInteger = 9007199254740991;

  // ---------------------------------------------------------------------
  // Binary file frames
  // ---------------------------------------------------------------------

  /// First byte of every binary frame.
  static const int fileFrameTag = 1;

  /// `tag (1 byte) + transfer id (16 raw bytes)`.
  static const int fileFrameHeaderBytes = 1 + transferIdBytes;

  /// Payload bytes per emitted frame.
  static const int fileChunkBytes = 16 * 1024;

  /// The 4 MB batching cap that a WebView-based transport needed.
  ///
  /// This number only ever existed to cap the heap of a **WebView**, which
  /// buffered received bytes in JavaScript and handed them to the sink in
  /// batches. A Flutter desktop build has no WebView and no JS heap: the
  /// transport writes through `dart:io` straight to a file handle, so the
  /// batching cap has no meaning here. It is kept — and defined here, and only
  /// here — so that whoever introduces a buffering sink can reuse it or delete
  /// it in a single edit instead of hunting down a duplicated 4 MB.
  static const int fileFlushBytes = 4 * 1024 * 1024;

  // ---------------------------------------------------------------------
  // Pairing code
  // ---------------------------------------------------------------------

  /// 32 unambiguous characters, so `byte % 32` is unbiased.
  ///
  /// Ambiguous means `I`/`1`, `O`/`0` and every pair a person can misread when
  /// reading a code aloud or copying it from a screen. The alphabet is also
  /// exactly 32 characters, which is what makes the modulo reduction free of the
  /// modulo bias that a 26- or 36-character alphabet would introduce.
  static const String pairingCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Random bytes per pairing code, drawn from a cryptographic source.
  static const int pairingCodeLength = 13;

  /// `log2(32) * 13 = 65` bits of entropy. Named by the test "creates 65-bit,
  /// unambiguous codes".
  static const int pairingCodeBits = pairingCodeLength * 5;

  /// Longest input the normaliser will consider. A pasted code may carry spaces
  /// or separators, so the cap is above [pairingCodeLength].
  static const int pairingCodeMaxLength = 16;

  // ---------------------------------------------------------------------
  // Capabilities
  // ---------------------------------------------------------------------

  /// Length of the WebRTC capability string echoed back in `pair-confirmed`
  /// and in the reconnect `session` of an identity signal.
  ///
  /// 43 characters is the length of an unpadded base64url encoding of 32 bytes,
  /// which is an Ed25519 public key. The value is an *identifier*, not a
  /// capability list: it is a constant, compared for equality to decide whether
  /// two peers speak the same protocol.
  static const int capabilityLength = 43;

  // ---------------------------------------------------------------------
  // Fallbacks
  // ---------------------------------------------------------------------

  /// Used when a file's declared media type is missing or fails validation.
  static const String defaultMimeType = 'application/octet-stream';

  /// Used when a file's declared name is missing or fails validation. Turkish,
  /// because it is what the receiving user sees in their download folder.
  static const String defaultFileName = 'dosya';

  // ---------------------------------------------------------------------
  // Wire patterns
  //
  // Spelled out with literal counts so they read exactly like the regular
  // expressions they encode. `protocolConstantsTest.dart` asserts that each
  // count still agrees with the constant above, so the two cannot drift.
  // ---------------------------------------------------------------------

  /// A transfer id: 32 lowercase hex characters.
  static final RegExp transferIdPattern = RegExp(r'^[a-f0-9]{32}$');

  /// A capability string: 43 base64url characters.
  static final RegExp capabilityPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  /// The ranges a normalised pairing code's first character may fall in.
  /// Exposed as the alphabet ranges `A-H`, `J-N`, `P-Z` and `2-9`; see
  /// `normalizePairingCode`.
  static const String pairingCodeFirstRange = 'A-H';
  static const String pairingCodeSecondRange = 'J-N';
  static const String pairingCodeThirdRange = 'P-Z';
  static const String pairingCodeDigits = '2-9';

  // ---------------------------------------------------------------------
  // User-visible / peer-visible protocol strings
  //
  // Every string the protocol can put on the wire, or raise as a protocol
  // error, in one place. Turkish, and a compatibility surface: a peer's UI
  // renders several of these verbatim, so they are a wire contract too.
  // ---------------------------------------------------------------------

  /// Raised when a control frame exceeds [maxMessageBytes].
  static const String messageTooLarge = 'Kontrol mesajı çok büyük.';

  /// The single error raised for every rejected control shape. One message for
  /// all of them on purpose: the peer learns that the frame is unacceptable and
  /// nothing else, and a parser that explains *which* rule it broke is a parser
  /// that hands an attacker an oracle.
  static const String invalidControlMessage = 'Geçersiz kontrol mesajı.';

  /// The same discipline applied to a rendezvous payload, which the peer channel
  /// never parsed and which is therefore named here. It has no wire counterpart
  /// of its own; the wording mirrors [invalidControlMessage].
  static const String invalidSignalMessage = 'Geçersiz sinyal mesajı.';

  /// Raised for a binary frame whose length or tag is wrong.
  static const String invalidFrame = 'Geçersiz veri çerçevesi.';

  /// Raised when a frame arrives for a transfer this device never accepted.
  ///
  /// The reason this is a distinct string and not [invalidFrame]: a peer that
  /// streams data for an unaccepted transfer is either badly desynchronised or
  /// is sending something it was not offered, and those want different answers.
  static const String unauthorizedFileData =
      'İzin verilmeyen dosya verisi alındı.';

  /// Raised when a frame would push a transfer past its declared size.
  static const String fileSizeOverflow = 'Dosya beklenen boyutu aşıyor.';

  /// The auto-decline sent when [maxConcurrentReceives] is reached.
  static const String tooManyPendingTransfers =
      'Çok fazla bekleyen aktarım var.';

  /// Sent when a peer re-announces a transfer id that is already live.
  ///
  /// The alternative is to silently replace the live transfer, which resets the
  /// progress the user is watching and never counts the repeat against
  /// [maxConcurrentReceives] — so a peer can re-announce forever and the cap
  /// never moves. Refusing the repeat is what keeps the cap honest.
  static const String transferAlreadyReceiving =
      'Bu dosya zaten alınıyor.';

  /// Raised when an accept names a transfer id this device does not hold.
  static const String transferNotFound = 'Dosya teklifi bulunamadı.';

  /// Raised when the sink refuses to create the destination file.
  static const String sinkOpenFailed = 'Dosya diske açılamadı.';

  /// Raised when a transfer closes having received fewer bytes than it declared.
  static const String transferIncomplete = 'Dosya aktarımı eksik tamamlandı.';

  /// The `reason` a decline carries when the declining side gave none.
  static const String defaultFileDeclineReason = 'Alıcı dosyayı kabul etmedi.';

  /// The `reason` a cancel carries when the cancelling side gave none.
  static const String defaultFileCancelReason = 'Aktarım iptal edildi.';

  /// The `reason` a call decline carries when the declining side gave none.
  static const String defaultCallDeclineReason = 'Arama reddedildi.';

  /// The receiver-side fallback when a `file-decline` carries no reason.
  static const String fileDeclinedReason = 'Dosya reddedildi.';

  /// The receiver-side fallback when a `file-cancel` carries no reason.
  static const String fileCancelledReason = 'Dosya iptal edildi.';

  /// The auto-decline reason sent when a call arrives during another call.
  static const String busyCallReason = 'Meşgul.';
}
