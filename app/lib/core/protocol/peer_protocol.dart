/// Single source of truth for every constant of the MKVI peer wire protocol.
///
/// The TypeScript original scattered these across two files: the public limits
/// in `src/domain/peer-transport.ts` and the private frame/timing constants at
/// the top of `src/services/peer-transport.ts`. Dart has no equivalent of a
/// partially-private module export, and duplicating a literal is how a port
/// silently drifts, so all of them live here and nothing else in
/// `lib/core/protocol` may hard-code a wire number or a wire string.
library;

/// Wire limits, frame layout and the user-visible strings of the protocol.
final class PeerProtocol {
  const PeerProtocol._();

  // ---------------------------------------------------------------------
  // Control channel
  // ---------------------------------------------------------------------

  /// Largest control frame, measured in UTF-8 **bytes**. TS: `MAX_MESSAGE_BYTES`.
  static const int maxMessageBytes = 32 * 1024;

  /// A self-chosen display name is a label, not a payload channel; keep it short.
  /// TS: `MAX_DISPLAY_NAME_LENGTH`.
  static const int maxDisplayNameLength = 40;

  /// Cap for the free-text `reason` of decline/cancel frames. TS: inline
  /// `.slice(0, 256)` in `parseControl` and in `safeReason`.
  static const int maxReasonLength = 256;

  /// Cap for a sanitised file name. TS: inline `.slice(0, 160)` in `safeName`.
  static const int maxFileNameLength = 160;

  /// Cap for a validated media type. TS: inline `.slice(0, 128)` in `safeMime`.
  static const int maxMimeLength = 128;

  /// Raw bytes of a transfer id. TS: `FILE_ID_BYTES`.
  static const int transferIdBytes = 16;

  /// Hex characters of a transfer id. TS: the `{32}` in `/^[a-f0-9]{32}$/`.
  static const int transferIdLength = transferIdBytes * 2;

  /// Largest offerable file. TS: `MAX_FILE_BYTES`.
  static const int maxFileBytes = 512 * 1024 * 1024;

  /// How many announced-but-unfinished receives one peer may hold.
  /// TS: `MAX_CONCURRENT_RECEIVES`.
  static const int maxConcurrentReceives = 2;

  /// `Number.MAX_SAFE_INTEGER`, i.e. `2^53 - 1`. A Dart `int` is a 64-bit
  /// integer, so this bound has to be re-imposed by hand for the port to accept
  /// exactly the same set of declared sizes as the TypeScript original.
  static const int maxSafeInteger = 9007199254740991;

  // ---------------------------------------------------------------------
  // Binary file frames
  // ---------------------------------------------------------------------

  /// First byte of every binary frame. TS: `FILE_FRAME`.
  static const int fileFrameTag = 1;

  /// `tag (1 byte) + transfer id (16 raw bytes)`. TS: `FILE_HEADER_BYTES`.
  static const int fileFrameHeaderBytes = 1 + transferIdBytes;

  /// Payload bytes per emitted frame. TS: `FILE_CHUNK_BYTES`.
  static const int fileChunkBytes = 16 * 1024;

  /// TS: `FILE_FLUSH_BYTES` (4 MB).
  ///
  /// This number existed only to cap the heap of the Tauri **WebView**, which
  /// buffered received bytes in JavaScript and handed them to the Rust sink in
  /// batches. A Flutter desktop build has no WebView and no JS heap: the
  /// transport writes through `dart:io` straight to a file handle, so the
  /// batching cap has no meaning in the Dart port. It is kept — and defined
  /// here, and only here — so that whoever replaces the WebView sink can reuse
  /// it or delete it in a single edit instead of hunting down a duplicated 4 MB.
  static const int fileFlushBytes = 4 * 1024 * 1024;

  // ---------------------------------------------------------------------
  // Pairing code
  // ---------------------------------------------------------------------

  /// 32 unambiguous characters, so `byte % 32` is unbiased.
  /// TS: the `alphabet` literal in `createPairingCode`.
  static const String pairingCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// TS: `crypto.getRandomValues(new Uint8Array(13))`.
  static const int pairingCodeLength = 13;

  /// `log2(32) * 13 = 65` bits of entropy. Named by the ported test
  /// "creates 65-bit, unambiguous codes".
  static const int pairingCodeBits = pairingCodeLength * 5;

  /// TS: `.slice(0, 16)` in `normalizePairingCode`.
  static const int pairingCodeMaxLength = 16;

  // ---------------------------------------------------------------------
  // Capabilities
  // ---------------------------------------------------------------------

