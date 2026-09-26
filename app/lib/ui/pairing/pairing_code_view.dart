/// The block that shows the code **this** device minted, one character per box,
/// and hands it to the clipboard.
///
/// ## What is generated and what is drawn
///
/// The code is `createPairingCode()`'s — 13 characters over
/// `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` from `lib/signaling/pairing_code.dart` —
/// and this file re-implements none of that. It draws the string the wire's own
/// function produced, in cells of the shape `MkviCodeField`'s *filled* cells have
/// (`accentSoft` fill, `borderStrong` edge, an `md` control square), because
/// those two blocks are read together: one device shows a code, the other types
/// it, and a user comparing the two screens should not have to notice that they
/// are drawn by different files.
///
/// The cells are laid out in a horizontal scroll view for the same reason
/// `MkviCodeField` scrolls its cells: 13 hit-target-wide boxes are 466 dp at the
/// cozy density, and `mkviWindowSizes` includes a 400 dp window. Scrolling is a
/// narrower code field's problem; clipping a cell the user has to read is not.
///
/// ## The characters are not thirteen controls
///
/// They are `ExcludeSemantics`d and the block above them carries one label with
/// the whole code, so a screen reader says "Bu cihazın eşleştirme kodu. ABC…"
/// once instead of reading thirteen isolated letters. They are also not hit
/// targets: nothing about a character is operable, and `expectHitTarget` on them
/// would be measuring a promise this block does not make.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/signaling/pairing_code.dart';

import 'pairing_action.dart';
import 'pairing_strings.dart';

/// The keys the parts of the code block answer to.
abstract final class PairingCodeKeys {
  /// The whole block, so a test can measure it as one box.
  static const Key block = Key('mkvi.pairing.code.block');

  /// The label above the cells.
  static const Key label = Key('mkvi.pairing.code.label');

  /// The scrollable row of cells.
  static const Key characters = Key('mkvi.pairing.code.characters');

  /// The "send this to the other side" sentence.
  static const Key sendNote = Key('mkvi.pairing.code.send');

  /// The one-time-use sentence.
  static const Key lifetimeNote = Key('mkvi.pairing.code.lifetime');

  /// The copy control.
  static const Key copy = Key('mkvi.pairing.code.copy');

  /// Mints a different code.
  static const Key regenerate = Key('mkvi.pairing.code.regenerate');

  /// The line that reports what the copy did. Absent until it has been tried.
  static const Key status = Key('mkvi.pairing.code.status');

  /// The one announcement the whole code gets.
  static const Key announcement = Key('mkvi.pairing.code.announcement');

  /// The cell holding character [index].
  static Key character(int index) => Key('mkvi.pairing.code.char.$index');

  /// The drawn box of character [index], the size of an `md` control.
  static Key characterBox(int index) => Key('mkvi.pairing.code.box.$index');
}

/// Writes [code] to the system clipboard, and says whether it worked.
///
/// The seam rather than a direct `Clipboard.setData` call, for the reason
/// `lib/ui/notice` makes its clock a parameter: a test that cannot see the copy
/// proves only that a button was pressed. This is also the **default**, so the
/// production path is the real `Clipboard` and a test that wants the real thing
/// can mock the platform channel and get the same answer.
typedef PairingClipboard = Future<bool> Function(String code);

/// The production clipboard: `SystemChannels.platform`'s `Clipboard.setData`.
///
/// Returns `false` rather than throwing. A clipboard the platform refuses is a
/// recoverable situation — the code is on screen in thirteen boxes — and a copy
/// button that takes the whole screen down with it would be worse than useless.
Future<bool> copyPairingCodeToClipboard(String code) async {
  try {
    await Clipboard.setData(ClipboardData(text: code));
    return true;
  } on Object {
    return false;
  }
}

/// The generated code, split into boxes, with a copy control and a way to mint a
/// new one.
///
/// [initialCode] seeds the first code. It exists so a test can assert on a code it
/// can name; production passes nothing and gets [createPairingCode]. A seeded
/// code is still replaceable by the regenerate control, because a code that has
/// been read off the screen has to be replaceable — that is the whole reason the
/// control is there.
class PairingCodeView extends StatefulWidget {
  /// Creates the code block.
  const PairingCodeView({
    super.key,
    this.initialCode,
    this.copyToClipboard = copyPairingCodeToClipboard,
  });

  /// The code to start with, or `null` to mint one with
  /// `createPairingCode()`.
  final String? initialCode;

  /// Where the code goes when the copy control is pressed.
  final PairingClipboard copyToClipboard;

  @override
  State<PairingCodeView> createState() => _PairingCodeViewState();
}

class _PairingCodeViewState extends State<PairingCodeView> {
  /// The code on screen. Replaced wholesale by the regenerate control, because
  /// a 13-character code is one value and thirteen independent cells would be
  /// thirteen things that could disagree with it.
  late String _code;

