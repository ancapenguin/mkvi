/// The connection state, as its own channel.
///
/// This enum exists because "something happened" and "the app is broken" were
/// the same `String` in TS. The reconnect loop wrote
/// `Yeniden bağlanılıyor: ${error.message}` into `notice` from inside the loop
/// (`src/App.tsx:289`), so a *condition* was rendered as an *event*: it had a
/// 5.5 s lifetime, it could be closed by the user, and the loop re-opened it
/// about once a second. Two machines reported it as "the bottom-right
/// notification never goes away".
///
/// A [ConnectionStatus] has no text of its own on the notice channel, is never
/// auto-dismissed and cannot be closed by a button: it is read by
/// `NoticeStatusBar` and it stays until the transport says otherwise. The one
/// thing it must never be is a toast.
library;

import 'notice_strings.dart';

/// Where the peer connection is, right now. A state, not an event.
enum ConnectionStatus {
  /// Nothing is being negotiated. The app is up and no channel is wanted.
  idle,

  /// A connection is being negotiated. Normal, and not worth a toast.
  connecting,

  /// The data channel is open.
  online,

  /// A peer exists and cannot currently be reached. Retrying in the background.
  offline,

  /// The last attempt failed outright — a bad endpoint, a refused socket, a
  /// missing key. A state, not a one-off event, so it does not expire.
  error;

  /// The Turkish label for a status strip.
  String get labelTr => switch (this) {
    ConnectionStatus.idle => NoticeTr.statusIdle.tr,
    ConnectionStatus.connecting => NoticeTr.statusConnecting.tr,
    ConnectionStatus.online => NoticeTr.statusOnline.tr,
    ConnectionStatus.offline => NoticeTr.statusOffline.tr,
    ConnectionStatus.error => NoticeTr.statusError.tr,
  };

  /// The Turkish sentence under [labelTr] in a status strip.
  String get detailTr => switch (this) {
    ConnectionStatus.idle => NoticeTr.statusIdleDetail.tr,
    ConnectionStatus.connecting => NoticeTr.statusConnectingDetail.tr,
    ConnectionStatus.online => NoticeTr.statusOnlineDetail.tr,
    ConnectionStatus.offline => NoticeTr.statusOfflineDetail.tr,
    ConnectionStatus.error => NoticeTr.statusErrorDetail.tr,
  };

  /// Whether the app can carry traffic on the peer connection.
  bool get isUsable => this == ConnectionStatus.online;
}
