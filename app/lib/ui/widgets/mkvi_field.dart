/// The text fields: a single-line field with a label, helper, error and counter,
/// and a multi-line one whose height is built from spacing steps.
///
/// ## What ThemeData already dresses, and what is left here
///
/// `settings/appearance_resolver.dart` fills `inputDecorationTheme` completely:
/// the `OutlineInputBorder` at the token radius, the enabled and focused edges,
/// the `danger` error edge, the hint, label and error type. So neither field
/// here sets a border, a border radius, a fill or a content padding. What
/// `ThemeData` does NOT reach is the rest of a field's behaviour:
///
/// * the text runs at `style.control('md').fontSize` - the control's own size,
///   which is not the `md` TYPE step and is the size every other control in the
///   app uses, so a field lines up with the button beside it;
/// * the caret is the accent, not `ColorScheme.primary` read by a default;
/// * the field is at least `hitTargetMin` tall, which is NOT the `md` control
///   height (34 dp at density 1) - the same distinction the 0.1.x close button
///   got wrong;
/// * a rejected value is ANNOUNCED: `validationResult: invalid` plus a visible
///   Turkish sentence, because a red edge nobody hears is a defect only for
///   sighted keyboard users.
///
/// `settings/connection_settings.dart` is why the error has to be a sentence
/// and not a colour: the layer below already refuses a bad value and hands back
/// a reason in Turkish (`EndpointValidation.errorTr`), and the screen that
/// shows it needs somewhere to put that exact text.
library;

import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

/// Keys for the parts of a field, so a test asserts on the widget it means.
abstract final class MkviFieldKeys {
  /// The group carrying the field's validation semantics.
  static const Key field = Key('mkvi.field.field');

  /// The [TextField] itself - the target of `tester.enterText`.
  static const Key input = Key('mkvi.field.input');

  /// The block that grows when a multi-line field is focused.
  static const Key block = Key('mkvi.field.block');

  /// The counter `MaxLengthEnforcement` renders, when a maximum is set.
  static const Key counter = Key('mkvi.field.counter');
}

/// A single-line text field: label, hint, helper, error and a length counter.
///
/// Every string is Turkish and every one of them comes from the screen: this
/// widget has no label of its own, because a field that invents its own label
/// is how a form ends up with two names for the same value.
class MkviTextField extends StatelessWidget {
  /// Creates a single-line field.
  const MkviTextField({
    super.key,
    required this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.maxLength,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.obscureText = false,
  });

  /// The field's name. Turkish, from the screen.
  final String label;

  /// What the value is, when it is not obvious. Turkish, from the screen.
  final String? hintText;

  /// A permanent line under the field. Turkish, from the screen.
  final String? helperText;

  /// Why the value was refused. Turkish, and it comes from the layer that
  /// refused it, not from here: a field that invents its own reason teaches the
  /// user that the app's reasons are approximate.
  final String? errorText;

  /// The longest value accepted, or null for no limit. When set, Material's own
  /// counter is shown, dressed in the type and colour of this layer.
  final int? maxLength;

  /// The text, when the screen owns it. Not disposed here.
  final TextEditingController? controller;

  /// The focus, when the screen owns it. Not disposed here.
  final FocusNode? focusNode;

  /// Which keyboard the field wants.
  final TextInputType? keyboardType;

  /// What the keyboard's action key does.
  final TextInputAction? textInputAction;

  /// Whether the value is capitalised on the keyboard.
  final TextCapitalization textCapitalization;

  /// Called on every change, with the current text.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Whether the field takes the keyboard on first build.
  final bool autofocus;

  /// Whether the field accepts input.
  final bool enabled;

  /// Whether the value is hidden as it is typed.
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final ResolvedControl md = style.control('md');
    final String? problem = (errorText == null || errorText!.isEmpty)
        ? null
        : errorText;
    // A local, so the null check promotes: a public field does not.
    final String? helper = (helperText == null || helperText!.isEmpty)
        ? null
        : helperText;

    return Semantics(
      key: MkviFieldKeys.field,
      // There is no `error` string on `Semantics` any more: `validationResult`
      // is the flag a platform turns into "invalid entry", and the sentence the
      // screen hands this field is the text that goes with it. The two travel
      // together, so a value can never be announced as invalid without a reason.
      validationResult: problem == null
          ? SemanticsValidationResult.none
          : SemanticsValidationResult.invalid,
      child: ConstrainedBox(
        // The `md` control height is 34 dp at density 1 and the hit target is
        // 44: a field has to be the larger of the two, or it is a control that
        // is smaller than the promise the token file makes.
        constraints: BoxConstraints(
          minHeight: md.height < style.hitTargetMin
              ? style.hitTargetMin
              : md.height,
        ),
        child: TextField(
          key: MkviFieldKeys.input,
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autofocus: autofocus,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          maxLines: 1,
          maxLength: maxLength,
          style: mkviInputTextStyle(style),
          cursorColor: style.role('accent'),
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          // No border, no radius, no fill, no content padding: all five come
          // from `inputDecorationTheme`, which the resolver fills from the token
          // file. Setting them here is how a second radius table starts.
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            helperText: helper,
            errorText: problem,
            // `errorStyle` and the label style are the theme's own - the `sm`
            // step and the `danger` role - because the resolver fills
            // `inputDecorationTheme` from the token file. Only the helper's
            // colour is said here: the theme sets no helper style, and
            // Material's default is not a token.
            helperStyle: style.styleOf('sm').copyWith(
              color: style.role('textMuted'),
            ),
          ),
          // The counter is built here rather than left to Material's default so
          // that it is a keyed widget with a token type: a test asserts the
          // number, and a theme change cannot silently restyle it.
          buildCounter: maxLength == null
              ? null
              : (
                  BuildContext context, {
                  required int currentLength,
                  required int? maxLength,
                  required bool isFocused,
                }) => Text(
                  '$currentLength/$maxLength',
                  key: MkviFieldKeys.counter,
                  style: style.styleOf('2xs').copyWith(
                    color: style.role('textMuted'),
                  ),
                ),
        ),
      ),
    );
  }
}

