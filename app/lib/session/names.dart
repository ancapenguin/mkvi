/// Who the peer is, and what this device calls them.
///
/// ## Why these are two slots and not one name with a precedence operator
///
/// A single `alias || announced || placeholder` expression is the obvious way to
/// write this, and it ranks the two names backwards: a purely local annotation
/// outranks the name the peer published about itself, so the announced name
/// becomes invisible the moment a note is added.
///
/// The worse half is what usually got built on top of that expression — an
/// "is an alias set?" test written as "are the two names *different*?" — and
/// then used to gate BOTH the "Kendi seçtiği ad: …" line and the
/// "Takma adı kaldır" button. Type the note as the peer's own name and both
/// disappear: the peer can never change their name again from the UI, and the
/// user has no way to get the button back.
///
/// [PeerNameView] is therefore not a pair of strings with a precedence
/// operator. The announced name and the annotation are two separate slots, and
/// the UI's question - "is an annotation set?" - is answered by
/// [PeerNameView.hasAlias], which asks about the ANNOTATION and never about how
/// the two compare.
library;

import 'package:mkvi/core/protocol/text_sanitizer.dart';

import 'local_settings.dart';
import 'peer_store.dart';

/// Everything the UI shows about the peer, already resolved.
///
/// Immutable and complete: the UI is handed one of these and never recomputes a
/// name, a placeholder or an "is an alias set" boolean of its own. That is what
/// makes the `aliasIsSet` trap unrepresentable rather than merely avoided.
final class PeerNameView {
  const PeerNameView({required this.announcedName, this.alias = ''});

  /// The name the peer announced for itself over the data channel, or the one
  /// restored from the encrypted store. Empty when it is genuinely unknown.
  final String announcedName;

  /// This device's note about the peer. Local, never transmitted, never
  /// persisted into the peer's record.
  final String alias;

  /// Whether an annotation is set.
  ///
  /// This asks about the annotation only. Asking instead whether the two names
  /// are *different* is what made an annotation equal to the announced name
  /// silently remove the "remove annotation" button and the announced-name line.
  bool get hasAlias => alias.isNotEmpty;

  /// The primary display slot: the announced name, or the placeholder.
  ///
  /// The annotation is deliberately NOT in this expression. The announcement is
  /// the peer's identity and it is what the user must be able to read at a
  /// glance; the annotation is a second line.
  String get displayName =>
      announcedName.isEmpty ? KnownPeer.defaultAnnouncedName : announcedName;

  /// Whether the announced name is unknown and the placeholder is standing in
  /// for it. There is then nothing to show a second time, so the UI shows one
  /// name and no annotation line.
  bool get announcedNameIsUnknown => announcedName.isEmpty;

  /// Whether the "Kendi seçtiği ad: …" line must be visible.
  ///
  /// True whenever an annotation exists, including when the annotation happens
  /// to equal the announced name. That case is the one a "are they different?"
  /// test cannot render, and it is the case where the peer is MOST likely to
  /// want to change their name.
  bool get showsAnnouncedName => hasAlias && !announcedNameIsUnknown;

  /// Whether the "Takma adı kaldır" affordance must be visible. Same rule, and
  /// for the same reason: it is what un-answers the question "can I stop being
  /// called this locally?".
  bool get canRemoveAlias => hasAlias;

  /// What the annotation editor should open pre-filled with.
  ///
  /// The *annotation*, or empty when there is none. Pre-filling it with the
  /// display name instead would make clicking "Takma ad" on a peer who already
  /// has an annotation silently re-label them as themselves.
  String get aliasDraft => alias;

  /// The avatar initials, from the primary name.
  ///
  /// `String.toUpperCase` takes no locale on this SDK, so the Turkish casing is
  /// applied by [turkishUpperCase] before the default pass. The locale is not
  /// cosmetic: `i` uppercases to `İ` and `ı` to `I` in Turkish, and the
  /// default pass turns `i` into a plain `I`.
  String get avatarInitials {
    final String source = displayName;
    if (source.isEmpty) return '';
    return turkishUpperCase(
      source.runes.take(2).map((int rune) => String.fromCharCode(rune)).join(),
    );
  }

  /// The "Kendi seçtiği ad: …" line.
  String get announcedNameLabel => 'Kendi seçtiği ad: $announcedName';

  /// The "Takma ad" button.
  String get aliasButtonLabel => 'Takma ad';

  /// `aria-label` of the alias reset button.
  String get removeAliasLabel => 'Takma adı kaldır';

  /// `aria-label` of the inline alias editor.
  String get aliasFieldLabel => 'Bu cihazdaki kişi takma adı';

