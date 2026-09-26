/// Every Turkish string the chat and file-transfer layer can produce, in one file.
///
/// The TypeScript original mixed languages exactly here. `ChatCallWorkspace.tsx`
/// had Turkish labels in its JSX but an **English** `state` union
/// (`"active" | "done" | "failed"`) that it dropped straight into a class name
/// (`className={`mkvi-transfer is-${transfer.state}`}`), `App.tsx` raised
/// `setNotice("Message not stored locally.")`-shaped English falls-through
/// branches, and `formatBytes` used `.` as the decimal separator while every
/// neighbouring string was `tr-TR`. A Turkish/English split like that is not
/// cosmetic: the layer is rendered, read aloud and screen-read by a Turkish
/// user, so the split *is* the defect.
///
/// Two rules make it structural rather than a matter of discipline:
///
/// * [all] enumerates every constant in this class, and
///   `test/chat/chat_messages_test.dart` reads this source file and fails if a
///   `static const String` exists that is not a key of [all]. A new string
///   cannot be added without being registered.
/// * Anything that is already a *wire* string is **reused** from `PeerProtocol`
///   rather than copied. `transferNotFound`, `sinkOpenFailed`,
///   `transferIncomplete`, `defaultFileDeclineReason`, `defaultFileCancelReason`
///   and `tooManyPendingTransfers` all appear on a `reason` field, so a local
///   copy could drift from the text the peer already displays.
///
/// Every number that is a protocol limit is read from `PeerProtocol` at call
/// time, never written out. A literal "512 MB" here is a port that will still
/// claim 512 MB after the cap is changed in one place.
library;

import 'package:mkvi/core/protocol/file_transfer.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';

/// The chat and transfer layer's own user-facing text. Turkish, like every
/// other user-facing string in the port.
final class ChatMessages {
  const ChatMessages._();

  // ---------------------------------------------------------------------
  // Chat: the composer and the timeline
  // ---------------------------------------------------------------------

  /// TS: the empty chat headline, `ChatCallWorkspace.tsx:571`.
  static const String emptyChatTitle = 'Güvenli sohbet hazır';

  /// TS: the empty chat body, `ChatCallWorkspace.tsx:571`.
  static const String emptyChatBody =
      'Mesajlar yalnızca eşleşen cihazlar arasında gönderilir.';

  /// TS: the `aria-label` of the message log, `ChatCallWorkspace.tsx:570`.
  static const String messageLogLabel = 'Mesajlar';

  /// TS: the read receipt appended to an outgoing message's meta line,
  /// `ChatCallWorkspace.tsx:572`.
  static const String readReceipt = 'Okundu';

  /// TS: the throw of `sendChat` for a blank body, `peer-transport.ts:230`.
  static const String emptyMessage = 'Boş mesaj gönderilemez.';

  /// TS: the generic `sendMessage` catch, `App.tsx:501`.
  static const String sendFailed = 'Mesaj gönderilemedi.';

  /// TS: the throw of `sendMessage` with no transport, `App.tsx:497`.
  static const String peerOffline = 'Karşı cihaz çevrimdışı.';

  /// TS: both `appendLocalHistory` catches, `App.tsx:366` and `App.tsx:500`.
  static const String messageNotStored = 'Mesaj yerelde saklanamadı.';

  /// TS: the `listLocalHistory` catch, `App.tsx:203`.
  static const String historyUnavailable = 'Yerel geçmiş açılamadı.';

  /// Refusal of a send because the in-flight queue is at its bound.
  ///
  /// Not in 0.1.x: there was no queue, so a message composed while the channel
  /// was down was simply thrown away with a notice. This layer keeps the message
  /// instead — and at the bound it must say so rather than dropping the oldest
  /// one, because dropping the oldest is the same silent loss with extra steps.
  static const String queueFull =
      'Bekleyen mesaj sayısı doldu. Bağlantı gelince gönderilecek.';

  /// Label of the retry action on a message that failed to go out.
  static const String retry = 'Yeniden dene';

  /// The notice shown while the data channel is down and messages are held.
  static const String holdingForReconnect =
      'Bağlantı bekleniyor. Yazdığın mesajlar sıraya alındı.';