/// A multi-line text field whose block grows while the caret is in it.
///
/// The block's vertical padding and its minimum height are spacing steps, not
/// numbers, and the growth is animated over `style.duration('fast')` - which is
/// `instant` under reduced motion, because the resolver replaced every
/// duration in the token file, not the ones this widget wrote.
///
/// Growth is one step of padding, deliberately: a field that jumps several
/// lines the moment it is focused moves the text the user was reading, which is
/// a worse defect than a field that does not grow at all.
class MkviMultilineField extends StatefulWidget {
  /// Creates a multi-line field.
  const MkviMultilineField({
    super.key,
    required this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.maxLength,
    this.lines = 3,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
  });

  /// The field's name. Turkish, from the screen.
  final String label;

  /// What the value is, when it is not obvious. Turkish, from the screen.
  final String? hintText;

  /// A permanent line under the field. Turkish, from the screen.
  final String? helperText;

  /// Why the value was refused. Turkish, from the screen.
  final String? errorText;

  /// The longest value accepted, or null for no limit.
  final int? maxLength;

  /// How many lines of text the field is tall enough for.
  final int lines;

  /// The text, when the screen owns it. Not disposed here.
  final TextEditingController? controller;

  /// The focus, when the screen owns it. Not disposed here.
  final FocusNode? focusNode;

  /// Called on every change, with the current text.
  final ValueChanged<String>? onChanged;

  /// Whether the field takes the keyboard on first build.
  final bool autofocus;

  /// Whether the field accepts input.
  final bool enabled;

  @override
  State<MkviMultilineField> createState() => _MkviMultilineFieldState();
}

class _MkviMultilineFieldState extends State<MkviMultilineField> {
  FocusNode? _ownNode;

  /// The caller's node when there is one, otherwise one this widget owns.
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final String? problem = (widget.errorText == null || widget.errorText!.isEmpty)
        ? null
        : widget.errorText;
    // A local, so the null check promotes: a public field does not.
    final String? helper = (widget.helperText == null ||
            widget.helperText!.isEmpty)
        ? null
        : widget.helperText;

    // `FocusNode` is a `Listenable`, so the growth follows the caret without
    // this widget owning any state of its own.
    return ListenableBuilder(
      listenable: _node,
      builder: (BuildContext context, Widget? _) {
        final bool focused = _node.hasFocus;
        return Semantics(
          key: MkviFieldKeys.field,
          validationResult: problem == null
              ? SemanticsValidationResult.none
              : SemanticsValidationResult.invalid,
          child: AnimatedContainer(
            key: MkviFieldKeys.block,
            duration: style.duration('fast'),
            curve: style.motionEasing,
            padding: EdgeInsets.symmetric(
              vertical: focused ? style.gap('6') : style.gap('2'),
            ),
            constraints: BoxConstraints(
              minHeight: style.gap('8') * widget.lines,
            ),
            child: TextField(
              key: MkviFieldKeys.input,
              controller: widget.controller,
              focusNode: _node,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              minLines: widget.lines,
              maxLines: widget.lines,
              maxLength: widget.maxLength,
              keyboardType: TextInputType.multiline,
              style: mkviInputTextStyle(style),
              cursorColor: style.role('accent'),
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hintText,
                helperText: helper,
                errorText: problem,
                helperStyle: style.styleOf('sm').copyWith(
                  color: style.role('textMuted'),
                ),
              ),
              buildCounter: widget.maxLength == null
                  ? null
                  : (
                      BuildContext context, {
                      required int currentLength,
                      required int? maxLength,
                      required bool isFocused,
                    }) => Text(
                      '$currentLength/$maxLength',
                      key: MkviFieldKeys.counter,
                      style: style.styleOf('2xs').copyWith(
                        color: style.role('textMuted'),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// The [TextStyle] every text field in the app paints with.
///
/// The control's own font size rather than the `md` TYPE step: `md` the type
/// step and `md` the control are two different numbers in `tokens.json`, and a
/// field is a control, so it lines up with the button next to it.
TextStyle mkviInputTextStyle(AppearanceStyle style) {
  return style.styleOf('sm').copyWith(
    fontSize: style.control('md').fontSize,
    color: style.role('text'),
  );
}
