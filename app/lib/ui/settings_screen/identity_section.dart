/// The identity: the name the other device sees.
///
/// ## Why the field does not enforce the 40-character cap
///
/// `safeDisplayName` — the wire's own function, reached through
/// `sanitisedSelfName` — trims, strips control and bidi characters, collapses
/// whitespace and truncates to `PeerProtocol.maxDisplayNameLength`. This screen
/// deliberately does **not** set `MkviTextField.maxLength`:
///
/// * `MaxLengthEnforcement.enforced` is the default, so a cap here would
///   *refuse* input the layer would have accepted and silently truncated;
/// * the counter would then promise "40/40" for a value the wire still cuts.
///
/// So the field takes what the user types, the layer sanitises it on the way in,
/// and the confirmation line reports that the name was stored. The name that is
/// stored is the one that was shown, which is the property
/// `app/test/settings/settings_controller_test.dart` pins on the state side.
///
/// ## Why the section is "Kimlik" and not "Profil"
///
/// `SettingsCatalog` has a `profileSection` ('Profil') for a profile page. This
/// screen has no profile beyond the name, and a heading that promises a page
/// which does not exist is the same defect as a label for a control that is not
/// there. The wording is in `SettingsUiTr`, not in the catalogue, because the
/// catalogue's is a different section.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'appearance_section.dart' show SettingsCard;
import 'settings_strings.dart';

/// The keys the parts of the identity section answer to.
abstract final class IdentityKeys {
  /// The `surface` card the field lives in.
  static const Key card = Key('mkvi.settings.identity.card');

  /// The field and everything around it, so a test can find it among the
  /// screen's other `MkviFieldKeys.input`s.
  static const Key field = Key('mkvi.settings.identity.field');

  /// The line that says the name was stored.
  static const Key notice = Key('mkvi.settings.identity.notice');
}

/// The self name field, with one save.
class IdentitySection extends StatefulWidget {
  /// Creates the section over [controller].
  const IdentitySection({super.key, required this.controller});

  /// The state this screen shows and changes. Never written to directly.
  final SettingsController controller;

  @override
  State<IdentitySection> createState() => _IdentitySectionState();
}

class _IdentitySectionState extends State<IdentitySection> {
  late final TextEditingController _name;

  /// The Turkish reason the last save was refused, or null.
  ///
  /// Always null today — a name is sanitised rather than refused — and the field
  /// shows it anyway, so the shape of this form does not change when a future
  /// rule starts refusing something.
  String? _error;

  /// Whether the last save was stored, so a save is never silent.
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.controller.settings.selfName);
  }

  @override
  void didUpdateWidget(IdentitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    _name.text = widget.controller.settings.selfName;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.controller.setSelfName(_name.text);
    if (!mounted) return;
    setState(() {
      _error = widget.controller.selfNameErrorTr;
      _saved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final SettingsCatalog catalog = widget.controller.catalog;
    return SettingsCard(
      key: IdentityKeys.card,
      resting: MkviRestingSurface.surface,
      title: SettingsUiTr.identitySection.tr,
      subtitle: SettingsUiTr.identityDescription.tr,
      actions: <MkviPanelAction>[
        MkviPanelAction(
          label: SettingsUiTr.identitySaveLabel.tr,
          filled: true,
          onPressed: _save,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KeyedSubtree(
            key: IdentityKeys.field,
            child: MkviTextField(
              label: catalog.selfNameLabel,
              hintText: catalog.selfNameHint,
              errorText: _error,
              controller: _name,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => _typed(),
              onSubmitted: (_) => _save(),
            ),
          ),
          if (_saved) ...<Widget>[
            SizedBox(height: style.gap('2')),
            Semantics(
              key: IdentityKeys.notice,
              liveRegion: true,
              child: Text(
                SettingsUiTr.selfNameSaved.tr,
                style: style.styleOf('sm').copyWith(
                  color: style.role('textMuted'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A keystroke invalidates the last confirmation.
  void _typed() {
    if (!_saved && _error == null) return;
    setState(() {
      _error = null;
      _saved = false;
    });
  }
}