  // ---------------------------------------------------------------------
  // Chat: the channel seam
  // ---------------------------------------------------------------------

  /// TS: the rejection `close` hands to every pending send, `peer-transport.ts:299`.
  static const String channelClosed = 'Bağlantı kapatıldı.';

  /// TS: the throw of `ensureChannelOpen`, `peer-transport.ts:526`.
  static const String channelNotReady = 'Doğrudan bağlantı henüz hazır değil.';

  /// The refusal for a channel that is up but not taking frames, i.e.
  /// back-pressure rather than a dead connection. No 0.1.x counterpart: the
  /// browser transport threw "Dosya aktarımı zaman aşımına uğradı." after 30 s of
  /// it, which is a timeout reported as if it were a network fault.
  static const String channelBusy = 'Bağlantı şu anda meşgul.';

  // ---------------------------------------------------------------------
  // Chat: day separators and time
  // ---------------------------------------------------------------------

  /// TS: no counterpart — 0.1.x had no day separator at all, so a two-week
  /// conversation and a two-minute one rendered identically.
  static const String today = 'Bugün';

  /// See [today].
  static const String yesterday = 'Dün';

  // ---------------------------------------------------------------------
  // Transfers: the transfer list
  // ---------------------------------------------------------------------

  /// TS: the `aria-label` of the transfer list, `ChatCallWorkspace.tsx:577`.
  static const String transferListLabel = 'Dosya aktarımları';

  /// TS: the `%${percent}` branch of the transfer row, `ChatCallWorkspace.tsx:584`.
  static const String completed = 'Tamamlandı';

  /// TS: the second branch of the same line, `ChatCallWorkspace.tsx:584`.
  static const String failed = 'Başarısız';

  /// Not in 0.1.x: a cancelled transfer was rendered as `failed` with the
  /// cancel reason in the detail line, which made "you stopped this" and "this
  /// broke" indistinguishable in the only place the user could see it.
  static const String cancelled = 'İptal edildi';

  /// The state of a transfer the peer announced and nobody has answered yet.
  static const String awaitingDecision = 'Karar bekleniyor';

  /// The decline notice, `App.tsx:387`.
  static const String offerDeclined = 'Dosya teklifi reddedildi.';

  /// The cancel notice. No 0.1.x counterpart: `cancelFile` rejected the sender's
  /// promise and the receiver only ever saw a vanished row.
  static const String remoteCancelled = 'Karşı taraf aktarımı iptal etti.';

  // ---------------------------------------------------------------------
  // The registered constants
  // ---------------------------------------------------------------------

  /// Every constant declared above, keyed by its name.
  ///
  /// Read by `chat_messages_test.dart`, which also parses this file and fails if
  /// a `static const String` is declared that is missing from here. That is what
  /// makes "one file, no scattered user-facing strings" an invariant rather than
  /// a convention.
  static const Map<String, String> all = <String, String>{
    'emptyChatTitle': emptyChatTitle,
    'emptyChatBody': emptyChatBody,
    'messageLogLabel': messageLogLabel,
    'readReceipt': readReceipt,
    'emptyMessage': emptyMessage,
    'sendFailed': sendFailed,
    'peerOffline': peerOffline,
    'messageNotStored': messageNotStored,
    'historyUnavailable': historyUnavailable,
    'queueFull': queueFull,
    'retry': retry,
    'holdingForReconnect': holdingForReconnect,
    'channelClosed': channelClosed,
    'channelNotReady': channelNotReady,
    'channelBusy': channelBusy,
    'today': today,
    'yesterday': yesterday,
    'transferListLabel': transferListLabel,
    'completed': completed,
    'failed': failed,
    'cancelled': cancelled,
    'awaitingDecision': awaitingDecision,
    'offerDeclined': offerDeclined,
    'remoteCancelled': remoteCancelled,
  };

  // ---------------------------------------------------------------------
  // The formatted strings
  // ---------------------------------------------------------------------

