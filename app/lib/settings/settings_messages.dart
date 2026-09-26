/// Why a stored setting could not be used, in Turkish, in one place.
///
/// Every sentence a user can read about a settings problem is built here, so
/// the whole Turkish surface of the settings layer can be audited in one file
/// and so a correction is never reported in an English fragment. The option
/// LABELS the settings screen shows live in `settings_catalog.dart`.
///
/// The rule these sentences exist to enforce: a persisted setting that no
/// longer validates is REPORTED, never silently replaced. The value may still
/// be corrected - a theme that no longer exists cannot be painted - but the
/// user is told what was found, what it was applied instead, and why. Losing a
/// choice in silence is the defect; losing it loudly is a migration.
library;

/// The reasons a stored value could not be used as-is.
///
/// Each one carries enough context in [SettingsIssue] to build a sentence
/// without a lookup table: what was found, what was applied, and a short
/// technical fragment for a measurement.
enum SettingsProblem {
  /// The document is not a settings object at all.
  malformedDocument,

  /// The document was written by a newer build.
  futureVersion,

  /// A known key held a value of the wrong shape.
  wrongType,

  /// The stored theme id is not one of `tokens.json` `themes`.
  unknownTheme,

  /// The stored accent id is not one of `tokens.json` `accents`.
  unknownAccent,

  /// A custom accent was stored as something that is not `#RRGGBB`.
  badAccentColour,

  /// The stored font scale was not a number.
  fontScaleNotANumber,

  /// The stored font scale was outside the slider range.
  fontScaleOutOfRange,

  /// The stored font scale was not a multiple of the slider step.
  fontScaleNotOnStep,

  /// The stored density id is not one of `space.densities`.
  unknownDensity,

  /// The stored radius id is not one of `radius.presets`.
  unknownRadius,

  /// A measured pair fell below the minimum `contrast` declares for it.
  ///
  /// For a shipped theme and accent this is impossible - `design/test/
  /// contrast_test.dart` gates all 816 measured pairs - so it can only fire for
  /// a custom accent or for a future token change, and it is reported rather
  /// than shipped.
  contrastRequirementFailed,

  /// The signaling endpoint was stored empty.
  endpointEmpty,

  /// The signaling endpoint was stored without a scheme.
  endpointNotAbsolute,

  /// The signaling endpoint had no host.
  endpointMissingHost,

  /// The signaling endpoint used a scheme other than http/https.
  endpointUnsupportedScheme,

  /// A stored self name was not already in its sanitised form.
  ///
  /// The sanitiser is the wire's own, so a name is corrected rather than
  /// refused - but the correction is still reported, because "the name you
  /// typed is not the name that was saved" must never be a surprise.
  selfNameSanitised,
}

/// The Turkish sentence for [problem].
///
/// [key] is the stored key or field name, [received] what the store held, and
/// [applied] what the app used instead. [detail] is a short technical fragment
/// for a measurement, e.g. `accent / bg = 1.24:1, en az 3 gerekiyor`.
String settingsProblemTr(
  SettingsProblem problem, {
  required String key,
  String? received,
  String? applied,
  String? detail,
}) {
  return switch (problem) {
    SettingsProblem.malformedDocument =>
      'Ayar dosyası okunamadı${_received(received)}; varsayılanlar kullanıldı.',
    SettingsProblem.futureVersion =>
      'Ayar dosyası daha yeni bir sürümde yazılmış${_received(received)}; '
          'bilinen alanlar okundu, bilinmeyenler yok sayıldı.',
    SettingsProblem.wrongType =>
      '"$key" okunamadı${_received(received)}; varsayılan değer uygulandı.',
    SettingsProblem.unknownTheme =>
      'Kayıtlı tema tanınmıyor${_received(received)}; "Sistem" uygulandı.',
    SettingsProblem.unknownAccent =>
      'Kayıtlı vurgu rengi tanınmıyor${_received(received)}; varsayılan vurgu uygulandı.',
    SettingsProblem.badAccentColour =>
      'Vurgu rengi okunamadı${_received(received)}; '
          'renk #RRGGBB ya da #RRGGBBAA biçiminde olmalı, varsayılan vurgu uygulandı.',
    SettingsProblem.fontScaleNotANumber =>
      'Yazı tipi ölçeği bir sayı olmalı${_received(received)}; 1 uygulandı.',
    SettingsProblem.fontScaleOutOfRange =>
      'Yazı tipi ölçeği${_received(received)} reddedildi; '
          '${_applied(applied)} uygulandı (en az 0.9, en çok 1.25).',
    SettingsProblem.fontScaleNotOnStep =>
      'Yazı tipi ölçeği${_received(received)} '
          '0.05 adımlarıyla uyuşmuyor; ${_applied(applied)} uygulandı.',
    SettingsProblem.unknownDensity =>
      'Yoğunluk tanınmıyor${_received(received)}; "Rahat" uygulandı.',
    SettingsProblem.unknownRadius =>
      'Köşe yuvarlaklığı tanınmıyor${_received(received)}; "Yumuşak" uygulandı.',
    SettingsProblem.contrastRequirementFailed =>
      'Renk ölçümü başarısız${detail == null ? '' : ': $detail'}.',
    SettingsProblem.endpointEmpty =>
      'Sunucu adresi boş olamaz; kendi Worker adresinizi girin.',
    SettingsProblem.endpointNotAbsolute =>
      'Sunucu adresi tam bir adres olmalı; örnek: https://signal.example.workers.dev',
    SettingsProblem.endpointMissingHost => 'Sunucu adresinde alan adı yok.',
    SettingsProblem.endpointUnsupportedScheme =>
      'Sunucu adresi yalnızca http:// veya https:// ile başlayabilir.',
    SettingsProblem.selfNameSanitised =>
      'Adınız kaydedilirken temizlendi; temizlenmiş hâli kullanıldı.',
  };
}

String _received(String? value) =>
    value == null || value.isEmpty ? '' : ' (alınan: $value)';

String _applied(String? value) => value ?? 'varsayılan';
