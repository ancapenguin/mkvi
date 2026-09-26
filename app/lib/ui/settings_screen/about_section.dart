/// The about section: the version, and the update status — or the absence of one.
///
/// ## Why the update client is a callback and not a dependency
///
/// `app/lib/update/` is written and tested, and `UpdateConfig.isUsableFeedUrl`
/// is the only thing in it that decides whether a feed may be read. This screen
/// does not import it, for one reason: a build that ships no update check must
/// be able to say so. If the section took an `UpdateClient`, then
/// "Sürüm 0.2.0" and the whole row below it would be unreachable in a build
/// without a configured feed, and the section would have nothing honest to show
/// — which is the state this screen is in until a host wires one up.
///
/// So the section takes:
///
/// * [appVersion] — a required string, because `pubspec.yaml` is the single
///   source of the version and a second copy in this tree is a value that will
///   drift;
/// * [onCheckUpdate] — null until a host has an update client. While it is null
///   there is **no** button and the status reads
///   [SettingsUiTr.updateStatusUnknown], because "Güncel" would be a claim
///   nobody measured;
/// * [updateStatusTr] — the Turkish sentence the host's own update state
///   produces, so the wording of a check stays with the thing being checked.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'appearance_section.dart' show SettingsCard;
import 'settings_strings.dart';

/// The keys the parts of the about section answer to.
abstract final class AboutKeys {
  /// The `surface` card the rows live in.
  static const Key card = Key('mkvi.settings.about.card');

  /// The version row's value.
  static const Key version = Key('mkvi.settings.about.version');

  /// The update status row's value.
  static const Key updateStatus = Key('mkvi.settings.about.updateStatus');
}

/// The version, and the update status or the reason there is not one.
class AboutSection extends StatelessWidget {
  /// Creates the section.
  const AboutSection({
    super.key,
    required this.appVersion,
    this.onCheckUpdate,
    this.updateStatusTr,
  });

  /// The version this build reports, from `pubspec.yaml`.
  final String appVersion;

  /// Asks the host to check for an update.
  ///
  /// Null in a build with no update client, and then there is no button at all:
  /// a control that cannot do anything is not a control.
  final VoidCallback? onCheckUpdate;

  /// What the host's update state is, in Turkish. Null says the honest thing —
  /// that this build cannot check.
  final String? updateStatusTr;

  /// Whether this build can check for an update at all.
  bool get canCheck => onCheckUpdate != null;

  /// The sentence the status row shows.
  String get statusTr =>
      updateStatusTr ?? SettingsUiTr.updateStatusUnknown.tr;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return SettingsCard(
      key: AboutKeys.card,
      resting: MkviRestingSurface.surface,
      title: SettingsUiTr.aboutSection.tr,
      subtitle: SettingsUiTr.aboutDescription.tr,
      actions: <MkviPanelAction>[
        if (canCheck)
          MkviPanelAction(
            label: SettingsUiTr.checkUpdateLabel.tr,
            onPressed: onCheckUpdate,
          ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KeyedSubtree(
            key: AboutKeys.version,
            child: MkviKeyValueRow(
              label: SettingsUiTr.versionLabel.tr,
              value: appVersion,
            ),
          ),
          SizedBox(height: style.gap('1')),
          KeyedSubtree(
            key: AboutKeys.updateStatus,
            child: MkviKeyValueRow(
              label: SettingsUiTr.updateStatusLabel.tr,
              value: statusTr,
            ),
          ),
        ],
      ),
    );
  }
}