  /// TS: the `sendChat` size guard, `peer-transport.ts:231`.
  ///
  /// The "32 KB" is not written here: it is read out of
  /// [PeerProtocol.maxMessageBytes] through [formatBytes], so the message cannot
  /// claim a cap the parser does not enforce.
  static String messageTooLarge() =>
      'Mesaj en fazla ${formatBytes(PeerProtocol.maxMessageBytes)} olabilir.';

  /// TS: the rejection of `sendFile` for an out-of-range size,
  /// `peer-transport.ts:241`.
  ///
  /// Same discipline as [messageTooLarge]: the 512 MB comes from
  /// [PeerProtocol.maxFileBytes], never from a literal here.
  static String fileSizeOutOfRange() =>
      'Dosya boyutu 1 bayt ile ${formatBytes(PeerProtocol.maxFileBytes)} '
      'arasında olmalı.';

  /// The reason sent on the wire when an announced file is over the cap.
  static String fileOverCap() =>
      'Dosya boyutu en fazla ${formatBytes(PeerProtocol.maxFileBytes)} olabilir.';

  /// The reason sent on the wire when too many transfers are already tracked.
  static String tooManyTransfers() => PeerProtocol.tooManyPendingTransfers;

  /// TS: the transfer row headline, `ChatCallWorkspace.tsx:583`.
  static String transferHeading(TransferDirection direction, String name) =>
      '${direction == TransferDirection.send ? 'Gönderiliyor' : 'Alınıyor'}: $name';

  /// TS: the `aria-label` of the row's close button, `ChatCallWorkspace.tsx:585`.
  static String dismissTransferLabel(String name) => '$name satırını kapat';

  /// TS: the `aria-label` of the progress bar, `ChatCallWorkspace.tsx:587`.
  static String transferProgressLabel(String name) =>
      '$name aktarım ilerlemesi';

  /// TS: the completion notice, `App.tsx:376`.
  static String fileSaved(String name, String path) =>
      '$name kaydedildi: $path';

  /// The `label` for a day boundary, e.g. "Bugün", "Dün" or "14 Eylül 2026".
  ///
  /// [day] and [now] are both local wall-clock times. Hand-rolled instead of
  /// `package:intl`, which is not a dependency of this app: an added dependency
  /// for twelve month names is not worth it, and a locale-sensitive formatter is
  /// exactly the thing that produced the mixed-language UI this file replaces.
  static String dayLabel({required DateTime day, required DateTime now}) {
    final DateTime midnight = DateTime(day.year, day.month, day.day);
    final DateTime todayMidnight = DateTime(now.year, now.month, now.day);
    final int daysApart = midnight.difference(todayMidnight).inDays;
    if (daysApart == 0) return today;
    if (daysApart == -1) return yesterday;
    final String month = _turkishMonths[day.month - 1];
    return day.year == now.year
        ? '${day.day} $month'
        : '${day.day} $month ${day.year}';
  }

  /// The `HH:mm` meta line of one message. TS: `formatTime`,
  /// `ChatCallWorkspace.tsx:102`, which was `Intl.DateTimeFormat("tr-TR", …)`.
  static String messageTime(DateTime value) =>
      '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';

  /// The `transferred / total` detail line. TS: `formatBytes`,
  /// `ChatCallWorkspace.tsx:107`.
  ///
  /// Two deliberate differences from the original, both because the result is
  /// shown to a Turkish reader:
  ///
  /// * the decimal separator is `,`, not `.`, matching `tr-TR`;
  /// * the unit ladder is identical (`B`, `KB`, `MB`, `GB`) and the rounding is
  ///   identical, so `32768` is still "32 KB" and [PeerProtocol.maxFileBytes] is
  ///   still "512 MB".
  static String formatBytes(int value) {
    if (value < 1024) return '$value B';
    const List<String> units = <String>['KB', 'MB', 'GB'];
    double size = value / 1024;
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    final int decimals = (size >= 100 || unit == 0) ? 0 : 1;
    return '${size.toStringAsFixed(decimals).replaceAll('.', ',')} '
        '${units[unit]}';
  }

  /// The `transferred / total` pair under a progress bar.
  static String bytePair(int transferred, int total) =>
      '${formatBytes(transferred)} / ${formatBytes(total)}';

  static const List<String> _turkishMonths = <String>[
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
