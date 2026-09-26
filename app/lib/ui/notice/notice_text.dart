/// Text shaping for a notice body, and nothing else.
///
/// The reported bug had five parts; this file is the fix for the fifth. There was
/// no height cap, and the longest thing the old toast ever showed was a saved
/// file's full Windows path — ``setNotice(`${event.file.name} kaydedildi: ${event.file.path}`)``
/// at `src/App.tsx:376` — so a long notice grew down over the message list, and
/// because the toast was `position: fixed; bottom: 18px` it grew *into* the
/// composer while it did it.
///
/// A cap is only half of it. A 300-character path has no spaces, so a `Text`
/// that merely wraps would still run off the edge, which is why the old CSS
/// needed `overflow-wrap: anywhere` (`.mkvi-toast span`, `src/App.css:189`).
/// Dart has no such switch, so the break opportunities are inserted explicitly:
/// a zero-width space after every character a path or a sentence breaks on. It
/// is invisible, it changes no visible character, and the accessibility label
/// stays the untouched original because the message group is announced by
/// `NoticeMessage` and the `Text` inside it is excluded from semantics.
library;

/// The code unit inserted to create a break opportunity.
///
/// U+200B, ZERO WIDTH SPACE: a real UAX #14 break opportunity that occupies no
/// width. It is a code unit and not a string literal on purpose — a literal
/// zero-width character in source is invisible, and a file of invisible
/// characters cannot be reviewed or diffed.
const int noticeZeroWidthSpace = 0x200B;

/// [noticeZeroWidthSpace] as the one-character string a `String` API needs.
String get noticeZeroWidthSpaceChar =>
    String.fromCharCode(noticeZeroWidthSpace);

/// The characters a notice body may break after: both path separators, the
/// punctuation that ends a Turkish word, and the brackets that open a suffix.
const String noticeBreakAfter = r' \/.:;!?-_,()[]{}';

/// [text] with a zero-width break opportunity after every breakable character.
///
/// Idempotent for text with no breakable character, and never inserts a trailing
/// break opportunity, so a notice that happens to end in `/` does not grow a
/// phantom line.
String noticeSoftBreaks(String text) {
  if (text.isEmpty) return text;
  final List<int> runes = text.runes.toList(growable: false);
  final StringBuffer out = StringBuffer();
  for (int index = 0; index < runes.length; index += 1) {
    final int rune = runes[index];
    out.writeCharCode(rune);
    final bool isLast = index == runes.length - 1;
    if (!isLast && noticeBreakAfter.contains(String.fromCharCode(rune))) {
      out.writeCharCode(noticeZeroWidthSpace);
    }
  }
  return out.toString();
}

/// [text] with every break opportunity removed, i.e. what a person reads.
///
/// The test oracle for [noticeSoftBreaks]: the shaping must be invisible.
String noticeVisibleText(String text) =>
    text.replaceAll(noticeZeroWidthSpaceChar, '');
