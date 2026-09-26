/// The network seam: two reads, one whole document and one byte stream.
///
/// Every side effect of the update client goes through here, which is what lets
/// `test/update` drive an entire update - including a download that is cut in
/// half, one that runs past its cap, and one that is cancelled - with no
/// socket, no server and no clock.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// The one way to stop a transfer that is already running.
///
/// A handle rather than a flag on the client, so a cancel aimed at one attempt
/// cannot reach another, and so the transport has something to watch. The client
/// aborts on its own when the byte cap trips, which is why a transport that
/// ignores [AbortToken] still cannot fill a disk: the cap is counted in the
/// client, not delegated.
final class AbortToken {
  final Completer<void> _aborted = Completer<void>();

  /// Whether somebody has asked for this transfer to stop.
  bool get isAborted => _aborted.isCompleted;

  /// Completes the first time [abort] is called. Transports may race their read
  /// against this; a per-chunk check is the portable minimum.
  Future<void> get whenAborted => _aborted.future;

  /// Asks for the transfer to stop. Idempotent.
  void abort() {
    if (!_aborted.isCompleted) _aborted.complete();
  }
}

/// What one read of the feed produced.
sealed class FeedRead {
  const FeedRead();
}

/// A body, and the length the server claimed for it when it claimed one.
final class FeedReadOk extends FeedRead {
  const FeedReadOk({required this.body, required this.declaredLength});

  final List<int> body;

  /// `Content-Length`, or null when the response carried none or an unreadable
  /// one. Never guessed: a truncated body has to be reported as truncated.
  final int? declaredLength;

  @override
  String toString() =>
      'FeedReadOk(${body.length} bytes, declared: $declaredLength)';
}

/// The feed is past the cap. A separate answer rather than a thrown error,
/// because a 40 MB "manifest" is a different thing from a connection that
/// failed, and the user is told so.
final class FeedReadTooLarge extends FeedRead {
  const FeedReadTooLarge();

  @override
  String toString() => 'FeedReadTooLarge()';
}

/// The read never completed.
///
/// [detail] is for a log line and is never shown: it is whatever the transport
/// produced, which may be a URL, an IP or an English exception, and none of those
/// belong in a notice.
final class FeedReadFailed extends FeedRead {
  const FeedReadFailed(this.detail);

  final String detail;

  @override
  String toString() => 'FeedReadFailed($detail)';
}

/// One event from a streaming download.
sealed class DownloadEvent {
  const DownloadEvent();
}

/// Something the client can know before the first byte: the length the server
/// claimed, or null when it claimed none.
///
/// Worth its own event for one reason - a server that announces ten gigabytes of
/// "installer" is refused before a single byte is written, rather than after.
final class DownloadAnnounced extends DownloadEvent {
  const DownloadAnnounced(this.declaredLength);

  final int? declaredLength;

  @override
  String toString() => 'DownloadAnnounced(declared: $declaredLength)';
}

/// Some bytes, in the order they arrived. The only event that writes to disk.
final class DownloadChunk extends DownloadEvent {
  const DownloadChunk(this.bytes);

  final List<int> bytes;

  @override
  String toString() => 'DownloadChunk(${bytes.length} bytes)';
}

/// The source ended on its own. [declaredLength] is the server's `Content-Length`
/// when there was one, so a body that arrived short can be told from a complete
/// one.
final class DownloadComplete extends DownloadEvent {
  const DownloadComplete(this.declaredLength);

  final int? declaredLength;

  @override
  String toString() => 'DownloadComplete(declared: $declaredLength)';
}

/// The transport stopped itself at the cap it was given. The client treats this
/// and its own count tripping as the same failure, so the transport may enforce
/// the cap, ignore it, or land exactly on it.
final class DownloadLimitReached extends DownloadEvent {
  const DownloadLimitReached();

  @override
  String toString() => 'DownloadLimitReached()';
}

/// The [AbortToken] fired. The partial file is removed; nothing is offered.
final class DownloadAborted extends DownloadEvent {
  const DownloadAborted();

  @override
  String toString() => 'DownloadAborted()';
}

/// The transfer broke. [detail] is a log line, never shown to a user.
final class DownloadFailed extends DownloadEvent {
  const DownloadFailed(this.detail);

  final String detail;

  @override
  String toString() => 'DownloadFailed($detail)';
}

