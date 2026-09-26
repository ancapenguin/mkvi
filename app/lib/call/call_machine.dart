/// The call state machine: one call, one status, two symmetric 45 s timeouts.
///
/// ## Why the state is one enum and not three maps
///
/// The call has exactly one lifecycle, and modelling it as separate pending,
/// incoming and active collections is what produced the four defects below: each
/// one is a direct consequence of guessing a status by set membership, and each
/// is now structurally impossible.
///
/// 1. **An answer step exists.** Nothing auto-accepts: [accept] is the only way in
///    and it is guarded against a call that has already ended.
/// 2. **Both sides arm a 45 s timer.** An unanswered answer screen can therefore
///    never stay up forever with both buttons disabled. The two timers are
///    separate fields so a test can fire one and assert the other stayed put.
/// 3. **A decline has its own outcome.** [CallDeclined] is distinct from
///    [CallTimedOut] and from [CallFailed], because "she said no" and "she did not
///    answer" are different facts and a missed-call list that cannot tell them
///    apart is not a missed-call list.
/// 4. **The callee never publishes before it accepted.** [accept] emits its actions
///    in order — `call-accept` first, media second — and emits none at all when the
///    call has already ended.
///
/// ## What this deliberately does not do
///
/// There is no WebRTC, no capture, no data channel and no `dart:async` timer in
/// this class. Everything the machine wants the outside world to do arrives in
/// [CallTransition.actions], in order, and the two timeouts are the injected
/// [CallTimerStarter]. That is what makes all of the above testable without a
/// camera, a peer or a second machine.
library;

import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/core/protocol/text_sanitizer.dart';
import 'package:mkvi/core/protocol/transfer_id.dart';

import 'call_action.dart';
import 'call_messages.dart';
import 'call_outcome.dart';
import 'call_refusal.dart';
import 'call_session.dart';
import 'call_status.dart';
import 'call_timers.dart';
import 'call_transition.dart';
import 'missed_call.dart';

/// The one call this device is in, or the one it is being invited to.
///
/// Not a `ChangeNotifier`: the port takes no state-management library
/// (`ROADMAP.md`, "UI kütüphanesi, i18n, durum yönetimi alınmaz"). A `ValueListenable`
/// or a hand-written `ChangeNotifier` in the UI layer subscribes to [onTransition]
/// and re-renders. Every public method returns a [CallTransition] and none of them
/// throws.
final class CallMachine {
  /// [startTimer] is the *whole* clock seam and is deliberately required: the
  /// machine cannot arm a timer the caller did not hand it, so no test can ever
  /// wait 45 real seconds and no production wiring can forget to pass
  /// [asyncCallTimerStarter].
  CallMachine({
    required this.startTimer,
    DateTime Function()? now,
    String Function()? idFactory,
    this.offerTimeout = callOfferTimeout,
    this.ringTimeout = callRingTimeout,
    this.onTransition,
  }) : _now = now ?? DateTime.now,
       _newId = idFactory ?? randomTransferId;

  /// How long the caller waits for a `call-accept` before sending a `call-end`
  /// and giving up.
  static const Duration callOfferTimeout = Duration(seconds: 45);

  /// The callee-side twin of [callOfferTimeout].
  ///
  /// The two are separate fields, not one constant, so a test can make one of them
  /// fire and assert that the *other* one did not — which is the only way to prove
  /// the 45 s on each side means what it claims to.
  static const Duration callRingTimeout = Duration(seconds: 45);

  /// The only way a timer can be created in this package.
  final CallTimerStarter startTimer;

  /// How long a ringing invitation is offered.
  final Duration offerTimeout;

  /// How long an answer screen waits.
  final Duration ringTimeout;

  /// Called for every transition that changed something or put a frame on the
  /// wire. A refused step and a stale frame are *not* reported, so a listener
  /// cannot be woken by a double tap.
  final void Function(CallTransition transition)? onTransition;

  final DateTime Function() _now;
  final String Function() _newId;

