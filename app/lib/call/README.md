# `lib/call` — the call state machine

Pure Dart. No WebRTC, no `flutter`, no `dart:io`, and **no timer of its own**: the two
45 s timeouts are an injected `CallTimerStarter`, so `test/call` drives a whole call —
including both timeouts — without a camera, a peer or a second machine.

```dart
final CallMachine machine = CallMachine(
  startTimer: asyncCallTimerStarter, // production; tests pass a fake
  onTransition: (CallTransition t) => setState(() {}),
);
```

Every method returns a `CallTransition` and **none of them throws**. A refused step comes
back with `refusal` set and Turkish text on it, which is what keeps "Arama reddedildi."
out of the media-error box.

## The order the caller must run things in

`CallTransition.actions` is ordered, and the order is the contract:

| step | actions, in order |
|---|---|
| `startOutgoing` | `call-offer` |
| `onRemoteAccept` | `PublishMedia` |
| `onMediaReady` | — |
| `onIncomingOffer` (admitted) | — |
| `accept` | **`call-accept`, then `PublishMedia`** |
| `decline` | `call-decline` |
| `upgradeToVideo` | `PublishMedia` (no frame: `replaceTrack`, no renegotiation) |
| `end` / `fail` / any timeout / `onRemoteEnd` | `call-end` (when it must be sent), `ReleaseMedia` |

`ReleaseMedia` is absent on the callee's pre-accept paths (`decline`, the ring timeout,
a remote `call-end` while ringing) because the callee has captured nothing: the media step
does not exist before `accept`. That is the promise the answer dialog makes, kept literally.

## Transitions

`from → event → to`, with the guard that allows it. `busy` is `status.isLive`.

| from | event | to | guard | frames out |
|---|---|---|---|---|
| `idle` \| `ended` | `startOutgoing(mode)` | `outgoing` | never busy | `call-offer` |
| `outgoing` | `onRemoteAccept` | `connecting` | caller side **and** that id **and** still `outgoing` | — |
| `connecting` | `onMediaReady` | `connected` | `replaceTrack` finished | — |
| `connected` | `upgradeToVideo` | `connected` | `connected` **and** mode is `audio` | — |
| `idle` \| `ended` | `onIncomingOffer` | `incoming` | id not already on screen **and** not busy | — |
| busy | `onIncomingOffer` | *unchanged* | — | `call-decline` (`Meşgul.`) |
| `incoming` | `accept` | `connecting` | callee side **and** that id **and** still ringing | `call-accept` |
| `incoming` | `decline` | `ended` | callee side **and** still ringing | `call-decline` |
| `outgoing` | `onRemoteDecline` | `ended` | caller side **and** that id **and** still `outgoing` | — |
| any live | `end`, `fail` | `ended` | a call is live | `call-end` (unless `notifyPeer: false`), `ReleaseMedia` |
| any live | `onRemoteEnd` | `ended` | a call is live **and** that id | — , `ReleaseMedia` |
| `outgoing` | 45 s offer timer | `ended` | caller side **and** that id **and** still `outgoing` | `call-end`, `ReleaseMedia` |
| `incoming` | 45 s ring timer | `ended` | callee side **and** that id **and** still ringing | `call-decline` (`Cevap verilmedi.`) |
| `ended` | `reset` | `idle` | — | — |

Everything else is a silent no-op that returns `applied: false` and puts nothing on the
wire: a stale or duplicated remote frame, a second `end`, a second `decline`, a second
`reset`, `decline` on a call that is not a ringing incoming one. The refusals that *do*
carry a message, because a user pressed something and deserves an answer, are
`startOutgoing` while busy (`callInProgress`), `accept` with no ringing incoming call
(`incomingCallNotFound`), `upgradeToVideo` outside `connected` (`notConnected` or
`alreadyVideo`), and `reset` while a call is live (`callStillRunning`).

The two timer guards are the reason the two timeouts cannot be confused: the offer timer
only means something in `outgoing` on the caller side, the ring timer only in `incoming` on
the callee side, and both are additionally keyed to the id they were armed for.

## What the UI layer needs

- `status` / `CallStatus.label` — the six states and their Turkish labels.
- `session` — id, mode, side, `startedAt`, `acceptedAt`, `connectedAt`, `endedAt`. While
  `status == incoming` it is the old UI's `IncomingCallView`.
- `outcome` / `CallOutcome.notice` — the one line to show. `CallDeclined`,
  `CallTimedOut(offeredByUs:)`, `CallCancelledByRemote`, `CallEndedByRemote`,
  `CallEndedLocally`, `CallFailed` are distinct types, so a decline cannot be rendered
  as a failure by accident.
- `missedCalls` / `lastMissedCall` — one immutable entry per finished call, oldest first,
  with a `MissedCallReason` of `declined`, `timedOut`, `cancelled` or `endedNormally`.
  Survives `reset`, because a call log has to outlive the call stage.
- `isRingTimerArmed` — the answer screen is dismissed when it turns `false`, whether the
  user answered or the ring timeout fired.
- `CallMessages` — the dialog strings, including `mediaPromise`, the sentence the
  implementation above keeps true.