  /// The sentence the last copy produced, or `null` before the first try.
  ///
  /// Deliberately not cleared by time: `lib/ui/notice` owns the transient
  /// channel, and a timer here would be a second one. The line is replaced by
  /// the next attempt, which is the only thing that can honestly change it.
  String? _status;

  /// Whether the last copy worked, for the status line's colour.
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _code = widget.initialCode ?? createPairingCode();
  }

  Future<void> _copy() async {
    final bool ok = await widget.copyToClipboard(_code);
    if (!mounted) return;
    setState(() {
      _statusOk = ok;
      _status = ok ? PairingTr.copiedNote.tr : PairingTr.copyFailedNote.tr;
    });
  }

  void _regenerate() {
    setState(() {
      _code = createPairingCode();
      // A new code invalidates the last copy's report: leaving "Kod panoya
      // kopyalandı" under a code that was never copied is a sentence about the
      // wrong code.
      _status = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Column(
      key: PairingCodeKeys.block,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          key: PairingCodeKeys.announcement,
          readOnly: true,
          // One announcement for the whole code, rather than thirteen.
          label: '${PairingTr.codeDisplayLabel.tr}. $_code',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  PairingTr.codeDisplayLabel.tr,
                  key: PairingCodeKeys.label,
                  style: style.styleOf('sm').copyWith(
                    color: style.role('textMuted'),
                  ),
                ),
                SizedBox(height: style.gap('3')),
                Container(
                  key: PairingCodeKeys.characters,
                  padding: EdgeInsets.all(style.gap('2')),
                  decoration: BoxDecoration(
                    color: style.role('surfaceSoft'),
                    borderRadius: style.shape('md').borderRadius,
                    border: Border.all(
                      color: style.role('border'),
                      width: style.borderWidth,
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (int index = 0; index < _code.length; index += 1)
                          Padding(
                            padding: EdgeInsets.only(
                              right: index == _code.length - 1
                                  ? 0.0
                                  : style.gap('2'),
                            ),
                            child: _cell(style, index),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: style.gap('2')),
                Text(
                  PairingTr.codeLengthCaption.format(_code.length),
                  style: style
                      .styleOf('2xs')
                      .copyWith(color: style.role('textMuted')),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: style.gap('3')),
        Text(
          PairingTr.sendCodeNote.tr,
          key: PairingCodeKeys.sendNote,
          style: style.styleOf('md').copyWith(color: style.role('text')),
        ),
        SizedBox(height: style.gap('2')),
        Text(
          PairingTr.codeLifetimeNote.tr,
          key: PairingCodeKeys.lifetimeNote,
          style: style.styleOf('sm').copyWith(color: style.role('textMuted')),
        ),
        SizedBox(height: style.gap('4')),
        PairingActionRow(
          actions: <PairingAction>[
            PairingAction(
              label: PairingTr.copyLabel.tr,
              icon: Icons.content_copy_rounded,
              buttonKey: PairingCodeKeys.copy,
              onPressed: _copy,
            ),
            PairingAction(
              label: PairingTr.regenerateLabel.tr,
              icon: Icons.refresh_rounded,
              buttonKey: PairingCodeKeys.regenerate,
              onPressed: _regenerate,
            ),
          ],
          // The block stands on the `surfaceRaised` of the panel the screen put
          // it in, so a filled action here would take the strong edge. Neither
          // of these two is filled, which is deliberate: on a first run there is
          // nothing to press that is irreversible.
          surfaceRole: 'surfaceRaised',
        ),
        if (_status != null) ...<Widget>[
          SizedBox(height: style.gap('2')),
          Text(
            _status!,
            key: PairingCodeKeys.status,
            // `success` and `danger` are both declared at 4.5:1 on
            // `surfaceRaised`, and they are the two roles that say something; a
            // status line in `textMuted` would say the same thing about a
            // success and a failure.
            style: style.styleOf('sm').copyWith(
              color: style.role(_statusOk ? 'success' : 'danger'),
            ),
          ),
        ],
      ],
    );
  }

  /// One character in one box: an `md` control square, the same box a filled
  /// cell of `MkviCodeField` has, so the two screens agree.
  ///
  /// `FittedBox` with `scaleDown` for the same reason `MkviCodeField` uses it:
  /// a code that will not fit at 1.25 type must shrink, not overflow.
  Widget _cell(AppearanceStyle style, int index) {
    final ResolvedControl md = style.control('md');
    return Container(
      key: PairingCodeKeys.characterBox(index),
      width: md.height,
      height: md.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.role('accentSoft'),
        border: Border.all(color: style.role('borderStrong'), width: style.borderWidth),
        borderRadius: style.shape('sm').borderRadius,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _code[index],
          key: PairingCodeKeys.character(index),
          style: style.styleOf('lg').copyWith(color: style.role('text')),
        ),
      ),
    );
  }
}
