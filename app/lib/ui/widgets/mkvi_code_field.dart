/// The pairing code field: one real text field, thirteen character cells, and
/// the wire's own rules about what a code may contain.
///
/// ## Why the code is not a plain text field
///
/// `lib/signaling/pairing_code.dart` is the only definition of a pairing code:
/// a 13-character string over `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, with `I`,
/// `O`, `0` and `1` removed at the SOURCE rather than explained in the UI, and
/// `normalizePairingCode` doing the ECMAScript-compatible folding the Worker
/// does. This widget does not re-implement any of it - it calls
/// [normalizePairingCode] from a [TextInputFormatter] and [isAcceptedPairingCode]
/// to decide whether the value is usable, so a code the Worker would reject
/// with a bare `400` can never reach it looking complete on screen.
///
/// The three properties that follow from that, and that the tests measure:
///
/// * a PASTE is accepted as a whole, not character by character - a pasted
///   `abcd-efgh ijkl` becomes `ABCDEFGHJKL` in the formatter and fills every
///   cell, which is what the user actually does after copying a code;
/// * an input of only unusable characters (`1`, `0`, `I`, `O`, punctuation) is
///   REPORTED in Turkish rather than silently becoming an empty field;
/// * a short code is REPORTED, not accepted, and `onSubmitted` does not fire.
///
/// ## Why the text field is invisible
///
/// There is one [TextField] and it is behind the cells at `opacity: 0`. The
/// caret, the selection and the platform IME stay exactly where Flutter puts
/// them - which is the only way paste, selection and the keyboard keep working
/// on every platform - while the cells, drawn here, are what the user sees and
/// what the tokens dress. The cells are [ExcludeSemantics]d, so a screen reader
/// announces the field and its value once instead of reading thirteen isolated
/// letters.
///
/// The alternative - one field per cell - is the shape that produces the
/// half-filled state after a paste: the first field swallows the first character
/// and the rest is lost, silently, in the widget the user is looking at.
library;

import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter, TextRange;
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/signaling/pairing_code.dart';

/// Keys for the parts of the field, so a test asserts on the widget it means.
abstract final class MkviCodeKeys {
  /// The label above the cells.
  static const Key label = Key('mkvi.code.label');

  /// The [TextField] itself - the target of `tester.enterText`.
  static const Key field = Key('mkvi.code.field');

  /// The row of cells, scrollable when the window is narrower than the code.
  static const Key cells = Key('mkvi.code.cells');

  /// The focus ring drawn around the cells.
  static const Key ring = Key('mkvi.code.ring');

  /// The helper line under the cells while there is no error.
  static const Key helper = Key('mkvi.code.helper');

  /// The error line under the cells. Absent while there is no error.
  static const Key error = Key('mkvi.code.error');

  /// The touchable area of cell [index]: never smaller than the hit target.
  static Key cell(int index) => Key('mkvi.code.cell.$index');

  /// The drawn square of cell [index], the size of an `md` control.
  static Key cellBox(int index) => Key('mkvi.code.box.$index');
}

/// Every user-facing string this field can show, in Turkish, in one place.
///
/// A widget with one `String` per decision written at its call site is how an
/// English fragment ends up in a Turkish screen; the same argument
/// `ui/notice/notice_strings.dart` makes, kept in the same shape.
enum MkviCodeTr {
  /// The label of the field. Also its accessible name.
  fieldLabel('Eşleştirme kodu'),

  /// The helper line while nothing has been typed.
  fieldHint('Kodu yazın ya da yapıştırın.'),

  /// The helper line while a code is being typed: `%d` written, `%d` expected.
  progress('%d / %d karakter yazıldı.'),

  /// A code that is not finished yet: `%d` characters still missing.
  tooShort('Kod eksik: %d karakter daha gerekiyor.'),

  /// A code longer than [pairingCodeMaxLength].
  tooLong('Kod çok uzun.'),

  /// Input that contained nothing the alphabet accepts.
  unusableCharacters(
    'Kodda kullanılamayan karakterler var; yalnızca A-Z (I ve O hariç) ve '
    '2-9 rakamları olur.',
  ),

  /// A non-empty code [isAcceptedPairingCode] still refuses.
  rejected('Bu kod geçersiz.');

