/// Every string the settings screen shows, in Turkish, in one typed place.
///
/// ## Why the theme and accent names are NOT written here
///
/// `design/tokens.json` carries a Turkish name for every theme and every
/// accent, and it is the only place one may be written down. This catalogue
/// asks [AppearanceTokens] for those four names and four names, and supplies
/// only the words the token file does not have: the `system` theme (which the
/// token file cannot have, because it is not a theme), the two densities, the
/// two radii, the accessibility switches and every field label.
///
/// `app/test/settings/catalog_test.dart` asserts the four theme names and the
/// four accent names this catalogue renders are byte-for-byte the ones in
/// `design/tokens.json`, so "do not retype them" is a test, not a promise.
library;

import 'dart:ui' show Color;

import 'appearance_settings.dart';
import 'contrast.dart';
import 'design_tokens.dart';

/// The Turkish text of the settings screen.
final class SettingsCatalog {
  const SettingsCatalog(this.tokens);

  /// The token file, for the names it owns.
  final AppearanceTokens tokens;

  // --- sections -------------------------------------------------------------

  /// The appearance section.
  String get appearanceSection => 'Görünüm';

  /// The connection section.
  String get connectionSection => 'Bağlantı';

  /// The accessibility section.
  String get accessibilitySection => 'Erişilebilirlik';

  /// The identity section.
  String get profileSection => 'Profil';

  /// The banner that appears when a stored setting had to be corrected.
  String get repairedBannerTitle => 'Bazı ayarlar düzeltildi';

  // --- theme ----------------------------------------------------------------

  /// The label of the theme picker.
  String get themeLabel => 'Tema';

  /// The label of the system theme. Not in the token file: it is a decision
  /// about the platform, not a theme.
  String get systemThemeLabel => 'Sistem';

  /// What the system theme does.
  String get systemThemeDescription =>
      'İşletim sisteminin açık ve koyu ayarını izler.';

  /// The Turkish name of a theme, from the token file.
  String themeOptionLabel(ThemePreference preference) {
    final String? id = preference.themeId;
    if (id == null) return systemThemeLabel;
    return tokens.themeLabel(id);
  }

  /// Every theme a user can pick, in the token file's order, with `system`
  /// first because it is the default.
  List<ThemePreference> get themeOptions => <ThemePreference>[
    ThemePreference.system,
    ...ThemePreference.values.where(
      (ThemePreference value) => value.isExplicit,
    ),
  ];

  // --- accent ---------------------------------------------------------------

  /// The label of the accent picker.
  String get accentLabel => 'Vurgu rengi';

  /// The label of a shipped accent, from the token file.
  String accentOptionLabel(AccentId accent) => tokens.accentLabel(accent.name);

  /// The label of a custom accent, with the colour the user picked.
  String customAccentLabel(Color? colour) {
    if (colour == null) return customAccentName;
    return '$customAccentName (${hexOf(colour)})';
  }

  /// The name of the custom option, without a colour.
  String get customAccentName => 'Özel';

  /// What a custom accent is allowed to do.
  String get customAccentDescription =>
      'İstediğiniz bir rengi seçin. Metin rengi, seçtiğiniz renge göre '
      'otomatik ayarlanır.';

  // --- font scale -----------------------------------------------------------

  /// The label of the type size slider.
  String get fontScaleLabel => 'Yazı tipi boyutu';

  /// The slider's value, as a percentage of the token size.
  String fontScaleValue(double scale) => '%${(scale * 100).round()}';

  /// The slider's smallest value.
  String get fontScaleMinimumLabel =>
      fontScaleValue(AppearanceSettings.minFontScale);

  /// The slider's largest value.
  String get fontScaleMaximumLabel =>
      fontScaleValue(AppearanceSettings.maxFontScale);

  // --- density and radius ---------------------------------------------------

  /// The label of the density picker.
  String get densityLabel => 'Yoğunluk';

  /// The compact density.
  String get densityCompactLabel => 'Sıkışık';

  /// The comfortable density.
  String get densityComfortableLabel => 'Rahat';

  /// The label of the density a preference resolves to.
  String densityOptionLabel(DensityPreference preference) =>
      preference == DensityPreference.compact
      ? densityCompactLabel
      : densityComfortableLabel;

  /// What the density switch changes.
  String get densityDescription =>
      'Boşluklar ve düğme yükseklikleri ölçeklenir; yazı tipi boyutu değişmez.';

  /// The label of the corner picker.
  String get radiusLabel => 'Köşe yuvarlaklığı';

  /// The crisp preset.
  String get radiusCrispLabel => 'Keskin';

  /// The soft preset.
  String get radiusSoftLabel => 'Yumuşak';

  /// The label of the radius a preference resolves to.
  String radiusOptionLabel(RadiusPreference preference) =>
      preference == RadiusPreference.crisp ? radiusCrispLabel : radiusSoftLabel;

  // --- accessibility --------------------------------------------------------

  /// The high contrast switch.
  String get highContrastLabel => 'Yüksek karşıtlık';

  /// What the high contrast switch does, in the token file's own terms.
  String get highContrastDescription =>
      'Metin ve kenarlık renkleri sınır değerlere çekilir, odak halkası '
      'kalınlaşır. Her ölçüm, tasarımın kendi eşiğinden daha yüksektir.';

  /// The reduced motion switch.
  String get reduceMotionLabel => 'Hareketi azalt';

  /// What the reduced motion switch does, in the token file's own terms.
  String get reduceMotionDescription =>
      'Bütün geçiş süreleri anlığa çevrilir ve mürekkep efekti kapatılır.';

  // --- connection -----------------------------------------------------------

  /// The endpoint field.
  String get endpointLabel => 'Sinyal sunucusu';

  /// What goes in the endpoint field.
  String get endpointHint => 'Kendi Cloudflare Worker adresiniz (https://…)';

  /// The empty-state text while nothing is configured.
  String get endpointEmptyState =>
      'Sunucu adresi girilmedi. MKVI kendi sunucusunu içermez; herkes kendi '
      'Worker adresini kullanır.';

  /// The ICE servers field.
  String get iceServersLabel => 'Ek ICE sunucuları';

  /// What goes in the ICE servers field.
  String get iceServersHint => 'İsteğe bağlı, her satıra bir adres';

  /// The save action.
  String get saveLabel => 'Kaydet';

  // --- identity -------------------------------------------------------------

  /// The self name field.
  String get selfNameLabel => 'Adınız';

  /// What goes in the self name field.
  String get selfNameHint => 'Karşı tarafta görünecek adınız';

  // --- actions --------------------------------------------------------------

  /// Back to the shipped defaults for the appearance.
  String get resetAppearanceLabel => 'Görünümü sıfırla';

  /// The confirmation shown after a reset.
  String get appearanceResetDone => 'Görünüm varsayılanlara döndü.';
}
