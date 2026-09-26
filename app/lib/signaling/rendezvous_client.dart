/// The rendezvous signaling client: one WebSocket, two rooms.
///
/// What a browser client would get from a global, this client gets from an
/// injected [SignalingSocketFactory]. That is the whole test seam: a test hands
/// in a fake, drives open, message, close and error by hand, and never needs a
/// server, a port or a timer.
///
/// ## Three behaviours that are easy to get wrong, and are pinned by the vectors
///
/// 1. **A bad endpoint produces a REJECTED FUTURE** carrying
///    [signalingConnectError]. Building the URL eagerly — outside the returned
///    future — lets a `TypeError: Invalid URL` escape `connect()` as a
///    synchronous throw, so a `.catch()` on the returned future never runs at all
///    and the caller hangs instead of reporting. [buildSignalingUrl] validates
///    first, inside the async path.
/// 2. **A `wss://` endpoint stays `wss://`.** Mapping only `https:` to `wss:`
///    means a user who pastes the `wss://` address silently gets a plaintext
///    `ws://` connection — identity signatures and SDP in the clear, with
///    nothing to indicate it. The `url` cases in `vectors/wire-v1.json` pin this.
/// 3. **A `relay` envelope the Worker would never relay is treated as
///    malformed** and closes with 1003. Forwarding an arbitrary untyped payload
///    means relaying something that cannot be rebuilt into a typed object, so
///    the client would hand its own transport something it cannot handle.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;

import 'query_encoding.dart';
import 'signal_payload.dart';

/// Path of the fifteen-minute, single-use pairing room.
const String rendezvousPath = '/v1/rendezvous';

/// Path of the long-lived, pair-scoped discovery room.
const String peerPath = '/v1/peer';

/// Close code for a message that is not a signaling envelope.
const int closeCodeInvalidMessage = 1003;

/// Close reason sent with [closeCodeInvalidMessage]. Not user-facing text.
const String closeReasonInvalidMessage = 'Invalid signaling message';

/// Shown when the signaling server cannot be reached or the endpoint is unusable.
const String signalingConnectError = 'Signaling sunucusuna bağlanılamadı.';

/// Shown when something is relayed on a socket that is not open.
const String signalingNotOpenError = 'Signaling bağlantısı açık değil.';

/// An error whose `toString()` is exactly the text the user is shown, so a
/// Turkish message is never buried inside an English exception prefix.
class SignalingException implements Exception {
  const SignalingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Why a socket closed, in the shape the client needs to report it.
class SignalingCloseEvent {
  const SignalingCloseEvent(this.code, this.reason);

  final int code;
  final String reason;
}

/// The socket surface [RendezvousClient] needs, and nothing more.
///
/// Keeping it this small is what makes the client testable: `dart:io`'s
/// [WebSocket] is adapted by [IoSignalingSocket], and a test supplies a fake
/// that fires the handlers in whatever order it likes.
abstract class SignalingSocket {
  /// [WebSocket.readyState] values, so callers never hard-code integers.
  static const int connecting = 0;
  static const int open = 1;
  static const int closing = 2;
  static const int closed = 3;

  int get readyState;

  /// Called once the handshake finished.
  void Function()? onOpen;

  /// Called with each text frame. Binary frames are decoded by the adapter.
  void Function(String data)? onMessage;

  void Function(SignalingCloseEvent event)? onClose;
  void Function(Object error)? onError;

  void send(String data);

  void close([int? code, String? reason]);
}

/// Creates the socket for [url]. The single injection point for tests.
typedef SignalingSocketFactory = SignalingSocket Function(Uri url);

/// The production factory: a `dart:io` WebSocket.
SignalingSocket defaultSocketFactory(Uri url) => IoSignalingSocket(url);

/// Adapts `dart:io`'s [WebSocket] to [SignalingSocket].
class IoSignalingSocket implements SignalingSocket {
  IoSignalingSocket(Uri url) {
    WebSocket.connect(url.toString()).then(
      (WebSocket socket) {
        _socket = socket;
        _readyState = SignalingSocket.open;
        onOpen?.call();
        _subscription = socket.listen(
          (Object? frame) => onMessage?.call(_decodeFrame(frame)),
          onError: (Object error) => onError?.call(error),
          onDone: () {
            _readyState = SignalingSocket.closed;
            // A socket torn down without a handshake reports no code at all;
            // 1006 is the reserved "abnormal closure" stand-in.
            onClose?.call(SignalingCloseEvent(socket.closeCode ?? 1006, socket.closeReason ?? ''));
          },
        );
      },
      // A refused connection arrives here, not through `onError`.
      onError: (Object error) {
        _readyState = SignalingSocket.closed;
        onError?.call(error);
      },
    );
  }

