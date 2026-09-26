/// Every string the settings screen needs that `SettingsCatalog` does not have.
///
/// ## Why this file exists at all
///
/// `settings/settings_catalog.dart` owns the **labels of the settings**: the
/// theme names (from `design/tokens.json`), the accent names (from the same
/// file), the two densities, the two radii, the type scale's own percent form,
/// every field label and every field hint. That catalogue is not this screen's
/// to extend and this screen does not restate any of it — `themeOptionLabel`,
/// `accentOptionLabel`, `fontScaleValue`, `densityOptionLabel`,
/// `radiusOptionLabel`, `endpointHint` and `customAccentLabel` are read, never
/// retyped, so a renamed theme fails one test instead of drifting in two files.
///
/// What is left is the wording a *screen* has and a catalogue of *values* does
/// not: the name of a section the catalogue has no entry for, the sentence under
/// a section heading, the sample copy the live preview paints with, and the
/// confirmation shown after something was saved. Those live here, in one enum, so
/// that a new screen string without Turkish wording is a compile error rather
/// than an empty label — the same rule `ui/notice/notice_strings.dart` follows.
///
/// ## What is deliberately NOT here
///
/// * No theme, accent, density or radius name. `design/tokens.json` is the only
///   place one may be written down, and `SettingsCatalog` is the only way to
///   read it.
/// * No error sentence. `settings/settings_messages.dart` builds the reason a
///   value was refused, in Turkish, from the layer that refused it; a field that
///   invents its own reason teaches the user that the app's reasons are
///   approximate. The screen shows `SettingsController.endpointErrorTr` and
///   `selfNameErrorTr` verbatim.
/// * No number that a design token owns. The type scale's range and step come
///   from `AppearanceSettings`, the gaps from `AppearanceStyle`.
library;

/// One string this screen can show, in Turkish.
enum SettingsUiTr {
  /// The identity section's heading.
  ///
  /// The catalogue has `profileSection` ('Profil') for a profile page; this
  /// screen has no profile beyond the name the peer sees, so it says what the
  /// section is.
  identitySection('Kimlik'),

  /// One line under the identity heading.
  identityDescription('Karşı tarafta görünecek adınız.'),

  /// The action that stores the self name.
  identitySaveLabel('Adı kaydet'),

  /// Shown after the self name was stored, so a save is never silent.
  selfNameSaved('Adınız kaydedildi.'),

  /// The about section's heading.
  aboutSection('Hakkında'),

  /// One line under the about heading.
  aboutDescription('MKVI sürümü ve güncelleme durumu.'),

  /// The version row's label. The value is the caller's, not a literal here.
  versionLabel('Sürüm'),

  /// The update status row's label.
  updateStatusLabel('Güncelleme durumu'),

  /// The update status while no `UpdateClient` is wired to this screen.
  ///
  /// A build with no update check has to say so, because "Güncel" would be a
  /// claim nobody measured.
  updateStatusUnknown('Bu derlemede güncelleme denetimi bağlı değil.'),

  /// The action that asks the host to check for an update.
  checkUpdateLabel('Güncelleme denetle'),

  /// The appearance section's heading comes from the catalogue; this is the one
  /// line under it, and it is the promise the section keeps.
  appearanceDescription(
    'Renkler, yazı tipi boyutu, yoğunluk ve erişilebilirlik. Her değişiklik '
    'anında uygulanır.',
  ),

  /// What to do about a stored setting that had to be corrected.
  ///
  /// The banner is not an apology: the value was changed and the user has to be
  /// able to change it back, so this says so in one sentence.
  repairedBannerRecovery('Kaybolan bir seçimi yeniden yapabilirsiniz.'),

  /// The heading of the live preview block.
  previewLabel('Önizleme'),

  /// One line under the preview heading.
  previewDescription('Seçtiğiniz tema ve vurgu rengi bu blokta görünür.'),

  /// The accent pill inside the preview: an accent fill, seen.
  previewAccentLabel('Vurgu'),

  /// The first sample row's name.
  previewSampleName('Ayşe Gül'),

  /// The first sample row's secondary line.
  previewSampleDetail('Son mesaj: dosya gönderildi.'),

  /// The type scale block's heading.
  typeScaleSection('Yazı ölçeği'),

  /// The heading of the sample block under the type scale slider.
  typeScaleSampleLabel('Örnek metin'),

  /// The small end of the sample: the step a list row paints with.
  typeScaleSampleSmall('Kısa bir mesaj.'),

  /// The large end of the sample: the step a heading paints with.
  typeScaleSampleLarge('Sohbet arkadaşın, nasılsın?'),

  /// The heading of the sample rows under the density picker.
  densitySampleLabel('Örnek satırlar'),

  /// A sample row's name.
  densitySampleName('Ayşe Gül'),

  /// A sample row's secondary line.
  densitySampleDetail('Bugün 14:32 · Görüldü'),

  /// One line under the connection heading.
  connectionDescription(
    'Sinyalleşme adresini ve isteğe bağlı ICE sunucularını girin.',
  ),

  /// Shown after an endpoint was accepted and stored, so a save is never silent.
  connectionSaved('Sunucu adresi kaydedildi.');

  const SettingsUiTr(this.tr);

  /// The Turkish text, never empty.
  final String tr;
}

/// Every entry as a map, for tests, a debug overlay and a future translation pass.
Map<SettingsUiTr, String> get settingsUiTrCatalogue => <SettingsUiTr, String>{
  for (final SettingsUiTr entry in SettingsUiTr.values) entry: entry.tr,
};
