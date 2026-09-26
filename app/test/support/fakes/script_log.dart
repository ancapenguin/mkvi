/// The one thing every fake in this directory shares: an ordered record of
/// every call it received, and a refusal for the calls no test arranged.
///
/// ## Why this exists
///
/// MKVI's most expensive lesson is "the test was green and the feature was
/// broken". Almost every instance of it was a **silent no-op in a double**: a
/// fake whose `write` returned `0` for a transfer nobody opened, a peer store
/// that answered `PeerAbsent` because nobody had scripted an answer, a fetcher
/// that reported `FeedReadFailed('no answer scripted')` and was therefore
/// indistinguishable from a dead server. A double that answers "fine" without
/// having been asked anything proves nothing, and it proves it *loudly green*.
///
/// So the rule every fake here follows:
///
/// 1. A behaviour that is a *decision* must be written down by the test. Until
///    it is, the call raises [UnscriptedCallError] instead of answering.
/// 2. Every call is recorded, in order, whether it succeeded or blew up. The
///    order is data: `ROADMAP.md` Faz 5 models the ordering contract
///    (`accept` -> `[SendFrame, PublishMedia]`) as a list, not as prose.
/// 3. An error path is scriptable like any other. Production swallowed errors
///    quietly in three places (`media_fault.dart` exists because of them), so a
///    double that cannot throw cannot prove the swallowing was removed.
///
/// A written default is a member the fake *defines* with [ScriptLog.define] -
/// a behaviour that is honestly total, like "`read` of a key that was never
/// written is null". Those are listed in [ScriptLog.writtenDefaults] so a
/// reader can tell the two apart instead of guessing.
library;

/// One call a fake received.
///
/// [member] is a plain string, so an assertion can be written against the order
/// of calls as data:
///
/// ```dart
/// expect(channel.log.order, <String>['send', 'sendFrame', 'abort']);
/// ```
final class RecordedCall {
  const RecordedCall(this.seam, this.member, {this.detail});

  /// The fake that received it, e.g. `ScriptedFileSink`.
  final String seam;

  /// The member, e.g. `open`, `write`, `read:mkvi.selfName`.
  final String member;

  /// Whatever the fake chose to attach: a path, a frame type, a byte count.
  final Object? detail;

  @override
  String toString() => detail == null
      ? '$seam.$member'
      : '$seam.$member -> $detail';
}

/// Thrown when a fake is called for something no test arranged.
///
/// A [StateError] on purpose: it is a defect in the *test*, and a test that has
/// not arranged a behaviour must go red rather than get a plausible answer.
final class UnscriptedCallError extends StateError {
  UnscriptedCallError({
    required this.seam,
    required this.member,
    required List<String> arranged,
    this.detail,
    String? hint,
  }) : super(
         'Unscripted call: $seam.$member'
         '${detail == null ? '' : ' -> $detail'} was never arranged.\n'
         'A fake that answers a call no test asked for proves nothing, so this '
         'one refuses. Arrange it first'
         '${hint == null ? '' : ' ($hint)'}, or call '
         'log.arrange(\'$member\') to accept whatever it does.\n'
         'Already arranged: '
         '${arranged.isEmpty ? '(nothing)' : arranged.join(', ')}',
       );

  final String seam;
  final String member;
  final Object? detail;
}

/// The ordered call record of one fake.
final class ScriptLog {
  ScriptLog(this.seam);

  /// The fake's own name, so a failure reads without a stack trace.
  final String seam;

  /// Every call, in order, including the one that raised.
  final List<RecordedCall> calls = <RecordedCall>[];

  /// The subset of [calls] that was never arranged, in order. Empty at the end
  /// of a passing test; the thing `expect(fake.log.unrecorded, isEmpty)` reads.
  final List<RecordedCall> unrecorded = <RecordedCall>[];

  final Set<String> _arranged = <String>{};
  final Map<String, String> _written = <String, String>{};