  WebSocket? _socket;
  StreamSubscription<Object?>? _subscription;
  int _readyState = SignalingSocket.connecting;

  @override
  int get readyState => _readyState;

  @override
  void Function()? onOpen;

  @override
  void Function(String data)? onMessage;

  @override
  void Function(SignalingCloseEvent event)? onClose;

  @override
  void Function(Object error)? onError;

  static String _decodeFrame(Object? frame) =>
      frame is String ? frame : utf8.decode((frame! as List<int>));

  @override
  void send(String data) => _socket?.add(data);

  @override
  void close([int? code, String? reason]) {
    _readyState = SignalingSocket.closing;
    // Cancel the subscription first, so a frame that is already queued cannot
    // arrive after the caller asked to close.
    _subscription?.cancel();
    _subscription = null;
    _socket?.close(code, reason);
  }
}

/// Builds the signaling URL for [endpoint].
///
/// The path is fixed, so the endpoint's own path, query and fragment are
/// REPLACED rather than merged: the Worker routes on `code`, or on `pair` plus
/// `device`, and an inherited query parameter would be silently dropped data
/// with no error anywhere. `https` and `wss` become `wss`; `http` and `ws`
/// become `ws`; nothing is ever upgraded, so a plaintext endpoint stays
/// plaintext and a TLS endpoint can never be downgraded.
///
/// Throws [SignalingException] with [signalingConnectError] when [endpoint] is
/// not an absolute http, https, ws or wss URL with a host.
Uri buildSignalingUrl(String endpoint, String path, Map<String, String> query) {
  final Uri base;
  try {
    base = Uri.parse(endpoint);
  } on FormatException {
    throw const SignalingException(signalingConnectError);
  }
  const Set<String> allowedSchemes = <String>{'http', 'https', 'ws', 'wss'};
  if (!allowedSchemes.contains(base.scheme) || base.host.isEmpty) {
    throw const SignalingException(signalingConnectError);
  }

  // `https` -> `wss`, `wss` -> `wss`, `http` -> `ws`, `ws` -> `ws`.
  final bool plaintext = base.scheme == 'http' || base.scheme == 'ws';
  final String scheme = plaintext ? 'ws' : 'wss';
  // The URL standard omits a scheme's default port, and so must this.
  final int defaultPort = plaintext ? 80 : 443;
  final Uri target = base.resolve(path);

  return Uri(
    scheme: scheme,
    host: target.host,
    port: target.hasPort && target.port != defaultPort ? target.port : null,
    path: target.path,
    query: encodeQuery(query),
  );
}

/// The signaling client: one socket, one envelope grammar, no mailbox.
///
/// The Durable Object has no per-room mailbox, so a signal sent while the peer
/// is offline is gone. A caller that needs reliability must reconnect and
/// re-announce; that is why [onDisconnect] exists and why it fires at most once
/// per socket.
class RendezvousClient {
  RendezvousClient({this.socketFactory = defaultSocketFactory});

  /// The single test seam: production dials `dart:io`, a test injects a fake.
  final SignalingSocketFactory socketFactory;
  SignalingSocket? _socket;

  /// Joins a pairing room with a 13 character [code].
  Future<void> connect(
    String endpoint,
    String code, {
    required void Function(SignalPayload signal) onSignal,
    required void Function(int peers) onPresence,
    void Function(SignalingCloseEvent event)? onDisconnect,
  }) => _open(endpoint, rendezvousPath, <String, String>{'code': code}, onSignal, onPresence, onDisconnect);

