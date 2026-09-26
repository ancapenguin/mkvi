/// The history control: the only way to reach the lines the window has already
/// forgotten, and the answer to "is there anything older?".
///
/// ## Why the control is a button and not a scroll-to-top
///
/// `ChatTimeline.exhausted` is the store's answer to "is there anything before
/// the oldest line I hold", and it is the only thing that may set it. A
/// scroll-triggered read therefore has a second problem the button does not:
/// the user would have to keep scrolling to find out that there is nothing,
/// which is the same "did it break or is there simply nothing?" question
/// `ROADMAP.md` Faz 1's broken-peer screen was about. A button says it, and it
/// says it in Turkish.
///
/// While a page is on its way the control becomes a **disabled button with a
/// different word**, not a spinner. `lib/ui/widgets` starts no clock — an
/// `AnimationController` with `repeat()` never lets `pumpAndSettle` return, and
/// that is how every overflow assertion in `test/support/mkvi_test_app.dart`
/// would be lost to a timeout. The row also keeps its height either way, so the
/// conversation above it does not jump when the button changes its word.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'workspace_strings.dart';

/// The keys the history control's parts answer to.
abstract final class WorkspaceHistoryKeys {
  /// The region, as one box.
  static const Key region = Key('mkvi.workspace.history');

  /// The control itself — the button, or the disabled button while loading.
  static const Key control = Key('mkvi.workspace.history.control');

  /// The line that says there is nothing older, shown once the history is
  /// exhausted and at least one line is on screen.
  static const Key status = Key('mkvi.workspace.history.status');
}

/// The "read an older page" row, between the conversation and the notice lane.
class WorkspaceHistory extends StatelessWidget {
  /// Creates the control.
  const WorkspaceHistory({
    super.key,
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
    this.lineCount = 0,
  });

  /// Whether the history may still have an older page —
  /// [ChatController.hasOlderHistory].
  final bool hasMore;

  /// Whether a page is on its way. A second press while it is loading is
  /// ignored, so the button cannot be made to read twice.
  final bool loading;

  /// Reads the page before the oldest line held —
  /// [ChatController.loadOlderHistory].
  final VoidCallback onLoadMore;

  /// How many lines are on screen, so the "nothing older" line is not shown
  /// above an empty conversation — where the empty state already says it.
  final int lineCount;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Padding(
      key: WorkspaceHistoryKeys.region,
      padding: EdgeInsets.symmetric(
        horizontal: style.gap('4'),
        vertical: style.gap('2'),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MkviDivider(),
          SizedBox(height: style.gap('2')),
          if (loading || hasMore)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // `Flexible`, because "Daha eski mesajları yükle" is a Turkish
                // sentence and a 368 dp phone-shaped window does not hold it on
                // one line. The label inside the button already wraps; what it
                // cannot do is make its own `Row` narrower than its content.
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: style.hitTargetMin,
                      minHeight: style.hitTargetMin,
                    ),
                    child: MkviActionButton(
                      key: WorkspaceHistoryKeys.control,
                      // A disabled action keeps its place in the layout and
                      // stays in the semantics tree, so a screen reader still
                      // finds the control and can say what it will do when it
                      // comes back.
                      action: MkviPanelAction(
                        label: loading
                            ? WorkspaceTr.historyLoading.tr
                            : WorkspaceTr.loadOlder.tr,
                        onPressed: loading ? null : onLoadMore,
                        icon: loading
                            ? Icons.hourglass_top_rounded
                            : Icons.history_rounded,
                      ),
                      surfaceRole: 'bg',
                    ),
                  ),
                ),
              ],
            )
          else if (lineCount > 0)
            Text(
              WorkspaceTr.historyComplete.tr,
              key: WorkspaceHistoryKeys.status,
              textAlign: TextAlign.center,
              style: style
                  .styleOf('2xs')
                  .copyWith(color: style.role('textMuted')),
            ),
        ],
      ),
    );
  }
}
