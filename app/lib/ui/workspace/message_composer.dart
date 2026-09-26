/// The composer: a field that is never disabled because the peer is away, and a
/// send button that is disabled only when there is nothing to send.
///
/// ## The defect this is the opposite of
///
/// `src/App.tsx` disabled the field on the peer's state:
///
/// ```tsx
/// <input … disabled={!peerOnline} placeholder={peerOnline ? … : "Mesaj göndermek için bağlantı bekleniyor"} />
/// ```
///
/// and `sendMessage` threw when the transport was gone:
///
/// ```ts
/// const id = peer.current?.sendChat(body);
/// if (!id) throw new Error("Karşı cihaz çevrimdışı.");
/// ```
///
/// So the two windows in which a user most wants to write — during a reconnect,
/// and in the instant between a field becoming enabled and the keypress landing
/// — were the two windows in which writing was impossible, and one throw lost
/// the text. `ChatController.send` inverts both: it writes the line down, holds
/// it in a queue and returns. So this widget's only disabled state is
/// [String.trim] being empty, and [MessageComposer.channelOpen] changes one
/// *sentence* under the field rather than the field's ability to be typed in.
///
/// ## What the send button returns
///
/// [MessageComposer.onSend] answers whether the line was **written down**.
/// The field is cleared only on a `true`, so a refusal that never reached the
/// queue (blank, over the byte cap, the queue at its bound) leaves the text
/// where the user typed it — the alternative is a send that loses a paragraph
/// the user has to find and retype.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'workspace_strings.dart';

/// The keys the composer's parts answer to.
abstract final class ComposerKeys {
  /// The composer as one box, so the layout test can measure what the notice
  /// lane must not overlap.
  static const Key composer = Key('mkvi.workspace.composer');

  /// The field itself — the target of `tester.enterText`.
  static const Key input = Key('mkvi.workspace.composer.input');

  /// The send control.
  static const Key send = Key('mkvi.workspace.composer.send');

  /// The permanent line under the field.
  static const Key helper = Key('mkvi.workspace.composer.helper');
}

/// The bottom row of the workspace: write, and send.
class MessageComposer extends StatefulWidget {
  /// Creates the composer.
  const MessageComposer({
    super.key,
    required this.onSend,
    this.controller,
    this.focusNode,
    this.channelOpen = true,
    this.queuedCount = 0,
    this.maxLines = 4,
  });

  /// Called with the trimmed body; answers whether the line was written down.
  final bool Function(String body) onSend;

  /// The text, when the screen owns it. Not disposed here.
  final TextEditingController? controller;

  /// The focus, when the screen owns it. Not disposed here.
  final FocusNode? focusNode;

  /// Whether the data channel is up. It changes one sentence and nothing else.
  final bool channelOpen;

  /// How many lines are waiting for the channel, i.e.
  /// [ChatController.queuedCount].
  final int queuedCount;

  /// How many lines tall the field may grow. The field is one line until the
  /// user asks for more, and a composer that never grows is a composer a
  /// paragraph has to be pasted into sideways.
  final int maxLines;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  TextEditingController? _ownText;
  FocusNode? _ownFocus;

  TextEditingController get _text =>
      widget.controller ?? (_ownText ??= TextEditingController());

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    // The listener, not `onChanged`: a test's `enterText` and a paste both
    // change the controller's value without a keystroke, and the send button's
    // enabled state has to follow those too.
    _text.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onTextChanged);
      _text.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _text.removeListener(_onTextChanged);
    _ownText?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  /// Whether there is anything to send. The one and only disabled state.
  bool get canSend => _text.text.trim().isNotEmpty;

  /// The permanent sentence under the field.
  ///
  /// Never empty and never conditionally absent: a helper line that appears and
  /// disappears moves the whole conversation above it, and the user is looking
  /// at the list, not at the composer.
  String get helperText {
    if (!widget.channelOpen) return ChatMessages.holdingForReconnect;
    if (widget.queuedCount > 0) {
      return workspaceQueuedLines(widget.queuedCount);
    }
    return WorkspaceTr.composerHelper.tr;
  }

  void _submit() {
    if (!canSend) return;
    if (widget.onSend(_text.text)) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Padding(
      key: ComposerKeys.composer,
      padding: EdgeInsets.fromLTRB(
        style.gap('4'),
        style.gap('3'),
        style.gap('4'),
        style.gap('4'),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MkviDivider(),
          SizedBox(height: style.gap('3')),
          Row(
            // Bottom-aligned, so a one-line field and a four-line field keep the
            // send button on the same line as the last line of text.
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: ConstrainedBox(
                  // The `md` control is 34 dp and the promise is 44: a field is
                  // a control the user aims at, so it gets the larger of the
                  // two — the same rule `MkviTextField` applies.
                  constraints: BoxConstraints(
                    minHeight: style.control('md').height < style.hitTargetMin
                        ? style.hitTargetMin
                        : style.control('md').height,
                  ),
                  child: TextField(
                    key: ComposerKeys.input,
                    controller: _text,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: widget.maxLines,
                    keyboardType: TextInputType.multiline,
                    // Enter is a newline in a multi-line field, so the action
                    // key says so; sending is the button, and the button is the
                    // thing the reported bug made unreachable.
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    style: mkviInputTextStyle(style),
                    cursorColor: style.role('accent'),
                    decoration: InputDecoration(
                      hintText: WorkspaceTr.composerHint.tr,
                      helperText: helperText,
                      helperMaxLines: 2,
                      helperStyle: style
                          .styleOf('2xs')
                          .copyWith(color: style.role('textMuted')),
                    ),
                  ),
                ),
              ),
              SizedBox(width: style.gap('2')),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: style.hitTargetMin,
                  minHeight: style.hitTargetMin,
                ),
                child: Tooltip(
                  message: WorkspaceTr.sendHint.tr,
                  child: FilledButton.icon(
                    key: ComposerKeys.send,
                    // Null, not `false`: a disabled control stays in the layout
                    // and stays reachable by a screen reader, which is how a
                    // user learns that there is a button at all.
                    onPressed: canSend ? _submit : null,
                    icon: Icon(Icons.send_rounded, size: style.control('md').iconSize),
                    label: Text(
                      WorkspaceTr.send.tr,
                      style: style.styleOf('sm'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
