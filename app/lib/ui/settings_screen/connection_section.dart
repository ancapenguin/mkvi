/// The connection: the signaling endpoint, the optional ICE servers, and the
/// save that either stores both or stores nothing.
///
/// ## Why the refusal is shown, not swallowed
///
/// MKVI embeds no server, so the endpoint is the one setting a user must type
/// before anything else works, and `ConnectionSettings.validateEndpoint` refuses
/// four different shapes of input — each with its own Turkish sentence in
/// `settings/settings_messages.dart`. This section shows the sentence the layer
/// produced, verbatim, under the field, and shows nothing when the value was
/// accepted:
///
/// ```dart
/// final bool ok = await controller.setEndpoint(raw, iceServersText: ice);
/// setState(() => _error = ok ? null : controller.endpointErrorTr);
/// ```
///
/// There is no second validation in this file and no wording of its own. A form
/// that invented its own reason would teach the user that the app's reasons are
/// approximate, and the whole point of `endpointErrorTr` is that they are not.
///
/// A refused value changes nothing: `SettingsController.setEndpoint` returns
/// false before it writes, and the section's confirmation line is the only thing
/// that appears when it returns true.
///
/// ## A note on `http://`
///
/// `validateEndpoint` accepts `http` and `https` and refuses everything else,
/// and its own message says so (`yalnızca http:// veya https:// ile başlayabilir`).
/// This screen does not add a stricter rule of its own: a form that refused
/// something the state layer accepts would be two answers to one question, and
/// the caller would not know which one is the contract.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'appearance_section.dart' show SettingsCard;
import 'settings_strings.dart';

/// The keys the parts of the connection section answer to.
abstract final class ConnectionKeys {
  /// The `surface` card the form lives in.
  static const Key card = Key('mkvi.settings.connection.card');

  /// The endpoint field and everything around it, so a test can tell the two
  /// fields apart: both carry `MkviFieldKeys.input`.
  static const Key endpointField = Key('mkvi.settings.connection.endpoint');

  /// The ICE servers field.
  static const Key iceField = Key('mkvi.settings.connection.ice');

  /// The line that says the values were stored.
  static const Key notice = Key('mkvi.settings.connection.notice');
}

/// The signaling endpoint and the ICE servers, with one save for both.
class ConnectionSection extends StatefulWidget {
  /// Creates the section over [controller].
  const ConnectionSection({super.key, required this.controller});

  /// The state this screen shows and changes. Never written to directly.
  final SettingsController controller;

  @override
  State<ConnectionSection> createState() => _ConnectionSectionState();
}

class _ConnectionSectionState extends State<ConnectionSection> {
  late final TextEditingController _endpoint;
  late final TextEditingController _ice;

  /// The Turkish reason the last save was refused, or null.
  ///
  /// Local rather than read straight off the controller, so that typing clears
  /// it: the sentence is about the value that was refused, and once the value
  /// has changed the verdict is stale. [widget.controller]'s own
  /// `endpointErrorTr` is what is copied in, never reworded.
  String? _error;

  /// Whether the last save was stored. So a save is never silent.
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _endpoint = TextEditingController(
      text: widget.controller.settings.connection.endpointText,
    );
    _ice = TextEditingController(
      text: widget.controller.settings.connection.iceServersText,
    );
  }

  @override
  void didUpdateWidget(ConnectionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    _endpoint.text = widget.controller.settings.connection.endpointText;
    _ice.text = widget.controller.settings.connection.iceServersText;
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _ice.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bool stored = await widget.controller.setEndpoint(
      _endpoint.text,
      iceServersText: _ice.text,
    );
    if (!mounted) return;
    setState(() {
      _error = stored ? null : widget.controller.endpointErrorTr;
      _saved = stored;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final SettingsCatalog catalog = widget.controller.catalog;
    final ConnectionSettings connection = widget.controller.settings.connection;
    return SettingsCard(
      key: ConnectionKeys.card,
      resting: MkviRestingSurface.surface,
      title: catalog.connectionSection,
      subtitle: SettingsUiTr.connectionDescription.tr,
      actions: <MkviPanelAction>[
        MkviPanelAction(
          label: catalog.saveLabel,
          filled: true,
          onPressed: _save,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KeyedSubtree(
            key: ConnectionKeys.endpointField,
            child: MkviTextField(
              label: catalog.endpointLabel,
              hintText: catalog.endpointHint,
              // Absent once something is configured: the sentence explains an
              // empty state, and a configured field does not have one.
              helperText: connection.hasEndpoint ? null : catalog.endpointEmptyState,
              errorText: _error,
              controller: _endpoint,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _typed(),
              onSubmitted: (_) => _save(),
            ),
          ),
          SizedBox(height: style.gap('3')),
          KeyedSubtree(
            key: ConnectionKeys.iceField,
            child: MkviMultilineField(
              label: catalog.iceServersLabel,
              hintText: catalog.iceServersHint,
              controller: _ice,
              onChanged: (_) => _typed(),
            ),
          ),
          if (_saved) ...<Widget>[
            SizedBox(height: style.gap('2')),
            Semantics(
              key: ConnectionKeys.notice,
              liveRegion: true,
              child: Text(
                SettingsUiTr.connectionSaved.tr,
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

  /// A keystroke invalidates the last verdict and the last confirmation.
  void _typed() {
    if (_error == null && !_saved) return;
    setState(() {
      _error = null;
      _saved = false;
    });
  }
}