  /// The members this fake defines itself, with a one-line description of what
  /// it does. A written default is a *total* behaviour - one that has a right
  /// answer for every input - and listing it is what keeps "this fake is
  /// permissive here" from being an invisible convention.
  Map<String, String> get writtenDefaults =>
      Map<String, String>.unmodifiable(_written);

  /// The members this test arranged, in the order it arranged them.
  List<String> get arrangedMembers => List<String>.unmodifiable(_arranged);

  /// Declares a written default. Called from a fake's constructor, never from a
  /// test: a test that wants a decision uses [arrange].
  void define(String member, String description) {
    _written[member] = description;
  }

  /// Arranges [member] for this test.
  void arrange(String member) => _arranged.add(member);

  /// Arranges several members at once.
  void arrangeAll(Iterable<String> members) => _arranged.addAll(members);

  /// Whether a call to [member] has somewhere to go.
  bool isArranged(String member) =>
      _arranged.contains(member) || _written.containsKey(member);

  /// Records a call, and refuses it when nothing was arranged.
  ///
  /// Records *before* it raises, so a test that catches the error can still read
  /// the receipt, and so the call never half-happened: the raise happens before
  /// the fake touches its own state.
  void record(String member, {Object? detail, String? hint}) {
    final RecordedCall call = RecordedCall(seam, member, detail: detail);
    calls.add(call);
    if (isArranged(member)) return;
    unrecorded.add(call);
    throw UnscriptedCallError(
      seam: seam,
      member: member,
      detail: detail,
      arranged: arrangedMembers,
      hint: hint,
    );
  }

  /// Records a call that can never be unarranged, because it is a poll rather
  /// than a decision. Still counted, still ordered, just never refused.
  void poll(String member) {
    calls.add(RecordedCall(seam, member));
  }

  /// How many times [member] was called.
  int countOf(String member) =>
      calls.where((RecordedCall c) => c.member == member).length;

  /// The member names in call order. The order contract, as data.
  List<String> get order => <String>[
    for (final RecordedCall call in calls) call.member,
  ];

  /// Every call to [member], in order.
  List<RecordedCall> of(String member) => calls
      .where((RecordedCall c) => c.member == member)
      .toList(growable: false);

  /// The details of every call to [member], in order.
  List<Object?> detailsOf(String member) => <Object?>[
    for (final RecordedCall call in of(member)) call.detail,
  ];

  /// Whether nothing has been called.
  bool get isEmpty => calls.isEmpty;

  /// Forgets everything, so one fake can serve two phases of a test without the
  /// first phase's calls colouring the second phase's assertions.
  void clear() {
    calls.clear();
    unrecorded.clear();
  }

  @override
  String toString() =>
      'ScriptLog($seam, ${calls.length} calls, ${unrecorded.length} unarranged)';
}

/// Yields to the event loop until [reached] is true, then throws rather than
/// hanging when the code under test never arrives.
///
/// Every fake here completes through a real `Future`, so a test has to let the
/// loop run. A timeout that hangs tells you nothing; one that throws names the
/// predicate that never became true.
Future<void> pumpUntil(
  bool Function() reached, {
  String reason = 'the expected point',
  int turns = 2000,
}) async {
  for (int turn = 0; turn < turns; turn += 1) {
    if (reached()) return;
    await Future<void>.delayed(Duration.zero);
  }
  if (reached()) return;
  throw StateError('the loop never reached $reason after $turns turns');
}

/// Lets the broadcast streams of the fakes deliver everything a test has
/// already caused.
///
/// A `StreamController.broadcast().add` runs its listeners in a later turn than
/// the `add`, so a report returned from a `Future` can arrive before the last
/// event has landed. One `await Future<void>.delayed(Duration.zero)` is enough
/// for the microtask queue the controllers use.
Future<void> settle() => Future<void>.delayed(Duration.zero);