  /// Length of the WebRTC capability string echoed back in `pair-confirmed`
  /// and in the reconnect `session` of an identity signal.
  /// TS: the `{43}` in `/^[A-Za-z0-9_-]{43}$/`.
  static const int capabilityLength = 43;

  // ---------------------------------------------------------------------
  // Fallbacks
  // ---------------------------------------------------------------------

  /// TS: the `safeMime` fallback literal.
  static const String defaultMimeType = 'application/octet-stream';

  /// TS: the `safeName` fallback literal.
  static const String defaultFileName = 'dosya';

  // ---------------------------------------------------------------------
  // Wire patterns
  //
  // Spelled out with literal counts so they read exactly like the TypeScript
  // regular expressions they replace. `protocolConstantsTest.dart` asserts that
  // each count still agrees with the constant above, so the two cannot drift.
  // ---------------------------------------------------------------------

  /// TS: `/^[a-f0-9]{32}$/`.
  static final RegExp transferIdPattern = RegExp(r'^[a-f0-9]{32}$');

  /// TS: `/^[A-Za-z0-9_-]{43}$/`.
  static final RegExp capabilityPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  /// TS: `/^[A-HJ-NP-Z2-9]/` after upper-casing; see `normalizePairingCode`.
  /// Exposed as the alphabet ranges `A-H`, `J-N`, `P-Z` and `2-9`.
  static const String pairingCodeFirstRange = 'A-H';
  static const String pairingCodeSecondRange = 'J-N';
  static const String pairingCodeThirdRange = 'P-Z';
  static const String pairingCodeDigits = '2-9';

  // ---------------------------------------------------------------------
  // User-visible / peer-visible protocol strings
  //
  // Every string the protocol can put on the wire, or raise as a protocol
  // error, in one place. Turkish, byte-identical to the TypeScript originals.
  // ---------------------------------------------------------------------

  /// TS: `parseControl` size guard.
  static const String messageTooLarge = 'Kontrol mesajı çok büyük.';

  /// TS: the single error `parseControl` raises for every rejected shape.
  static const String invalidControlMessage = 'Geçersiz kontrol mesajı.';

  /// The same discipline applied to a rendezvous payload, which the TypeScript
  /// original left to the transport and this port therefore names here. It has
  /// no TypeScript counterpart; the wording mirrors `invalidControlMessage`.
  static const String invalidSignalMessage = 'Geçersiz sinyal mesajı.';

  /// TS: `receiveFrame` length/tag guard.
  static const String invalidFrame = 'Geçersiz veri çerçevesi.';

  /// TS: `receiveFrame` when no accepted transfer owns the frame's id.
  static const String unauthorizedFileData =
      'İzin verilmeyen dosya verisi alındı.';

  /// TS: `receiveFrame` when a frame would push a transfer past its declared size.
  static const String fileSizeOverflow = 'Dosya beklenen boyutu aşıyor.';

  /// TS: the auto-decline sent when `MAX_CONCURRENT_RECEIVES` is reached.
  static const String tooManyPendingTransfers =
      'Çok fazla bekleyen aktarım var.';

  /// Not in 0.1.x: that build silently replaced a live transfer when a peer
  /// re-announced its id, which reset the progress the user was watching and
  /// never counted against the cap. This port refuses the repeat instead.
  static const String transferAlreadyReceiving =
      'Bu dosya zaten alınıyor.';

  /// TS: `acceptFile` when the id is unknown.
  static const String transferNotFound = 'Dosya teklifi bulunamadı.';

  /// TS: `acceptFile` when the sink refuses to create the destination file.
  static const String sinkOpenFailed = 'Dosya diske açılamadı.';

  /// TS: `finishReceive` when fewer bytes arrived than were offered.
  static const String transferIncomplete = 'Dosya aktarımı eksik tamamlandı.';

  /// TS: the `reason` default of `declineFile`.
  static const String defaultFileDeclineReason = 'Alıcı dosyayı kabul etmedi.';

  /// TS: the `reason` default of `cancelFile`.
  static const String defaultFileCancelReason = 'Aktarım iptal edildi.';

  /// TS: the `reason` default of `declineCall`.
  static const String defaultCallDeclineReason = 'Arama reddedildi.';

  /// TS: the receiver-side fallback when a `file-decline` carries no reason.
  static const String fileDeclinedReason = 'Dosya reddedildi.';

  /// TS: the receiver-side fallback when a `file-cancel` carries no reason.
  static const String fileCancelledReason = 'Dosya iptal edildi.';

  /// TS: the auto-decline reason sent when a call arrives during another call.
  static const String busyCallReason = 'Meşgul.';
}
