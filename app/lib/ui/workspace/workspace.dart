/// The workspace: the conversation and the file lane, in one window.
///
/// `ROADMAP.md` Faz 6 — mesaj listesi + geçmiş, gönderme durumu; dosya
/// aktarımı, ilerleme, iptal — is the last of the ten layers to reach a screen.
/// Everything below it was already written and tested: `lib/chat` has the
/// conversation, the queue, the history handoff, the transfer coordinator and
/// the `FileSink` contract; `lib/session` has [PeerNameView], the two names;
/// `lib/ui/notice` has the lane that reserves its own space; `lib/ui/widgets`
/// has the surfaces, the states, the badges, the bars and the fields.
///
/// ## What this package adds, and what it deliberately does not
///
/// It adds **layout decisions and nothing else**:
///
/// * [WorkspaceScreen] is where [NoticeHost] is placed — in flow, between the
///   list and the composer — which is the fix for the reported defect where a
///   `z-index: 100` toast sat on the send button and nothing could be typed;
/// * [WorkspaceMessageRow] draws the four delivery states as four rows, and a
///   line that has not gone out keeps its "Yeniden dene" and "Sil" instead of
///   disappearing, which is what "no message ever arrives" looked like;
/// * [WorkspaceTransferRow] draws five phases in a box that cannot grow without
///   bound and **never paints a saved path**, which is the same unbounded text
///   the toast grew on;
/// * [WorkspaceHeader] asks [PeerNameView] instead of comparing two names, so
///   the local note cannot overwrite the name the peer announced.
///
/// Every other value in this package is read out of one of those layers, and
/// every number is read out of [AppearanceStyle] — there is no colour literal,
/// no pixel literal, no `dart:math` and no hard-coded `Duration` under
/// `lib/ui/workspace/`, which `flutter analyze` and the overflow matrix in
/// `test/ui/workspace/` both check.
///
/// ## One import, no cycles
///
/// Same arrangement `lib/chat/chat.dart` and `lib/ui/notice/notice.dart` use:
/// the barrel exports the six files, the six files import each other only
/// where a dependency is real, and the strings live in one file so no widget
/// can be built with no Turkish wording.
library;

export 'message_composer.dart';
export 'message_list.dart';
export 'transfer_list.dart';
export 'workspace_header.dart';
export 'workspace_history.dart';
export 'workspace_screen.dart';
export 'workspace_strings.dart';
