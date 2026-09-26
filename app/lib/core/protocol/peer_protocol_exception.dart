/// Raised for every protocol-level violation: an oversized frame, a frame that
/// is not a known control shape, or a binary frame that does not belong to an
/// accepted transfer.
///
/// Dart has no error type that can carry a Turkish protocol message without
/// pretending to be a crash, so this one class does that job for both the
/// protocol violations and a decode failure; [cause] keeps the underlying
/// `FormatException` for logs.
final class PeerProtocolException implements Exception {
  const PeerProtocolException(this.message, [this.cause]);

  /// Turkish, and a compatibility surface: a peer's UI renders some of these
  /// verbatim.
  final String message;

  /// The decoder or arithmetic failure that triggered this, when there was one.
  final Object? cause;

  @override
  String toString() => 'PeerProtocolException: $message';
}
