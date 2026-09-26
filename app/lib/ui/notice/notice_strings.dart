/// Every user-facing string this layer can produce, in Turkish, in one typed
/// place.
///
/// TS had none of these: the toast rendered whatever `notice` happened to hold
/// (`src/App.tsx:542`, `597`, `615`) and the close button had no accessible name
/// at all. A notice layer with one `String` per decision in six call sites is
/// how "Yeniden bağlanılıyor: ..." ended up on screen forever — see
/// `src/App.tsx:289`, which interpolated a live error into a notice.
///
/// Each value carries its own text, so a new entry without Turkish wording is a
/// compile error rather than a blank button, and [noticeTrCatalogue] is the
/// iterable form the tests check.
library;

/// One string this layer can show, to anyone, in any channel.
enum NoticeTr {
  /// The accessible name of the close control on a notice. Also its tooltip.
  close('Bildirimi kapat'),

  /// The accessibility hint on a notice body that is taller than its cap, i.e.
  /// the one case where the rest of the text is reachable by scrolling.
  bodyScrollHint('Ayrıntıyı okumak için kaydır'),

  /// The accessible name of the severity mark on an informational notice.
  severityInfo('Bilgi'),

  /// The accessible name of the severity mark on a successful notice.
  severitySuccess('Başarılı'),

  /// The accessible name of the severity mark on a warning notice.
  severityWarning('Uyarı'),

  /// The accessible name of the severity mark on an error notice.
  severityError('Hata'),

  /// The status strip's label while nothing is being negotiated.
  statusIdle('Hazır'),

  /// The status strip's label while a connection is being negotiated.
  statusConnecting('Bağlanıyor'),

  /// The status strip's label while the data channel is open.
  statusOnline('Bağlı'),

  /// The status strip's label while the peer cannot be reached.
  statusOffline('Bağlantı yok'),

  /// The status strip's label when the last connection attempt failed outright.
  statusError('Bağlantı hatası'),

  /// The status strip's explanation while nothing is being negotiated.
  statusIdleDetail('Henüz bağlantı kurulmadı.'),

  /// The status strip's explanation while a connection is being negotiated.
  statusConnectingDetail('Eşleştiğin cihazla bağlantı kuruluyor.'),

  /// The status strip's explanation while the data channel is open.
  statusOnlineDetail('Eşleştiğin cihazla güvenli bağlantı kuruldu.'),

  /// The status strip's explanation while the peer cannot be reached.
  statusOfflineDetail('Eşleştiğin cihaza ulaşılamıyor, yeniden deneniyor.'),

  /// The status strip's explanation when the last attempt failed outright.
  statusErrorDetail('Bağlantı kurulamadı. Ayarları kontrol et.');

  const NoticeTr(this.tr);

  /// The Turkish text, never empty.
  final String tr;
}

/// Every entry as a map, for tests, for a debug overlay and for a future
/// translation pass.
Map<NoticeTr, String> get noticeTrCatalogue => <NoticeTr, String>{
  for (final NoticeTr entry in NoticeTr.values) entry: entry.tr,
};
