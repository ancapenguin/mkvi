/// Raised for every protocol-level violation: an oversized frame, a frame that
/// is not a known control shape, or a binary frame that does not belong to an
/// accepted transfer.
///
/// The TypeScript original throws plain `new Error("...")` with a Turkish
/// message and, for malformed JSON, lets the engine's own `SyntaxError`
/// escape. Dart has no error type that can carry a Turkish protocol message
/// without pretending to be a crash, so this one class does that job for both
/// cases; [cause] keeps the underlying `FormatException` for logs.
final class PeerProtocolException implements Exception {
  const PeerProtocolException(this.message, [this.cause]);

  /// Turkish, byte-identical to the corresponding `new Error(...)` literal.
  final String message;

  /// The decoder or arithmetic failure that triggered this, when there was one.
  final Object? cause;

  @override
  String toString() => 'PeerProtocolException: $message';
}
