/// A hand-driven [SignalingSocket] for tests.
///
/// The real socket is a network connection with its own timing, so the client is
/// given this instead: a test decides exactly when the socket opens, which frames
/// arrive, whether it errors and with which code it closes. No server, no port,
/// no waiting - which is what makes the "a message arrives before onopen" and
/// "the socket closes after the future settled" cases testable at all.
library;

import 'dart:convert';

import 'package:mkvi/signaling/rendezvous_client.dart';

/// A [SignalingSocket] whose every event is fired by the test.
class FakeSocket implements SignalingSocket {
  FakeSocket(this.url);

  /// The URL the client asked for, already built and encoded.
  final Uri url;

  int _readyState = SignalingSocket.connecting;

  /// Every frame the client sent, in order.
  final List<String> sent = <String>[];

  /// Every `close()` call, in order, with the arguments the client chose.
  final List<({int? code, String? reason})> closeCalls = <({int? code, String? reason})>[];

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

  /// Completes the handshake.
  void emitOpen() {
    _readyState = SignalingSocket.open;
    onOpen?.call();
  }

  /// Delivers one text frame.
  void emitMessage(String data) => onMessage?.call(data);

  /// Delivers one frame built from a JSON value, for readability in tests.
  void emitJson(Object? value) => emitMessage(jsonEncode(value));

  /// Reports a transport error.
  void emitError([Object? error]) => onError?.call(error ?? StateError('test error'));

  /// Reports a close. Use [code] 1006 to imitate a dropped connection.
  void emitClose({int code = 1006, String reason = ''}) {
    _readyState = SignalingSocket.closed;
    onClose?.call(SignalingCloseEvent(code, reason));
  }

  @override
  void send(String data) => sent.add(data);

  @override
  void close([int? code, String? reason]) {
    closeCalls.add((code: code, reason: reason));
    _readyState = SignalingSocket.closed;
  }
}

/// A [SignalingSocketFactory] that records every URL it was asked for and hands
/// back [FakeSocket]s, so a test can assert on the URL without a server.
class RecordingSocketFactory {
  final List<Uri> urls = <Uri>[];
  final List<FakeSocket> sockets = <FakeSocket>[];

  SignalingSocket call(Uri url) {
    urls.add(url);
    final FakeSocket socket = FakeSocket(url);
    sockets.add(socket);
    return socket;
  }

  /// The most recently created socket.
  FakeSocket get last => sockets.last;
}