  const MkviCodeTr(this.tr);

  /// The Turkish text, with `%d` holes.
  final String tr;

  /// [tr] with its `%d` holes filled by [first] and then [second].
  String format(Object? first, [Object? second]) {
    String out = tr;
    for (final Object? value in <Object?>[first, second]) {
      final int hole = out.indexOf('%d');
      if (hole < 0) break;
      out = out.replaceRange(hole, hole + 2, '$value');
    }
    return out;
  }
}

/// The pairing code entry: [length] cells, one caret, the wire's own rules.
///
/// [controller] is optional. When the caller supplies one this widget
/// normalises whatever is written into it - the same [normalizePairingCode]
/// the formatter applies to typing - and never disposes it; when the caller
/// does not, this widget owns one seeded with [initialCode].
///
/// The error line appears when the field is NOT focused, or after a submit that
/// was refused. A user halfway through typing the eighth character is not
/// looking at a red field, and making them see one is how a form starts
/// shouting at people who are still writing.
class MkviCodeField extends StatefulWidget {
  /// Creates a pairing code field.
  const MkviCodeField({
    super.key,
    this.controller,
    this.initialCode = '',
    this.label,
    this.onChanged,
    this.onSubmitted,
    this.onRejected,
    this.length = pairingCodeLength,
    this.autofocus = false,
  });

  /// The text, when the screen owns it. Not disposed here.
  final TextEditingController? controller;

  /// The code the field starts with, when the screen does not own a controller.
  final String initialCode;

  /// The label above the cells. Turkish, from the screen; defaults to
  /// [MkviCodeTr.fieldLabel] when a screen has no better word.
  final String? label;

  /// Called with the normalised code on every change, including a paste.
  final ValueChanged<String>? onChanged;

  /// Called with a code [isAcceptedPairingCode] accepts. Never called for a
  /// code it refuses, which is what makes this a gate and not a notification.
  final ValueChanged<String>? onSubmitted;

  /// Called with a code that was refused on submit, so the screen can say why
  /// it is not proceeding.
  final ValueChanged<String>? onRejected;

  /// How many cells to draw. Defaults to [pairingCodeLength], the length
  /// [createPairingCode] produces.
  final int length;

  /// Whether the field takes the keyboard on first build.
  final bool autofocus;

  @override
  State<MkviCodeField> createState() => _MkviCodeFieldState();
}

class _MkviCodeFieldState extends State<MkviCodeField> {
  /// Holds the last input the formatter had to reduce to nothing, because a
  /// field that has silently swallowed `1` and `0` is the defect this widget
  /// exists to remove.
  final _PairingCodeFormatter _formatter = _PairingCodeFormatter();

  TextEditingController? _ownController;
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _submitted = false;

  /// Set when a value a SCREEN wrote into the controller contained nothing the
  /// alphabet accepts. Sticky for the same reason [_PairingCodeFormatter
  /// .reducedToNothing] is: an empty value cannot say whether it was emptied by
  /// the user or emptied by the alphabet.
  bool _rejected = false;

  /// Whether the current text cannot be used yet, and the reason is that
  /// something the alphabet accepts not at all was typed.
  bool get _unusableInput => _rejected || _formatter.reducedToNothing;