  CallStatus _status = CallStatus.idle;
  CallSession? _session;
  CallOutcome? _outcome;
  final List<MissedCall> _missedCalls = <MissedCall>[];
  CallTimerCancel? _cancelOfferTimer;
  CallTimerCancel? _cancelRingTimer;

  // ---------------------------------------------------------------------
  // Read-only view
  // ---------------------------------------------------------------------

  CallStatus get status => _status;

  /// The call being set up, ringing or held, or `null` when the machine holds
  /// none. While [status] is [CallStatus.incoming] this is also the old UI's
  /// `IncomingCallView`: read [CallSession.id] and [CallSession.mode] for it.
  CallSession? get session => _session;

  /// The result of the last call, kept after [reset] so a late listener can still
  /// read it. Cleared when the next call starts.
  CallOutcome? get outcome => _outcome;

  /// Every finished call, oldest first. One entry per call id, ever.
  List<MissedCall> get missedCalls =>
      List<MissedCall>.unmodifiable(_missedCalls);

  MissedCall? get lastMissedCall =>
      _missedCalls.isEmpty ? null : _missedCalls.last;

  /// Whether a call is live, i.e. whether starting or accepting another one is
  /// refused. This is the single guard, and it answers the one question every
  /// entry point has to ask.
  bool get isBusy => _status.isLive;

  /// Whether an answer screen is waiting for the user.
  bool get isRinging => _status.isRinging;

  /// Whether the caller's offer timer is still armed.
  bool get isOfferTimerArmed => _cancelOfferTimer != null;

  /// Whether the callee's ring timer is still armed.
  ///
  /// The answer screen must disappear when this becomes `false`, whether it
  /// became `false` because the user answered or because the ring timeout fired.
  bool get isRingTimerArmed => _cancelRingTimer != null;

  // ---------------------------------------------------------------------
  // Caller side
  // ---------------------------------------------------------------------

  /// Sends a `call-offer` and starts ringing.
  ///
  /// Refused with [CallRefusal.callInProgress] while any call is live, which is
  /// the "Başka bir arama zaten etkin." a caller sees — a *value* here rather
  /// than a rejected promise, so a UI can show it without a catch block.
  ///
  /// No media is published and no frame other than the offer goes out: the caller
  /// may keep a local preview, and the peer learns nothing about it until it
  /// accepts. Publishing the preview after the offer would advertise a camera the
  /// peer has not agreed to receive.
  ///
  /// [id] exists for tests and for a re-announcement; production should let the
  /// machine generate a bare 32 character hex id, because `parseControl` rejects
  /// anything else.
  CallTransition startOutgoing(CallMode mode, {String? id}) {
    if (_status.isLive) {
      return _unchanged(refusal: CallRefusal.callInProgress);
    }
    _disarmAllTimers();
    _outcome = null;
    final String callId = id ?? _newId();
    final DateTime at = _now();
    _session = CallSession(
      id: callId,
      mode: mode,
      side: CallSide.caller,
      status: CallStatus.outgoing,
      startedAt: at,
      offeredAt: at,
    );
    _armOfferTimer(callId);
    return _apply(
      next: CallStatus.outgoing,
      actions: <CallAction>[
        SendFrame(CallOfferMessage(id: callId, mode: mode)),
      ],
    );
  }

  /// The peer accepted. Moves to [CallStatus.connecting] and asks for the media.
  ///
  /// Ignored unless this machine is the caller of exactly this call and is still
  /// ringing, so a stale or forged `call-accept` cannot pull a ringing callee or
  /// a finished call back to [CallStatus.connecting].
  CallTransition onRemoteAccept({String? callId}) {
    final CallSession? ringing = _callerRinging(callId);
    if (ringing == null) return _unchanged();
    _disarmOfferTimer();
    final DateTime at = _now();
    _session = ringing.copyWith(status: CallStatus.connecting, acceptedAt: at);
    return _apply(
      next: CallStatus.connecting,
      actions: <CallAction>[_publishFor(ringing.mode)],
      outcome: CallAccepted(id: ringing.id, at: at),
    );
  }

