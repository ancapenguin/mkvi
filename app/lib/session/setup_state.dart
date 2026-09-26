/// The app's top-level state, as a closed set of values.
///
/// The white pairing screen was not a rendering bug, it was a *type* bug. When
/// the UI decided what to render from a single nullable "known peer" value, the
/// pairing screen was the fallback branch — reached by a first run, by a corrupt
/// store, and by a transient read failure alike. Two of those three showed the
/// first-run screen, so someone closing and reopening the app after a failed read
/// landed on a blank pairing screen with no way back.
///
/// The fix is not a branch, it is a type. [SetupState] has one case per thing
/// that can actually be true, and exactly one method -
/// [SetupState.showsPairingScreen] - decides whether the pairing UI may be
/// built. That method returns true for [SetupFirstRun] and [SetupNeedsPairing]
/// and for nothing else, so a failed read has no value it can reach.
library;

import 'peer_store.dart';

/// Where the app is during startup and after the channel drops.
sealed class SetupState {
  const SetupState();

  /// The one true first run. No pairing has ever completed on this device.
  const factory SetupState.firstRun() = SetupFirstRun;

  /// The stored peer is being read. Never a rendered surface, only a spinner.
  const factory SetupState.restoring() = SetupRestoring;

  /// A peer exists and the data channel is not up yet.
  const factory SetupState.reconnecting() = SetupReconnecting;

  /// The data channel is open.
  const factory SetupState.connected() = SetupConnected;

  /// The user explicitly asked to pair a new device. The ONLY way here is an
  /// explicit call on the controller; nothing derives it.
  const factory SetupState.needsPairing() = SetupNeedsPairing;

  /// A peer WAS paired and cannot be read. Not the pairing screen, ever.
  const factory SetupState.broken(PeerReadFailure failure) = SetupBroken;

  /// Whether the pairing screen may be shown.
  ///
  /// This single method is the regression guard for the white pairing screen
  /// and the only thing in the app that may answer that question. A UI that
  /// asks `state.showsPairingScreen` cannot show pairing after a failed read,
  /// after a corrupt record, or after a dropped channel, because none of those
  /// states returns true here.
  bool get showsPairingScreen;

  /// A Turkish headline. Every state has one, so no screen has to invent its
  /// own wording and no state can be rendered as a blank page.
  String get title;

  /// A Turkish sentence explaining the state and, where there is one, what to
  /// do about it.
  String get detail;

  /// Whether the chat and call surface may be shown. The saved pair owns the
  /// main screen even while it is offline — going "offline" must not take the
  /// user's conversation away.
  bool get showsWorkspace;

  /// Whether the UI must offer a plain "try the read again" action.
  bool get canRetry;

  /// Whether the UI may offer "pair a new device".
  ///
  /// This is an ACTION, not a state: acting on it is what produces
  /// [SetupNeedsPairing]. It is true here for exactly the states where the
  /// user is looking at a peer they already have - including
  /// [SetupBroken], where pairing again is the documented last resort and is
  /// reachable only because the user pressed the button.
  bool get offersPairNewDevice;
}

/// The one state that exists only while the store is being read. It is a value
/// rather than a rendering branch, so it cannot leak into a pairing render.
final class SetupRestoring extends SetupState {
  const SetupRestoring();

  @override
  bool get showsPairingScreen => false;

  @override
  String get title => 'MKVI hazırlanıyor';

  @override
  String get detail => 'Kayıtlı görüşme güvenli biçimde açılıyor…';

  @override
  bool get showsWorkspace => false;

  @override
  bool get canRetry => false;

  @override
  bool get offersPairNewDevice => false;
}

/// No pairing has ever completed here. The first-run pairing screen.
final class SetupFirstRun extends SetupState {
  const SetupFirstRun();

  @override
  bool get showsPairingScreen => true;

  @override
  String get title => 'İlk bağlantını kur';

  @override
  String get detail => 'Hesap açmadan, tek kullanımlık kodla eşleş.';

  @override
  bool get showsWorkspace => false;

  @override
  bool get canRetry => false;

  /// Already on the pairing screen; there is nothing to offer.
  @override
  bool get offersPairNewDevice => false;
}

/// The user pressed "pair a new device". The pairing screen is allowed here,
/// and only because of that press.
final class SetupNeedsPairing extends SetupState {
  const SetupNeedsPairing();

  @override
  bool get showsPairingScreen => true;

  @override
  String get title => 'Yeni bir cihaz bağla';

  @override
  String get detail =>
      'Bu cihazdaki mevcut eş kaydı yeni eşleşmeyle değiştirilecek.';

  @override
  bool get showsWorkspace => false;

  @override
  bool get canRetry => false;

  /// Already on the pairing screen; the affordance here is "go back".
  @override
  bool get offersPairNewDevice => false;
}

/// A peer is stored and the channel is not up. This is a normal state, not an
/// error: a saved pair owns the main screen even while offline.
final class SetupReconnecting extends SetupState {
  const SetupReconnecting();

  @override
  bool get showsPairingScreen => false;

  @override
  String get title => 'Yeniden bağlanılıyor';

  @override
  String get detail => 'Kayıtlı eş bulundu. Bağlantı kurulana kadar bekle.';

  @override
  bool get showsWorkspace => true;

  @override
  bool get canRetry => false;

  @override
  bool get offersPairNewDevice => true;
}

/// The data channel is open.
final class SetupConnected extends SetupState {
  const SetupConnected();

  @override
  bool get showsPairingScreen => false;

  @override
  String get title => 'Bağlı';

  @override
  String get detail => 'Eşleştiğin cihaza bağlandın.';

  @override
  bool get showsWorkspace => true;

  @override
  bool get canRetry => false;

  @override
  bool get offersPairNewDevice => true;
}

/// A peer WAS paired and cannot be read.
///
/// This state exists so the user is told what happened instead of being shown a
/// first-run screen for a device that has been paired for months. It is
/// reachable only from a [PeerUnreadable] read result or from a store that
/// threw, and [showsPairingScreen] is false here by construction.
final class SetupBroken extends SetupState {
  const SetupBroken(this.failure);

  final PeerReadFailure failure;

  /// What the user can do, on its own. The UI's primary action for this state.
  String get recovery => failure.recovery;

  @override
  bool get showsPairingScreen => false;

  @override
  String get title => 'Kayıtlı eş açılamadı';

  @override
  String get detail => '${failure.message} ${failure.recovery}';

  @override
  bool get showsWorkspace => false;

  /// A read that failed can very well succeed the second time, so retry is the
  /// primary action here.
  @override
  bool get canRetry => true;

  /// The documented last resort, and only after retry has failed. Acting on it
  /// is an explicit user press, which is what makes reaching the pairing screen
  /// from here a decision rather than an accident.
  @override
  bool get offersPairNewDevice => true;

  @override
  bool operator ==(Object other) =>
      other is SetupBroken && other.failure.runtimeType == failure.runtimeType;

  @override
  int get hashCode => Object.hash(SetupBroken, failure.runtimeType);
}
