/// The name this device publishes about itself.
///
/// One sanitising read and one sanitising write, both through
/// `safeDisplayName` - the same function the wire uses, already ported to
/// `package:mkvi/core/protocol/text_sanitizer.dart`. Nothing here re-implements
/// the character rules, because a name that is safe in the UI but not on the
/// wire is the bug this closes.
///
/// Both ends matter, and the old build only had one of them:
///
/// * on WRITE, so a control character, a bidi override or a 300-character
///   string never reaches the store;
/// * on READ, because a value written by an older build - or by a hand-edited
///   store - was read raw and announced unsanitised.
///
/// The read is idempotent: sanitising an already-sanitised name returns it
/// unchanged, so a value can be read as often as the UI likes.
library;

import 'package:mkvi/core/protocol/text_sanitizer.dart';

import 'settings_store.dart';

/// The self-name field: read it, write it, both sanitised.
final class SelfNameField {
  const SelfNameField(this._store);

  final SettingsStore _store;

  /// The stored name, sanitised, or '' when none is set.
  String read() => sanitisedSelfName(_store.read(selfNameKey));

  /// Stores [raw], sanitised.
  ///
  /// A name that sanitises away to nothing is stored as an empty string, so
  /// "no name" has exactly one representation and the read never has to guess
  /// whether '' means unset or set-to-blank.
  void write(String raw) => _store.write(selfNameKey, sanitisedSelfName(raw));

  /// Forgets the name.
  void clear() => _store.remove(selfNameKey);
}

/// Trims, strips invisibles and caps a self-chosen name.
///
/// The wire's own function, named for this layer. (`session/names.dart` has an
/// identically-behaving `sanitizeSelfName` over the older `LocalSettings`
/// store; two names, one implementation, so neither store can be the one that
/// forgot to sanitise.)
String sanitisedSelfName(String? raw) =>
    raw == null ? '' : safeDisplayName(raw);