  // ---------------------------------------------------------------------
  // Callee side
  // ---------------------------------------------------------------------

  /// A `call-offer` arrived.
  ///
  /// Three outcomes, in this order:
  ///
  /// * the id is already on screen — ignored, and the ring timer is **not**
  ///   re-armed, so a peer that re-announces every ten seconds cannot keep an
  ///   answer dialog alive forever;
  /// * a call is live — answered on the wire with a `call-decline` carrying
  ///   [PeerProtocol.busyCallReason] ("Meşgul."), the short wording the protocol
  ///   already owns, rather than a longer sentence that would have to be kept in
  ///   sync with it;
  /// * otherwise — an answer screen, a 45 s ring timer, and **nothing on the
  ///   wire**, because the dialog promises that nothing is sent until the user
  ///   accepts.
  CallTransition onIncomingOffer(CallOfferMessage offer) {
    if (_session?.id == offer.id) return _unchanged();
    if (_status.isLive) {
      return _apply(
        next: _status,
        applied: false,
        refusal: CallRefusal.callInProgress,
        actions: <CallAction>[
          SendFrame(
            CallDeclineMessage(
              id: offer.id,
              reason: PeerProtocol.busyCallReason,
            ),
          ),
        ],
      );
    }
    _disarmAllTimers();
    _outcome = null;
    final DateTime at = _now();
    _session = CallSession(
      id: offer.id,
      mode: offer.mode,
      side: CallSide.callee,
      status: CallStatus.incoming,
      startedAt: at,
      offeredAt: at,
    );
    _armRingTimer(offer.id);
    return _apply(next: CallStatus.incoming);
  }

  /// Answers the ringing screen: `call-accept` first, media second.
  ///
  /// Refused with [CallRefusal.incomingCallNotFound] when there is no ringing
  /// incoming call — which is a real race, not a hypothetical one: the caller's
  /// 45 s `call-end` (or this machine's own ring timeout) lands while the user is
  /// still opening the camera, and the answer button is still on screen. A refusal
  /// puts no frame on the wire and asks for no media, so the UI learns it must
  /// throw away the stream it just opened, and the peer is told nothing about a
  /// call that is already over. An exception here would strand that stream.
  CallTransition accept({String? callId}) {
    final CallSession? session = _session;
    if (session == null ||
        session.side != CallSide.callee ||
        !_status.isRinging ||
        (callId != null && callId != session.id)) {
      return _unchanged(refusal: CallRefusal.incomingCallNotFound);
    }
    _disarmRingTimer();
    final DateTime at = _now();
    _session = session.copyWith(status: CallStatus.connecting, acceptedAt: at);
    return _apply(
      next: CallStatus.connecting,
      actions: <CallAction>[
        // 1. The decision reaches the peer before anything is published, so the
        //    callee's camera cannot be live before the callee said yes. The
        //    reverse order puts a live camera on the wire during a call the
        //    callee may not even end up in.
        SendFrame(CallAcceptMessage(id: session.id)),
        // 2. Only now may the outside world open a camera.
        _publishFor(session.mode),
      ],
      outcome: CallAccepted(id: session.id, at: at),
    );
  }

  /// Answers the ringing screen with "Reddet".
  ///
  /// Idempotent: a second `decline` — from a double tap, or from a
  /// `declineIncomingCall` that runs after the ring timeout — is a silent no-op
  /// and sends no second `call-decline`. The guard is on the *ringing* status
  /// rather than on a stored id, so the check cannot be passed by holding a
  /// record of a call that has already ended.
  ///
  /// Releases no media, because the callee has captured none: the media step does
  /// not exist before [accept].
  CallTransition decline({String? reason}) {
    final CallSession? session = _session;
    if (session == null ||
        session.side != CallSide.callee ||
        !_status.isRinging) {
      return _unchanged();
    }
    _disarmRingTimer();
    final String text = safeReason(
      reason ?? PeerProtocol.defaultCallDeclineReason,
    );
    final DateTime at = _now();
    final MissedCall record = MissedCall(
      id: session.id,
      mode: session.mode,
      at: at,
      reason: MissedCallReason.declined,
      detail: text,
    );
    _missedCalls.add(record);
    _session = session.copyWith(status: CallStatus.ended, endedAt: at);
    return _apply(
      next: CallStatus.ended,
      actions: <CallAction>[
        SendFrame(CallDeclineMessage(id: session.id, reason: text)),
      ],
      outcome: CallEndedLocally(id: session.id, at: at, reason: text),
      missedCall: record,
    );
  }

