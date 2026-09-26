/// Who the peer is, and what this device calls them.
///
/// Two names existed in the TypeScript original and they were ranked the wrong
/// way round. `src/App.tsx:119` was
///
/// ```ts
/// const peerName = peerAlias || peerAnnouncedName || defaultPeerName;
/// ```
///
/// so a purely local annotation outranked the name the peer published about
/// itself, and the announced name became invisible the moment a note was added.
/// Worse, `src/components/ChatCallWorkspace.tsx:490` then computed
///
/// ```ts
/// const aliasIsSet = Boolean(peerAnnouncedName && peerAnnouncedName !== peerName);
/// ```
///
/// and gated BOTH the "Kendi seçtiği ad: …" line and the "Takma adı kaldır"
/// button on it. Type the note as the peer's own name and both disappear: the
/// peer can never change their name again from the UI.
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
  /// This asks about the annotation only. The `src/ChatCallWorkspace.tsx:490`
  /// expression asked about the two names being DIFFERENT, which is why an
  /// annotation equal to the announced name silently removed the "remove
  /// annotation" button and the announced-name line.
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
  /// to equal the announced name. That case is the one the TypeScript original
  /// could not render, and it is the case where the peer is MOST likely to
  /// want to change their name.
  bool get showsAnnouncedName => hasAlias && !announcedNameIsUnknown;

  /// Whether the "Takma adı kaldır" affordance must be visible. Same rule, and
  /// for the same reason: it is what un-answers the question "can I stop being
  /// called this locally?".
  bool get canRemoveAlias => hasAlias;

  /// What the annotation editor should open pre-filled with. TS:
  /// `setNameDraft(aliasIsSet ? peerName : "")` at
  /// `src/ChatCallWorkspace.tsx:506`, which opened it with the DISPLAY name, so
  /// clicking "Takma ad" on a peer with an annotation silently re-labelled the
  /// peer as themselves. It is the annotation, or empty when there is none.
  String get aliasDraft => alias;

  /// TS: `peerName.slice(0, 2).toLocaleUpperCase("tr-TR")` at
  /// `src/ChatCallWorkspace.tsx:218`, over the primary name.
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

  /// TS: the `Kendi seçtiği ad: {peerAnnouncedName}` line at
  /// `src/ChatCallWorkspace.tsx:513`.
  String get announcedNameLabel => 'Kendi seçtiği ad: $announcedName';

  /// TS: the `Takma ad` button at `src/ChatCallWorkspace.tsx:506`.
  String get aliasButtonLabel => 'Takma ad';

  /// TS: `aria-label` of the alias reset button, `src/ChatCallWorkspace.tsx:514`.
  String get removeAliasLabel => 'Takma adı kaldır';

  /// TS: the `aria-label` of the inline alias editor,
  /// `src/ChatCallWorkspace.tsx:507`.
  String get aliasFieldLabel => 'Bu cihazdaki kişi takma adı';

  /// TS: the editor's `placeholder`, which falls back to the announced name so
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
/// TS: `toLocaleUpperCase("tr-TR")`. `String.toUpperCase` on this SDK accepts no
/// locale, so the two Turkish-specific mappings are done by hand first:
/// `i` becomes `İ` (U+0130) and `ı` becomes `I`. After that no `i` or `ı`
/// survives into the default pass, so the two cannot disagree, and both are
/// single code points in and out, so the length is unchanged.
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
/// TS: `peerAliasKey`, `readPeerAlias` and `renamePeer` at `src/App.tsx:75-85`
/// and `524-532`.
///
/// The TypeScript [readPeerAlias] fell back to the UNSCOPED `mkvi.peerName` key
/// for any peer that had no scoped entry, and migrated it on read. So a note
/// left for one person was shown for the NEXT person paired to this install,
/// and the scoped key it was copied into belonged to whoever happened to be
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

  /// Moves the unscoped 0.1.x annotation onto [publicKey] and returns it.
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
/// TS read `localStorage.getItem("mkvi.selfName")` raw at module load
/// (`src/App.tsx:35`) and only truncated on write (`src/App.tsx:595` and `608`),
/// so a value written by an older build, or by a hand-edited store, reached
/// `sendProfile` unsanitised. Both ends go through [safeDisplayName] here: an
/// empty result is stored as an empty string, and a read of an empty string is
/// the "no name" state the UI already handles.
final class SelfName {
  const SelfName(this._settings);

  final LocalSettings _settings;

  /// TS: `savedSelfName`, sanitised.
  String read() => sanitizeSelfName(_settings.read(SettingsKeys.selfName));

  /// TS: the `onChange` and `onRenameSelf` handlers, sanitised.
  void write(String raw) =>
      _settings.write(SettingsKeys.selfName, sanitizeSelfName(raw));
}

/// Trims, strips invisibles and caps a self-chosen name.
String sanitizeSelfName(String? raw) => raw == null ? '' : safeDisplayName(raw);
