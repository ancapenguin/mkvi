/// The settings screen, in one import.
///
/// Named `settings_screen_ui.dart` rather than `settings_screen.dart` because
/// the latter is [SettingsScreen] itself, and a barrel that shares a name with
/// the file it re-exports is the kind of collision the next agent resolves by
/// deleting the wrong one.
///
/// ```dart
/// import 'package:mkvi/ui/settings_screen/settings_screen_ui.dart';
/// ```
///
/// ## The files, and which question each one answers
///
/// | file | what it is |
/// |---|---|
/// | `settings_screen.dart` | [SettingsScreen]: the page, its order and its banner |
/// | `appearance_section.dart` | theme, accent, corners, accessibility, the live preview, and the two shared building blocks ([SettingsCard], [SettingsChoiceGroup]) |
/// | `type_scale_section.dart` | the type slider and the sample at both ends of the range |
/// | `density_section.dart` | the density picker and the sample rows |
/// | `connection_section.dart` | the endpoint and the ICE servers, with the refusal shown |
/// | `identity_section.dart` | the name the peer sees |
/// | `about_section.dart` | the version and the update status |
/// | `settings_strings.dart` | the Turkish this screen owns ([SettingsUiTr]) |
///
/// ## The rules this directory keeps
///
/// * **No value of its own.** Every change is a [SettingsController] call; every
///   control, colour, spacing step and label belongs to `app/lib/ui/widgets/` or
///   to `SettingsCatalog`. The two building blocks live here because the screen
///   is the first thing that needed them: a card on a `surface` (the panel
///   vocabulary has no such variant) and a choice list whose selection is the
///   controller's rather than the widget's.
/// * **No pixel, colour, `dart:math` or hard-coded `Duration`.** Every one of
///   them is `style.gap('4')`, `style.role('surface')`, `style.shape('md')`,
///   `style.control('md').height` or `style.duration('normal')`.
/// * **No English.** Comments are English; every string a user can read is
///   Turkish, and it comes from [SettingsCatalog] or [SettingsUiTr].
library;

export 'about_section.dart';
export 'appearance_section.dart';
export 'connection_section.dart';
export 'density_section.dart';
export 'identity_section.dart';
export 'settings_screen.dart';
export 'settings_strings.dart';
export 'type_scale_section.dart';
