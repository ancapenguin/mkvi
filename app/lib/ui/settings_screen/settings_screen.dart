/// The settings screen: the one place a preference can be changed, and the one
/// place its effect can be seen.
///
/// ## What the screen is
///
/// Four sections and a banner, in the order a user meets them:
///
/// | section | file | what it changes |
/// |---|---|---|
/// | Görünüm | `appearance_section.dart` | theme, accent, corners, high contrast, reduced motion, and a live preview |
/// | Yazı ölçeği | `type_scale_section.dart` | the type multiplier, with a sample at both ends |
/// | Yoğunluk | `density_section.dart` | the density, with sample rows |
/// | Bağlantı | `connection_section.dart` | the signaling endpoint and the ICE servers |
/// | Kimlik | `identity_section.dart` | the name the peer sees |
/// | Hakkında | `about_section.dart` | the version and the update status |
///
/// It is a `Scaffold` and a scroll view and nothing else: every control, every
/// colour, every spacing step and every Turkish label belongs to
/// `app/lib/ui/widgets/` or to `SettingsCatalog`. The one thing this file owns is
/// the **shape** of the page.
///
/// ## What it does not own
///
/// * **A value.** Every change is a `SettingsController` call, and every label
///   is read from `SettingsCatalog` or from `SettingsUiTr`. A test that finds a
///   theme name written in this tree is looking at a bug.
/// * **A reading of the store.** `SettingsController.load()` is the host's call
///   at startup, not this screen's — a screen that loaded on every build would
///   re-read the store behind the shell's back and publish a second report.
/// * **A width.** There is no `maxWidth` here, because a pixel literal is banned
///   in this tree and no `space` step expresses a reading measure. The page
///   padding is steps and the panels stretch; `settings_screen_test.dart` lays
///   the screen out in a 320 dp column, which is where an overflow becomes
///   possible at all.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'about_section.dart';
import 'appearance_section.dart';
import 'connection_section.dart';
import 'density_section.dart';
import 'identity_section.dart';
import 'settings_strings.dart';
import 'type_scale_section.dart';

/// The keys the parts of the screen answer to.
///
/// Named `SettingsScreenKeys` and not `SettingsKeys`, because
/// `package:mkvi/settings/settings.dart` already exports a `SettingsKeys` — the
/// four store keys — and a barrel that re-exports both would make every caller
/// that needs the store keys write a prefix to disambiguate.
abstract final class SettingsScreenKeys {
  /// The scrollable page.
  static const Key page = Key('mkvi.settings.page');

  /// The banner shown when a stored setting had to be corrected. Absent on a
  /// clean read, because absence is not corruption.
  static const Key repairedBanner = Key('mkvi.settings.repairedBanner');
}

/// The settings screen.
class SettingsScreen extends StatelessWidget {
  /// Creates the screen over [controller].
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.appVersion,
    this.onCheckUpdate,
    this.updateStatusTr,
  });

  /// The state this screen shows and changes. Never written to directly.
  final SettingsController controller;

  /// The version this build reports, from `pubspec.yaml`.
  final String appVersion;

  /// Asks the host to check for an update. Null in a build with no update
  /// client, and then the about section says so instead of showing a button
  /// that cannot do anything.
  final VoidCallback? onCheckUpdate;

  /// What the host's update state is, in Turkish. Null says the honest thing.
  final String? updateStatusTr;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final SettingsCatalog catalog = controller.catalog;
    return Scaffold(
      backgroundColor: style.role('bg'),
      body: SafeArea(
        child: SingleChildScrollView(
          key: SettingsScreenKeys.page,
          padding: EdgeInsets.all(style.gap('6')),
          child: ListenableBuilder(
            listenable: controller,
            builder: (BuildContext context, Widget? _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (controller.report.hasIssues) ...<Widget>[
                    MkviErrorState(
                      key: SettingsScreenKeys.repairedBanner,
                      title: catalog.repairedBannerTitle,
                      reason: controller.report.summaryTr,
                      message: SettingsUiTr.repairedBannerRecovery.tr,
                      icon: Icons.build_circle_outlined,
                    ),
                    SizedBox(height: style.gap('6')),
                  ],
                  AppearanceSection(controller: controller),
                  SizedBox(height: style.gap('6')),
                  TypeScaleSection(controller: controller),
                  SizedBox(height: style.gap('6')),
                  DensitySection(controller: controller),
                  SizedBox(height: style.gap('6')),
                  ConnectionSection(controller: controller),
                  SizedBox(height: style.gap('6')),
                  IdentitySection(controller: controller),
                  SizedBox(height: style.gap('6')),
                  AboutSection(
                    appVersion: appVersion,
                    onCheckUpdate: onCheckUpdate,
                    updateStatusTr: updateStatusTr,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
