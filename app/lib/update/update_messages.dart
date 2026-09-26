/// Every Turkish string the update layer can put in front of a user.
///
/// One enum, one text per member, no interpolation anywhere. A message that
/// needed a value in it would have to be built at the call site, and a built
/// string is a string nobody can audit by reading this file - so the values a
/// user might need (a version, a byte count) travel on the typed report and the
/// failure as data instead, and the text here stays a constant.
///
/// The enum rather than a class of constants is what makes the catalogue
/// auditable: `UpdateMessage.values` is every entry, in one place, and
/// `test/update/update_messages_test.dart` walks it, so a message added without
/// a Turkish text cannot compile its way past the test.
library;

/// One user-facing line, or nothing at all.
enum UpdateMessage {
  // -- preflight ------------------------------------------------------------
  /// The configured key is pre-hashed and readable. The only good news the
  /// preflight can deliver, and the answer to "is updating even wired up".
  keyAccepted('Güncelleme denetimi tamam; yayın anahtarı geçerli.'),

  /// The defect this layer exists to make visible: the key in
  /// `src-tauri/tauri.conf.json:41` decodes to minisign's retired `Ed`
  /// algorithm, so a strict verifier refuses every signature that key can ever
  /// produce. The old updater reported that as "the download may be
  /// tampered with", which sends a user hunting for an attacker who does not
  /// exist, and it did so silently for every release. This line says what is
  /// actually wrong and what to do about it.
  legacyKey(
    'Yayın anahtarı eski (legacy) biçimde. Bu anahtar prehashed biçimde '
    'yeniden üretilmeden hiçbir güncelleme imzası doğrulanamaz. Anahtarı '
    'değiştirdikten sonra güncellemeyi yeniden deneyin.',
  ),

  /// The configured key is not base64, or is a minisign block the reader cannot
  /// make sense of. Never treated as "probably fine".
  keyUnreadable(
    'Yayın anahtarı okunamadı. Güncelleme güvenlik nedeniyle durduruldu.',
  ),

  /// The app's own version could not be read, so there is nothing to compare
  /// an offered release against. Strictly *stricter* than the Rust core, which
  /// answers "not newer" and would let a broken build string pass for an
  /// up-to-date one. See `UpdateClient.check`.
  currentVersionUnreadable(
    'Uygulama sürümü okunamadı; güncelleme karşılaştırılamıyor.',
  ),

  /// The configured feed address is not an absolute http(s) URL.
  feedUrlUnusable(
    'Güncelleme adresi geçersiz. Güncelleme güvenlik nedeniyle durduruldu.',
  ),

  /// The verification bridge is not wired yet. Fails closed on purpose: an
  /// unverifiable update is not an update, and "the signature check is not
  /// implemented" must never read as "the signature is fine".
  verificationUnavailable(
    'Güncelleme doğrulaması yapılamıyor. Dosya kurulmadı.',
  ),

  // -- checking the feed ----------------------------------------------------

  /// Nothing newer. Not an error, and not silence either: a user who pressed
  /// "check for updates" gets an answer.
  alreadyUpToDate('Uygulama güncel; yeni bir sürüm bulunamadı.'),

  /// The client asked too recently to ask again. The endpoint this release
  /// shipped with answered 404 for its whole life, and a startup that re-asks
  /// on every launch would keep asking it.
  checkDeferred(
    'Güncelleme denetimi çok yakın zamanda yapıldı; şimdilik tekrar '
    'denenmiyor.',
  ),

  /// A newer release was advertised. Nothing has been verified yet beyond the
  /// manifest itself, and the wording says so.
  offered('Yeni bir sürüm bulundu. İndirme ve doğrulama sırada.'),

  /// The feed could not be reached at all. TS: the 404 that `raw.githubusercontent`
  /// gave for `ancapenguin/mkvi-updates` - the reason updating has never worked.
  feedUnreachable(
    'Güncelleme bildirimine ulaşılamadı. Bağlantınızı denetleyin.',
  ),

  /// The feed answered with something that is not a feed.
  feedUnreadable(
    'Güncelleme bildirimi okunamadı; sunucu beklenmeyen bir içerik döndürdü.',
  ),

  /// The feed is larger than a manifest has any right to be, which is what a
  /// captive portal or an error page with a body looks like.
  feedTooLarge('Güncelleme bildirimi beklenenden büyük.'),

  /// The manifest does not match the pinned copy. The feed is advisory, so this
  /// is defence in depth rather than the guarantee - but a rewritten feed is
  /// worth naming before anything is downloaded.
  feedPinMismatch(
    'Güncelleme bildirimi sabitlenmiş sürümüyle aynı değil; bildirim '
    'değiştirilmiş olabilir.',
  ),

  /// The feed advertises a release with no `windows-x86_64` entry. Mirrors
  /// `UpdateError::UnsupportedPlatform`.
  noArtifactForPlatform('Bu cihaz için yayınlanmış güncelleme dosyası yok.'),

  // -- downloading, verifying, installing -----------------------------------

  /// The installer was handed the file. Not "updated": Windows still has to run
  /// it, and the process may be refused.
  installed('Güncelleme kurulumu başlatıldı.'),

  /// Somebody - the user, or a second call to `abort` - stopped the transfer.
  /// Whatever was on disk went with it.
  aborted('Güncelleme iptal edildi.'),

  /// The transfer broke. The staging file is removed, so nothing partial is
  /// left for an installer to pick up.
  downloadFailed(
    'Güncelleme dosyası indirilemedi. Bağlantınızı denetleyip yeniden deneyin.',
  ),

  /// The download directory could not be written: no space, no permission, or an
  /// antivirus that has the folder. Its own case because the fix is a different
  /// one - retrying the same bytes will fail the same way.
  storageUnavailable(
    'Güncelleme dosyası kaydedilemedi; indirme klasörüne yazılamıyor.',
  ),

  /// A zero byte "artefact". Not reported as a bad signature, because nothing
  /// was tampered with - nothing arrived.
  artifactEmpty('Güncelleme dosyası boş geldi.'),

  /// The stream went past the cap. The cap is enforced by the client as it
  /// counts, not delegated to the transport, so a transport that ignores it
  /// still cannot fill the disk.
  artifactTooLarge('Güncelleme dosyası beklenenden büyük; indirme durduruldu.'),

  /// `Content-Length` and the number of bytes that arrived disagree. A truncated
  /// download is a failed download, not a small one.
  artifactSizeMismatch(
    'İndirilen güncelleme dosyası beklenen boyutta değil; dosya reddedildi.',
  ),

  /// The bytes do not match the release signature. This is the only failure
  /// that genuinely means "the file may have been modified", and it is reached
  /// only after a key the preflight already cleared, so it is a real signal.
  signatureRejected(
    'Güncelleme dosyasının imzası doğrulanamadı; indirilen dosya '
    'değiştirilmiş olabilir.',
  ),

  /// The signature field is not a readable minisign block.
  signatureUnreadable('Güncelleme imzası okunamadı; dosya reddedildi.'),

  /// Verified, committed, and the installer refused to start. Distinct from
  /// [signatureRejected] on purpose: the file is good, the platform said no.
  installFailed(
    'Güncelleme kurulumu başlatılamadı. Dosya indirildi ama kurulmadı.',
  );

  const UpdateMessage(this.text);

  /// The exact line a notice should carry. Turkish, and never empty - the test
  /// walks [values] and holds both of those.
  final String text;

  @override
  String toString() => text;
}