  /// The editor's `placeholder`, which falls back to the announced name so
  /// the user can see what the peer actually calls themselves.
  String get aliasFieldPlaceholder =>
      announcedName.isEmpty ? displayName : announcedName;

  PeerNameView withAlias(String next) => PeerNameView(
    announcedName: announcedName,
    alias: next == alias ? alias : sanitizeAlias(next),
  );

  @override
  bool operator ==(Object other) =>
      other is PeerNameView &&
      other.announcedName == announcedName &&
      other.alias == alias;

  @override
  int get hashCode => Object.hash(announcedName, alias);

  @override
  String toString() => 'PeerNameView($announcedName, alias: $alias)';
}

/// Trims, strips invisibles and caps an annotation at the display-name limit.
///
/// The same [safeDisplayName] the wire uses, so an annotation can never be the
/// one place a control character or an over-long string survives.
String sanitizeAlias(String raw) => safeDisplayName(raw);

/// Upper-cases with Turkish casing rules, then with the default Unicode table.
///
/// `String.toUpperCase` on this SDK accepts no locale, so the two
/// Turkish-specific mappings are done by hand first: `i` becomes `İ` (U+0130) and
/// `ı` becomes `I`. After that no `i` or `ı` survives into the default pass, so
/// the two cannot disagree, and both are single code points in and out, so the
/// length is unchanged.
String turkishUpperCase(String value) {
  final StringBuffer out = StringBuffer();
  for (final int rune in value.runes) {
    if (rune == 0x69) {
      out.write('İ');
    } else if (rune == 0x131) {
      out.write('I');
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString().toUpperCase();
}

/// The peer's local annotation, keyed by the peer's public key.
///
/// ## Why there is no fallback key
///
/// An earlier build read an annotation from the UNSCOPED `mkvi.peerName` key for
/// any peer that had no scoped entry, and migrated it on read. A note left for
/// one person was therefore shown for the NEXT person paired to this install,
/// and the scoped key it got copied into belonged to whoever happened to be
/// restored first. This port has no such fallback: [read] is a pure function of
/// one key, and the one-time migration is [migrateLegacyAlias], which the
/// bootstrap calls for the peer it actually restored and nowhere else.
final class PeerAliasStore {
  const PeerAliasStore(this._settings);

  final LocalSettings _settings;

  /// The annotation stored for exactly [publicKey], or '' for any other key.
  String read(String publicKey) =>
      sanitizeAlias(_settings.read(peerAliasKey(publicKey)) ?? '');

  /// Stores [raw] for [publicKey]. An empty or all-invisible annotation removes
  /// the entry rather than writing an empty string, so "no annotation" has one
  /// representation.
  void write(String publicKey, String raw) {
    final String clean = sanitizeAlias(raw);
    if (clean.isEmpty) {
      remove(publicKey);
      return;
    }
    _settings.write(peerAliasKey(publicKey), clean);
  }

  void remove(String publicKey) => _settings.remove(peerAliasKey(publicKey));

  /// Moves the unscoped legacy annotation onto [publicKey] and returns it.
  ///
  /// Returns '' and writes nothing when there is no legacy value, or when this
  /// public key already has an entry. The caller decides which peer it is; this
  /// function has no opinion, which is what stops one person's note from
  /// reaching the next.
  String migrateLegacyAlias(String publicKey) {
    final String? scoped = _settings.read(peerAliasKey(publicKey));
    if (scoped != null) return sanitizeAlias(scoped);
    final String? legacy = _settings.read(SettingsKeys.legacyPeerAlias);
    if (legacy == null) return '';
    _settings.remove(SettingsKeys.legacyPeerAlias);
    final String clean = sanitizeAlias(legacy);
    if (clean.isEmpty) return '';
    _settings.write(peerAliasKey(publicKey), clean);
    return clean;
  }
}

/// This device's own announced name, sanitised on read AND on write.
///
/// Sanitising only on write is not enough: a value written by an older build, or
/// by a hand-edited store, would reach the profile frame unsanitised and be
/// rejected by the peer's parser — a message the user never typed and cannot
/// see. Both ends therefore go through [safeDisplayName]: an empty result is
/// stored as an empty string, and a read of an empty string is the "no name"
/// state the UI already handles.
final class SelfName {
  const SelfName(this._settings);

  final LocalSettings _settings;

  /// The stored name, sanitised.
  String read() => sanitizeSelfName(_settings.read(SettingsKeys.selfName));

  /// Sanitises before storing, so nothing invalid is ever written.
  void write(String raw) =>
      _settings.write(SettingsKeys.selfName, sanitizeSelfName(raw));
}

/// Trims, strips invisibles and caps a self-chosen name.
String sanitizeSelfName(String? raw) => raw == null ? '' : safeDisplayName(raw);
