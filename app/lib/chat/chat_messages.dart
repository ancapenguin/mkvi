/// Every Turkish string the chat and file-transfer layer can produce, in one file.
///
/// The layer is rendered, read aloud and screen-read by a Turkish user, so a
/// Turkish/English split is not cosmetic — **the split is the defect**. It is
/// easy to reintroduce by accident: a state name is an English identifier, a
/// class name is built from it, and a fall-through error branch is a sentence
/// that never got translated. Everything below exists to make that impossible
/// rather than merely discouraged.
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
///
/// This file never grows a `static const String` that is not in [all] — the test
/// above reads the source text to prove it.
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

  /// The empty chat headline, shown before the first message exists.
  static const String emptyChatTitle = 'Güvenli sohbet hazır';

  /// The empty chat body, explaining the one property the user actually cares
  /// about before they type anything.
  static const String emptyChatBody =
      'Mesajlar yalnızca eşleşen cihazlar arasında gönderilir.';

  /// The `aria-label` of the message log.
  static const String messageLogLabel = 'Mesajlar';

  /// The read receipt appended to an outgoing message's meta line.
  static const String readReceipt = 'Okundu';

  /// Refused when the composed body is blank. Caught before anything is queued,
  /// so an empty message never becomes a pending row.
  static const String emptyMessage = 'Boş mesaj gönderilemez.';

  /// The generic send failure, shown when the channel refused a message for a
  /// reason that has no more specific line.
  static const String sendFailed = 'Mesaj gönderilemedi.';

  /// Refused when there is no open channel to send on at all.
  static const String peerOffline = 'Karşı cihaz çevrimdışı.';

  /// The local history write failed. Distinct from [sendFailed]: the message may
  /// have reached the peer, and telling the user otherwise would be a lie.
  static const String messageNotStored = 'Mesaj yerelde saklanamadı.';

  /// The local history could not be read back.
  static const String historyUnavailable = 'Yerel geçmiş açılamadı.';

  /// Refusal of a send because the in-flight queue is at its bound.
  ///
  /// There is a queue because a message composed while the channel was down must
  /// not be thrown away. At the bound it must say so rather than dropping the
  /// oldest one, because dropping the oldest is the same silent loss with extra
  /// steps.
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

  /// The channel closed while messages were in flight. Every pending send is
  /// told, so a queued message cannot wait forever for a channel that is gone.
  static const String channelClosed = 'Bağlantı kapatıldı.';

  /// The direct connection is not established yet. Kept distinct from
  /// [channelClosed]: one means "not yet", the other means "no longer".
  static const String channelNotReady = 'Doğrudan bağlantı henüz hazır değil.';

  /// The channel is up but not taking frames, i.e. back-pressure rather than a
  /// dead connection. This must not be reported as a timeout: a timeout is a
  /// network fault, and telling the user their network failed when the peer is
  /// merely busy is a diagnosis the user cannot act on.
  static const String channelBusy = 'Bağlantı şu anda meşgul.';

  // ---------------------------------------------------------------------
  // Chat: day separators and time
  // ---------------------------------------------------------------------

  /// The day boundary label for today.
  ///
  /// A day separator exists because a two-week conversation and a two-minute one
  /// otherwise render identically, and "when did she say that?" then has no
  /// answer on screen.
  static const String today = 'Bugün';

  /// See [today].
  static const String yesterday = 'Dün';

  // ---------------------------------------------------------------------
  // Transfers: the transfer list
  // ---------------------------------------------------------------------

  /// The `aria-label` of the transfer list.
  static const String transferListLabel = 'Dosya aktarımları';

  /// The transfer row's completed state.
  static const String completed = 'Tamamlandı';

  /// The transfer row's failed state.
  static const String failed = 'Başarısız';

  /// The transfer row's cancelled state.
  ///
  /// Its own state, not a flavour of [failed]: rendering a cancellation as a
  /// failure makes "you stopped this" and "this broke" indistinguishable in the
  /// only place the user can see it, and the two need different reactions.
  static const String cancelled = 'İptal edildi';

  /// The state of a transfer the peer announced and nobody has answered yet.
  static const String awaitingDecision = 'Karar bekleniyor';

  /// The notice when the peer declines an announced file.
  static const String offerDeclined = 'Dosya teklifi reddedildi.';

  /// The notice when the peer cancels a transfer in flight. The receiver has to
  /// be told: a row that simply vanishes leaves the user wondering whether the
  /// file is still coming.
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

  /// The size guard on a composed message.
  ///
  /// The "32 KB" is not written here: it is read out of
  /// [PeerProtocol.maxMessageBytes] through [formatBytes], so the message cannot
  /// claim a cap the parser does not enforce.
  static String messageTooLarge() =>
      'Mesaj en fazla ${formatBytes(PeerProtocol.maxMessageBytes)} olabilir.';

  /// The refusal for an announced file whose size is out of range.
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

  /// The transfer row headline, naming the direction and the file.
  static String transferHeading(TransferDirection direction, String name) =>
      '${direction == TransferDirection.send ? 'Gönderiliyor' : 'Alınıyor'}: $name';

  /// The `aria-label` of the row's close button.
  static String dismissTransferLabel(String name) => '$name satırını kapat';

  /// The `aria-label` of the progress bar.
  static String transferProgressLabel(String name) =>
      '$name aktarım ilerlemesi';

  /// The completion notice, including where the file landed.
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

  /// The `HH:mm` meta line of one message.
  static String messageTime(DateTime value) =>
      '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';

  /// The `transferred / total` detail line.
  ///
  /// The decimal separator is `,` and not `.`, matching `tr-TR` and every other
  /// string in this file. That is the whole defect this function exists to
  /// prevent: the same number read two ways in the same row, where "1.5 MB" and
  /// "1,5 MB" are two different files to a Turkish reader.
  ///
  /// The unit ladder (`B`, `KB`, `MB`, `GB`) and the rounding are deliberately
  /// plain and identical at both ends, so `32768` is "32 KB" and
  /// [PeerProtocol.maxFileBytes] is "512 MB".
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