  /// Rejoins a known pair with the opaque [pair] capability and this device's
  /// [device] handle. Only the pair capability routes to a Durable Object; the
  /// device handle exists to enforce the two-device limit.
  Future<void> connectKnown(
    String endpoint,
    String pair,
    String device, {
    required void Function(SignalPayload signal) onSignal,
    required void Function(int peers) onPresence,
    void Function(SignalingCloseEvent event)? onDisconnect,
  }) => _open(endpoint, peerPath, <String, String>{'pair': pair, 'device': device}, onSignal, onPresence, onDisconnect);

  Future<void> _open(
    String endpoint,
    String path,
    Map<String, String> query,
    void Function(SignalPayload signal) onSignal,
    void Function(int peers) onPresence,
    void Function(SignalingCloseEvent event)? onDisconnect,
  ) async {
    // `async` on purpose: a bad endpoint must reject THIS future, never throw
    // synchronously out of the caller's `connect()`.
    final Uri url = buildSignalingUrl(endpoint, path, query);
    final SignalingSocket socket = socketFactory(url);
    _socket = socket;

    final Completer<void> completer = Completer<void>();
    var opened = false;
    var settled = false;
    var disconnectReported = false;

    void rejectOpening() {
      if (settled) return;
      settled = true;
      if (!completer.isCompleted) {
        completer.completeError(const SignalingException(signalingConnectError));
      }
    }

    socket.onOpen = () {
      // A socket that opens after the future settled belongs to a dead attempt.
      if (settled) {
        socket.close();
        return;
      }
      opened = true;
      settled = true;
      if (!completer.isCompleted) completer.complete();
    };
    socket.onError = (Object _) {
      if (!opened) rejectOpening();
    };
    socket.onClose = (SignalingCloseEvent event) {
      final bool isCurrent = identical(_socket, socket);
      if (isCurrent) _socket = null;
      if (!opened) {
        rejectOpening();
        return;
      }
      if (!isCurrent || disconnectReported) return;
      disconnectReported = true;
      onDisconnect?.call(event);
    };
    socket.onMessage = (String data) => _handleMessage(socket, data, onSignal, onPresence);

    return completer.future;
  }

  /// Applies the incoming-message grammar from `vectors/wire-v1.json`.
  ///
  /// Anything that is not a JSON object carrying a `type` is malformed and closes
  /// the socket with 1003: swallowing it would leave the user waiting for a
  /// pairing that can no longer happen. An unknown `type` is ignored instead, so
  /// a future server message cannot crash an old client.
  void _handleMessage(
    SignalingSocket socket,
    String data,
    void Function(SignalPayload signal) onSignal,
    void Function(int peers) onPresence,
  ) {
    void malformed() => socket.close(closeCodeInvalidMessage, closeReasonInvalidMessage);

    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      malformed();
      return;
    }
    if (decoded is! Map || !decoded.containsKey('type')) {
      malformed();
      return;
    }

    final Object? type = decoded['type'];
    if (type == SignalingEnvelope.relayType) {
      final SignalPayload? payload = decodeSignalPayload(decoded['payload']);
      if (payload == null) {
        malformed();
        return;
      }
      onSignal(payload);
      return;
    }
    if (type == 'presence' || type == 'room' || type == 'ready') {
      // `peers` wins when both are present; a null `peers` falls through to
      // `online`, and a message with neither reports nobody.
      onPresence(_peerCount(decoded['peers']) ?? _peerCount(decoded['online']) ?? 0);
      return;
    }
    // Unknown type: ignored on purpose.
  }

  static int? _peerCount(Object? value) => value is num ? value.toInt() : null;

  /// Sends [payload] to the peer. Throws [SignalingException] when the socket is
  /// not open, because a silently dropped offer is a pairing that never happens.
  void relay(SignalPayload payload) {
    final SignalingSocket? socket = _socket;
    if (socket == null || socket.readyState != SignalingSocket.open) {
      throw const SignalingException(signalingNotOpenError);
    }
    socket.send(SignalingEnvelope(payload).encode());
  }

  void close() => _socket?.close();
}