  TextEditingController get _text =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownController = TextEditingController(
        text: normalizePairingCode(widget.initialCode),
      );
    }
    _controller = _text;
    // A screen may hand this field a code that is not in the code's own form
    // yet - a deep link, a stored value, a code read from the clipboard by the
    // screen itself. It is normalised BEFORE the listener is attached and
    // before the first build, so the cells cannot show a character the
    // alphabet drops and no setState is needed here.
    final String raw = _controller.text;
    final String code = normalizePairingCode(raw);
    if (code != raw) {
      _controller.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
    }
    _controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    _ownController?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focus.hasFocus);
  }

  /// Keeps the field's text in the code's own form, whatever wrote it.
  ///
  /// Typing already goes through [TextInputFormatter]; this is the same
  /// function applied to a value a screen or a deep link put into the
  /// controller, so the cells can never show a character the alphabet drops.
  void _onTextChanged() {
    final String raw = _controller.text;
    final String code = normalizePairingCode(raw);
    if (raw.trim().isNotEmpty) {
      _rejected = code.isEmpty;
    }
    if (code != raw) {
      if (mounted) setState(() {});
      _controller.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
      return;
    }
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call(code);
  }

  /// The Turkish reason the current code cannot be used, or null.
  String? _problem(String code) {
    if (code.isEmpty) {
      return _unusableInput ? MkviCodeTr.unusableCharacters.tr : null;
    }
    if (isAcceptedPairingCode(code)) return null;
    if (code.length < pairingCodeLength) {
      return MkviCodeTr.tooShort.format(pairingCodeLength - code.length);
    }
    if (code.length > pairingCodeMaxLength) return MkviCodeTr.tooLong.tr;
    return MkviCodeTr.rejected.tr;
  }

  /// Whether the error line is showing: there is a problem, and the user is
  /// either not in the field any more or has already tried to submit.
  bool _showsError(String code) =>
      _problem(code) != null && (!_focused || _submitted);

  void _onSubmitted(String value) {
    final String code = normalizePairingCode(value);
    final String? problem = _problem(code);
    setState(() => _submitted = true);
    if (problem == null) {
      widget.onSubmitted?.call(code);
      return;
    }
    widget.onRejected?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final ResolvedControl md = style.control('md');
    final String code = normalizePairingCode(_controller.text);
    final String? problem = _problem(code);
    final bool error = _showsError(code);
    final String helper = code.isEmpty
        ? MkviCodeTr.fieldHint.tr
        : MkviCodeTr.progress.format(code.length, widget.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          validationResult: error
              ? SemanticsValidationResult.invalid
              : SemanticsValidationResult.none,
          child: Text(
            widget.label ?? MkviCodeTr.fieldLabel.tr,
            key: MkviCodeKeys.label,
            style: style.styleOf('sm').copyWith(color: style.role('textMuted')),
          ),
        ),
        SizedBox(height: style.gap('3')),
        Container(
          key: MkviCodeKeys.ring,
          // The ring is drawn OUTSIDE the cells by the token file's own gap and
          // width, and the padding is there in both states so focusing the field
          // does not move the cells by a pixel.
          padding: EdgeInsets.all(style.focusRingGap + style.focusRingWidth),
          decoration: _focused
              ? BoxDecoration(
                  border: Border.all(
                    color: style.role('focusRing'),
                    width: style.focusRingWidth,
                  ),
                  borderRadius: style.shape('md').borderRadius,
                )
              : null,
          child: Stack(
            children: <Widget>[
              ExcludeSemantics(
                // Horizontal scrolling is what makes a narrow window a smaller
                // code field's problem rather than an overflow: a window
                // narrower than the row scrolls instead of clipping a cell the
                // user cannot hit.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    key: MkviCodeKeys.cells,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (int index = 0; index < widget.length; index += 1)
                        Padding(
                          padding: EdgeInsets.only(
                            right: index == widget.length - 1
                                ? 0.0
                                : style.gap('2'),
                          ),
                          child: _cell(style, md, code, index),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(child: _input(style, md)),
            ],
          ),
        ),
        SizedBox(height: style.gap('2')),
        if (error)
          Text(
            problem!,
            key: MkviCodeKeys.error,
            style: style.styleOf('sm').copyWith(color: style.role('danger')),
          )
        else
          Text(
            helper,
            key: MkviCodeKeys.helper,
            style: style.styleOf('sm').copyWith(color: style.role('textMuted')),
          ),
      ],
    );
  }

  /// The cell: a touchable area at least [AppearanceStyle.hitTargetMin] on a
  /// side, with the drawn box of an `md` control centred in it.
  ///
  /// The two are separate because the control height (34 dp at density 1) is
  /// NOT the hit target, and conflating them is how the close button in 0.1.x
  /// ended up at 34 px: a control height used as a target.
  Widget _cell(
    AppearanceStyle style,
    ResolvedControl md,
    String code,
    int index,
  ) {
    final double target = md.height < style.hitTargetMin
        ? style.hitTargetMin
        : md.height;
    final bool filled = code.length > index;
    // "Auto-advance": the caret is always in the first cell the code has not
    // reached, so the cell the user is typing into is the lit one.
    final bool active =
        _focused && index == (code.length < widget.length ? code.length : widget.length - 1);
    final Color border = active
        ? style.role('accent')
        : filled
        ? style.role('borderStrong')
        : style.role('border');

    return SizedBox(
      key: MkviCodeKeys.cell(index),
      width: target,
      height: target,
      child: Center(
        child: Container(
          key: MkviCodeKeys.cellBox(index),
          width: md.height,
          height: md.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? style.role('accentSoft') : style.role('surfaceSoft'),
            border: Border.all(color: border, width: style.borderWidth),
            borderRadius: style.shape('sm').borderRadius,
          ),
          // The cell is a fixed-format display: a character is drawn as large as
          // the scale asks and shrunk only if it would not fit, so a code field
          // cannot overflow at 1.25 type.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              filled ? code[index] : '',
              style: style.styleOf('lg').copyWith(color: style.role('text')),
            ),
          ),
        ),
      ),
    );
  }

  /// The real input, invisible, behind the cells.
  Widget _input(AppearanceStyle style, ResolvedControl md) {
    return Semantics(
      // The field carries its OWN name, and that is a deliberate choice rather
      // than a fallback.
      //
      // Two measured facts put it here. First, Flutter drops everything under a
      // fully transparent `Opacity` from the semantics tree unless
      // `alwaysIncludeSemantics` is set — a screen reader does not read what
      // was never painted — so the field, the control this whole screen exists
      // for, was **absent** rather than merely unlabelled. Second, the name on
      // the thirteen cells is on a SIBLING subtree, not an ancestor of the
      // field, so a reader that only looks upward from the field reads nothing
      // and calls it unlabelled.
      //
      // The wording is a label, not a sentence: a screen reader announces the
      // role ("text field") separately, so "eşleşme kodu" plus "metin alanı"
      // is one coherent announcement rather than two competing ones.
      //
      // `widget.label` is the screen's own word for the thing; the fallback is
      // what this field is called when nobody has a better name, which is also
      // what `test/ui/widgets` measures.
      label: widget.label ?? MkviCodeTr.fieldLabel.tr,
      textField: true,
      child: Opacity(
        // `alwaysIncludeSemantics: true` is load-bearing, and was measured. See
        // the comment above: without it this subtree is not in the tree at all,
        // so the `Semantics` above would describe a node that does not exist.
        //
        // Not `0` because of a token: a hidden text field is a layout, not a
        // painted thing, and there is no token for "how visible the caret is
        // when the caret is not the design".
        opacity: 0,
        alwaysIncludeSemantics: true,
      child: TextField(
        key: MkviCodeKeys.field,
        controller: _controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        style: style.styleOf('md').copyWith(
          fontSize: md.fontSize,
          color: style.role('text'),
        ),
        cursorColor: style.role('accent'),
        // A code is copied from a chat window, so autocorrect and suggestions
        // would only ever change it.
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        inputFormatters: <TextInputFormatter>[_formatter],
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: _onSubmitted,
      ),
      ),
    );
  }
}

/// Normalises a typed or pasted code to [pairingCodeAlphabet] and caps it at
/// [pairingCodeMaxLength], through the wire's own function.
///
/// The selection is collapsed at the end of the result: a code is written left
/// to right, so a caret the user cannot see must not stay behind a character
/// that the alphabet deleted.
class _PairingCodeFormatter extends TextInputFormatter {
  /// Whether the last edit the field was asked to make contained text the
  /// alphabet accepts not at all. Sticky: the field reads it while it BUILDS,
  /// and an edit that leaves the value unchanged - which is exactly what an
  /// input of only `1`, `0`, `I` and `O` produces - notifies no listener, so a
  /// one-shot flag would be read once and lost.
  ///
  /// It is cleared by the next edit that does produce characters, and NOT by an
  /// empty one, because a deletion cannot say whether it undoes a rejected
  /// input or an accepted one.
  bool reducedToNothing = false;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final String code = normalizePairingCode(newValue.text);
    reducedToNothing = code.isEmpty;
    return newValue.copyWith(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
      composing: TextRange.empty,
    );
  }
}