/// Everything the update client needs from the network.
///
/// Two methods rather than one, because the two transfers have nothing in
/// common: the feed is a small document read to the end, and the artefact is a
/// stream that has to be countable while it is written and stoppable while it
/// runs. Both are told the cap they must respect; neither is trusted to enforce
/// it.
abstract class HttpFetcher {
  /// Reads a whole small document.
  Future<FeedRead> read(
    Uri url, {
    required int maxBytes,
    required AbortToken abort,
  });

  /// Streams an artefact.
  Stream<DownloadEvent> download(
    Uri url, {
    required int maxBytes,
    required AbortToken abort,
  });
}

/// The production [HttpFetcher], over `package:http`.
///
/// Small on purpose: this file is a transport, not a policy. The cap, the
/// abort, the file, the verification and the order they happen in all belong to
/// [UpdateClient], which is the only place that can be tested without a network.
///
/// The byte cap is passed to the transport as well, and the transport stops at
/// it - but the client counts for itself, because a transport that forgets the
/// cap must not be able to fill a disk.
final class HttpUpdateFetcher implements HttpFetcher {
  /// Uses [client] if given, and otherwise creates one it owns and closes on
  /// [close]. Nothing else closes it.
  HttpUpdateFetcher({http.Client? client})
    : _client = client,
      _ownsClient = client == null;

  final http.Client? _client;
  final bool _ownsClient;

  http.Client get _http {
    final http.Client? client = _client;
    if (client != null) return client;
    throw StateError('HttpUpdateFetcher was closed.');
  }

  /// Closes the underlying client, but only when this instance created it.
  void close() {
    if (_ownsClient) _client?.close();
  }

  @override
  Future<FeedRead> read(
    Uri url, {
    required int maxBytes,
    required AbortToken abort,
  }) async {
    if (abort.isAborted) return const FeedReadFailed('aborted before start');
    try {
      final http.Response response = await _http.get(url);
      final int? declared = _contentLength(response.headers);
      // Checked before decoding: a body past the cap is refused without ever
      // becoming a string, so a hostile 200 MB "manifest" costs one length.
      if (response.bodyBytes.length > maxBytes) {
        return const FeedReadTooLarge();
      }
      if (declared != null && declared > response.bodyBytes.length) {
        // The server promised more than it sent. A short body is a failed read,
        // never a short manifest.
        return FeedReadFailed('body shorter than content-length');
      }
      return FeedReadOk(body: response.bodyBytes, declaredLength: declared);
    } on Object catch (error) {
      return FeedReadFailed('$error');
    }
  }

  @override
  Stream<DownloadEvent> download(
    Uri url, {
    required int maxBytes,
    required AbortToken abort,
  }) async* {
    if (abort.isAborted) {
      yield const DownloadAborted();
      return;
    }
    final http.StreamedResponse response;
    try {
      response = await _http.send(http.Request('GET', url));
    } on Object catch (error) {
      yield DownloadFailed('$error');
      return;
    }
    if (response.statusCode != 200) {
      // A 404 is the failure this product shipped with: the endpoint in
      // `src-tauri/tauri.conf.json:43` points at a repository that does not
      // exist. It is a transport failure here, not a malformed manifest, so the
      // user is told the server could not be reached rather than that the
      // document made no sense.
      yield DownloadFailed('http ${response.statusCode}');
      return;
    }
    final int? declared = _contentLength(response.headers);
    yield DownloadAnnounced(declared);
    if (declared != null && declared > maxBytes) {
      // Refused before any byte is written.
      yield const DownloadLimitReached();
      return;
    }
    int received = 0;
    try {
      await for (final List<int> chunk in response.stream) {
        if (abort.isAborted) {
          // Leaving the loop cancels the subscription, which is what releases
          // the socket; a cancelled transfer must not hold a connection open
          // while its partial file is deleted.
          yield const DownloadAborted();
          return;
        }
        received += chunk.length;
        if (received > maxBytes) {
          yield const DownloadLimitReached();
          return;
        }
        yield DownloadChunk(chunk);
      }
    } on Object catch (error) {
      yield DownloadFailed('$error');
      return;
    }
    if (abort.isAborted) {
      yield const DownloadAborted();
      return;
    }
    yield DownloadComplete(declared);
  }
}

/// Reads `Content-Length` without trusting it to parse.
///
/// `http.Response.contentLength` throws on a malformed header, and a header is
/// attacker-reachable input; a value that cannot be read is reported as absent
/// so the client's own count is the only number it relies on.
int? _contentLength(Map<String, String> headers) {
  final String? raw = headers['content-length'];
  if (raw == null) return null;
  final int? value = int.tryParse(raw.trim());
  return value != null && value >= 0 ? value : null;
}
