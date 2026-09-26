/// Every fake MKVI's seams have, in one library.
///
/// ```dart
/// import 'package:mkvi_test/../support/fakes/fakes.dart';
/// ```
///
/// (In this repository: `import '../support/fakes/fakes.dart';` from a suite
/// under `app/test/`, or `import 'support/fakes/fakes.dart';` from
/// `app/test/` itself.)
///
/// ## The three rules every fake here follows
///
/// 1. **A behaviour that is a decision must be written down by the test.** Until
///    it is, the call raises [UnscriptedCallError] instead of answering. A double
///    that answers a call nobody asked for proves nothing, and it proves it
///    *loudly green* - which is the shape of MKVI's most expensive bug.
/// 2. **Every call is recorded, in order.** `ROADMAP.md` Faz 5 models the
///    ordering contract (`accept` -> `[SendFrame, PublishMedia]`) as data, so
///    `fake.log.order` is a `List<String>` and a test can compare it directly.
/// 3. **An error path is scriptable like any other.** Production swallowed
///    errors quietly in three places; a double that cannot throw cannot prove
///    the swallowing was removed.
///
/// ## Which fake for which question
///
/// | question | ask |
/// |---|---|
/// | what happens to a line while the channel is down | `FakeChatHarness` |
/// | does a timer fire at 45 s, and only that one | `FakeCallHarness.advance` |
/// | did a second identity get minted at startup | `FakeSessionHarness.identity.calls` |
/// | is a signature checked over the whole artefact | `FakeUpdateHarness` |
/// | is the camera light still on after the call | `FakeMediaHarness.orphanedTracks` |
///
/// ## Layer notes
///
/// `fakes/README.md` says which fake replaces which production type and when to
/// reach for which one. This barrel is only the list.
library;

export 'call_fakes.dart';
export 'chat_fakes.dart';
export 'layer_harness.dart';
export 'media_fakes.dart';
export 'script_log.dart';
export 'session_fakes.dart';
export 'update_fakes.dart';