  // ---------------------------------------------------------------------
  // Both sides, once accepted
  // ---------------------------------------------------------------------

  /// The media is published; the call is live.
  ///
  /// This is the only step into [CallStatus.connected], and it is deliberately
  /// separate from [accept] / [onRemoteAccept] because publishing media is the
  /// transport's asynchronous job: the status must not claim a connection that
  /// `replaceTrack` has not finished. Both entry points therefore wait for the
  /// transport and *then* call this, which is what keeps `connected` from being
  /// a promise rather than a fact.
  CallTransition onMediaReady() {
    final CallSession? session = _session;
    if (session == null || _status != CallStatus.connecting) {
      return _unchanged();
    }
    final DateTime at = _now();
    _session = session.copyWith(status: CallStatus.connected, connectedAt: at);
    return _apply(next: CallStatus.connected);
  }

  /// Turns the camera on in a call that started as audio.
  ///
  /// No new call, no new id, no frame on the wire and no renegotiation: the Dart
  /// transport builds an audio, a camera and a screen transceiver as `sendrecv`
  /// when the connection is created, so this is a `replaceTrack` on a sender that
  /// already exists. The status does not change — a connected call stays
  /// connected — and [CallSession.mode] is how the UI (and a test) reads that the
  /// upgrade happened.
  ///
  /// Refused with [CallRefusal.notConnected] unless the call is
  /// [CallStatus.connected], and with [CallRefusal.alreadyVideo] if the camera is
  /// already on.
  CallTransition upgradeToVideo() {
    final CallSession? session = _session;
    if (session == null || _status != CallStatus.connected) {
      return _unchanged(refusal: CallRefusal.notConnected);
    }
    if (session.mode == CallMode.video) {
      return _unchanged(refusal: CallRefusal.alreadyVideo);
    }
    final DateTime at = _now();
    _session = session.copyWith(mode: CallMode.video, upgradedAt: at);
    return _apply(
      next: CallStatus.connected,
      actions: <CallAction>[
        const PublishMedia(mode: CallMode.video, audio: true, video: true),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Ending
  // ---------------------------------------------------------------------

  /// Hangs up. Idempotent: a second `end()` is a silent no-op and sends no
  /// second `call-end`.
  ///
  /// [notifyPeer] is `false` only when the peer is the one that ended the call and
  /// the local teardown must not echo a `call-end` back. Exactly one caller needs
  /// it, [onRemoteEnd]; every other end is local and does notify.
  ///
  /// Why the call ended, as recorded in [missedCalls]:
  /// [MissedCallReason.endedNormally] if it had connected, [MissedCallReason.declined]
  /// if a ringing answer screen was dismissed, [MissedCallReason.cancelled] if an
  /// unanswered invitation was given up on.
  CallTransition end({bool notifyPeer = true}) {
    final CallSession? session = _session;
    if (session == null || !_status.isLive) return _unchanged();
    return _finish(
      session,
      notifyPeer: notifyPeer,
      recordReason: _localEndReason(session),
      // The notice is built from the state *before* the call ends, which is why
      // it is a factory over the single instant `_finish` reads from the clock.
      outcome: (DateTime at) => CallEndedLocally(
        id: session.id,
        at: at,
        reason: _localEndNotice(session),
      ),
    );
  }

  /// The capture step or the transport failed.
  ///
  /// A callee that cannot open its camera *declines* with the reason — a person
  /// is being told the call cannot happen, and the peer's history should read as
  /// a decline; a caller that cannot place the call cancels it, because there is
  /// nobody on the other end to decline to anything. Either way the result is
  /// [CallFailed], which is deliberately not [CallDeclined]: one is a broken
  /// microphone, the other is a person saying no.
  ///
  /// Ignored when no call is live, so a capture that fails after the call already
  /// ended changes nothing.
  CallTransition fail([String reason = CallMessages.startFailed]) {
    final CallSession? session = _session;
    if (session == null || !_status.isLive) return _unchanged();
    _disarmAllTimers();
    final String text = safeReason(reason);
    final DateTime at = _now();
    final bool declined = session.side == CallSide.callee;
    final List<CallAction> actions = <CallAction>[
      if (declined)
        SendFrame(CallDeclineMessage(id: session.id, reason: text))
      else
        SendFrame(CallEndMessage(id: session.id)),
      if (_mayHaveCapture) const ReleaseMedia(),
    ];
    final MissedCall record = MissedCall(
      id: session.id,
      mode: session.mode,
      at: at,
      reason: declined ? MissedCallReason.declined : MissedCallReason.cancelled,
      detail: text,
    );
    _missedCalls.add(record);
    _session = session.copyWith(status: CallStatus.ended, endedAt: at);
    return _apply(
      next: CallStatus.ended,
      actions: actions,
      outcome: CallFailed(id: session.id, at: at, reason: text),
      missedCall: record,
    );
  }

  // ---------------------------------------------------------------------
  // Remote frames
  // ---------------------------------------------------------------------

  /// The peer sent `call-decline`.
  ///
  /// A decline is a first-class outcome, not an error: a caller that treats it as
  /// a failure cannot tell the user why the person hung up, and a caller that
  /// waits for the connection to drop instead learns about it far too late. It
  /// survives [reset], and it is not a [CallFailed].
  ///
  /// [reason] is the `reason` of a **parsed** [CallDeclineMessage]: the wire
  /// parser has already scrubbed control characters and capped it at
  /// [PeerProtocol.maxReasonLength]. An absent or empty reason falls back to
  /// [PeerProtocol.defaultCallDeclineReason].
  CallTransition onRemoteDecline({String? callId, String? reason}) {
    final CallSession? ringing = _callerRinging(callId);
    if (ringing == null) return _unchanged();
    _disarmOfferTimer();
    final DateTime at = _now();
    final String text = (reason == null || reason.isEmpty)
        ? PeerProtocol.defaultCallDeclineReason
        : reason;
    final MissedCall record = MissedCall(
      id: ringing.id,
      mode: ringing.mode,
      at: at,
      reason: MissedCallReason.declined,
      detail: text,
    );
    _missedCalls.add(record);
    _session = ringing.copyWith(status: CallStatus.ended, endedAt: at);
    return _apply(
      next: CallStatus.ended,
      actions: <CallAction>[if (_mayHaveCapture) const ReleaseMedia()],
      outcome: CallDeclined(id: ringing.id, at: at, reason: text),
      missedCall: record,
    );
  }

  /// The peer sent `call-end`.
  ///
  /// Before the call connected this is a *cancellation*, after it an *end*, and
  /// the two get different outcomes and different history reasons, because a
  /// missed-call list that cannot tell them apart is not a missed-call list. The
  /// "before" wording is the peer's cancellation notice, the "after" one is a
  /// normal hangup.
  ///
  /// Ignored when no call is live, so a late `call-end` after a local hangup
  /// cannot produce a second history entry.
  CallTransition onRemoteEnd({String? callId}) {
    final CallSession? session = _session;
    if (session == null ||
        !_status.isLive ||
        (callId != null && callId != session.id)) {
      return _unchanged();
    }
    return _finish(
      session,
      notifyPeer: false,
      recordReason: _status.isSettled
          ? MissedCallReason.endedNormally
          : MissedCallReason.cancelled,
      outcome: _status.isSettled
          ? (DateTime at) => CallEndedByRemote(id: session.id, at: at)
          : (DateTime at) => CallCancelledByRemote(id: session.id, at: at),
    );
  }

  // ---------------------------------------------------------------------
  // Returning to idle
  // ---------------------------------------------------------------------

  /// Drops the finished call and returns to [CallStatus.idle].
  ///
  /// Refused with [CallRefusal.callStillRunning] while a call is live — that is
  /// the one thing a UI must not be able to do by accident — and a silent no-op
  /// when already idle, so a second `reset()` after the first is harmless. Both
  /// the normal return-to-idle and the post-decline return land here.
  CallTransition reset() {
    if (_status == CallStatus.idle) return _unchanged();
    if (_status.isLive) {
      return _unchanged(refusal: CallRefusal.callStillRunning);
    }
    _disarmAllTimers();
    _session = null;
    return _apply(next: CallStatus.idle);
  }

  /// Cancels both timers. Idempotent, and the only thing a `dispose` needs to do
  /// because the machine owns nothing else.
  void dispose() => _disarmAllTimers();

  // ---------------------------------------------------------------------
  // Timeouts
  // ---------------------------------------------------------------------

  void _armOfferTimer(String callId) {
    _disarmOfferTimer();
    _cancelOfferTimer = startTimer(offerTimeout, () => _onOfferTimeout(callId));
  }

  void _onOfferTimeout(String callId) {
    _cancelOfferTimer = null;
    // Two guards, and each one exists. The id stops a *stale* timer — one armed
    // for a call that has already ended — from ending the call that is live now.
    // The side and the status are what separate this from the ring timeout: only a
    // caller waiting for a `call-accept` can time out here, while a machine that
    // is ringing for an answer has a ring timer instead. Without the second guard
    // the two would be one bug with two names.
    final CallSession? ringing = _callerRinging(callId);
    if (ringing == null) return;
    final DateTime at = _now();
    final MissedCall record = MissedCall(
      id: ringing.id,
      mode: ringing.mode,
      at: at,
      reason: MissedCallReason.timedOut,
    );
    _missedCalls.add(record);
    _session = ringing.copyWith(status: CallStatus.ended, endedAt: at);
    _apply(
      next: CallStatus.ended,
      // The caller tells the peer it is giving up before it stops its own
      // capture: a silent `call-end` would leave the peer ringing a call that
      // will never be answered.
      actions: <CallAction>[
        SendFrame(CallEndMessage(id: ringing.id)),
        if (_mayHaveCapture) const ReleaseMedia(),
      ],
      outcome: CallTimedOut(
        id: ringing.id,
        at: at,
        waited: offerTimeout,
        offeredByUs: true,
      ),
      missedCall: record,
    );
  }

  void _armRingTimer(String callId) {
    _disarmRingTimer();
    _cancelRingTimer = startTimer(ringTimeout, () => _onRingTimeout(callId));
  }

  void _onRingTimeout(String callId) {
    _cancelRingTimer = null;
    final CallSession? session = _session;
    if (session == null || session.id != callId || !_status.isRinging) return;
    final DateTime at = _now();
    final String text = safeReason(CallMessages.ringTimeoutReason);
    final MissedCall record = MissedCall(
      id: session.id,
      mode: session.mode,
      at: at,
      reason: MissedCallReason.timedOut,
      detail: text,
    );
    _missedCalls.add(record);
    _session = session.copyWith(status: CallStatus.ended, endedAt: at);
    _apply(
      next: CallStatus.ended,
      // The counterpart of the caller's `call-end`: a *decline*, because the
      // callee is the one who has to tell the peer the answer screen is gone.
      // The reason is the Turkish "Cevap verilmedi." and it is the only thing
      // that tells the caller the difference between "she said no" and "she did
      // not hear it".
      actions: <CallAction>[
        SendFrame(CallDeclineMessage(id: session.id, reason: text)),
      ],
      outcome: CallTimedOut(
        id: session.id,
        at: at,
        waited: ringTimeout,
        offeredByUs: false,
      ),
      missedCall: record,
    );
  }

  void _disarmOfferTimer() {
    _cancelOfferTimer?.call();
    _cancelOfferTimer = null;
  }

  void _disarmRingTimer() {
    _cancelRingTimer?.call();
    _cancelRingTimer = null;
  }

  void _disarmAllTimers() {
    _disarmOfferTimer();
    _disarmRingTimer();
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  /// The caller of [callId] while it is still waiting, or `null` for anything
  /// else. Both remote-settle handlers need this, and both must be guarded by it:
  /// a `call-accept` or `call-decline` that names a call this machine is not
  /// ringing as caller has to be dropped, not applied to whatever call happens to
  /// be live.
  ///
  /// Returning the session instead of a `bool` is what lets the caller sites use
  /// a promoted local, so no `!` is needed to reach `session.id` afterwards.
  CallSession? _callerRinging(String? callId) {
    final CallSession? session = _session;
    if (session == null ||
        session.side != CallSide.caller ||
        _status != CallStatus.outgoing) {
      return null;
    }
    return callId == null || callId == session.id ? session : null;
  }

  /// Whether local capture can exist right now.
  ///
  /// The callee captures nothing before it accepts — that is the promise the
  /// answer dialog makes — so a pre-accept ending releases nothing, while every
  /// caller ending has to release the preview the user could see.
  bool get _mayHaveCapture {
    final CallSession? session = _session;
    if (session == null) return false;
    return session.side == CallSide.caller || _status.isSettled;
  }

  PublishMedia _publishFor(CallMode mode) =>
      PublishMedia(mode: mode, audio: true, video: modeWantsVideo(mode));

  MissedCallReason _localEndReason(CallSession session) {
    if (_status.isSettled) return MissedCallReason.endedNormally;
    return session.side == CallSide.callee
        ? MissedCallReason.declined
        : MissedCallReason.cancelled;
  }

  String _localEndNotice(CallSession session) {
    if (_status.isSettled) return CallMessages.callEndedLocally;
    return session.side == CallSide.callee
        ? PeerProtocol.defaultCallDeclineReason
        : CallMessages.callCancelledLocally;
  }

  /// The single place a call becomes [CallStatus.ended]: disarm, optionally answer
  /// the peer, release what was captured, record exactly one history entry.
  CallTransition _finish(
    CallSession session, {
    required bool notifyPeer,
    required MissedCallReason recordReason,
    required CallOutcome Function(DateTime at) outcome,
  }) {
    _disarmAllTimers();
    final DateTime at = _now();
    final List<CallAction> actions = <CallAction>[
      // The peer is not told twice: a hangup that arrives *because* the peer hung
      // up must not echo a `call-end` back, or the two peers can trade the frame
      // forever.
      if (notifyPeer) SendFrame(CallEndMessage(id: session.id)),
      if (_mayHaveCapture) const ReleaseMedia(),
    ];
    final MissedCall record = MissedCall(
      id: session.id,
      mode: session.mode,
      at: at,
      reason: recordReason,
    );
    _missedCalls.add(record);
    _session = session.copyWith(status: CallStatus.ended, endedAt: at);
    return _apply(
      next: CallStatus.ended,
      actions: actions,
      outcome: outcome(at),
      missedCall: record,
    );
  }

  CallTransition _unchanged({CallRefusal? refusal}) =>
      _apply(next: _status, applied: false, refusal: refusal);

  CallTransition _apply({
    required CallStatus next,
    List<CallAction> actions = const <CallAction>[],
    CallOutcome? outcome,
    MissedCall? missedCall,
    bool applied = true,
    CallRefusal? refusal,
  }) {
    final CallStatus previous = _status;
    if (outcome != null) _outcome = outcome;
    _status = next;
    final CallTransition transition = CallTransition(
      status: next,
      previousStatus: previous,
      applied: applied,
      session: _session,
      actions: actions,
      outcome: outcome,
      missedCall: missedCall,
      refusal: refusal,
    );
    if (applied || actions.isNotEmpty) onTransition?.call(transition);
    return transition;
  }
}
