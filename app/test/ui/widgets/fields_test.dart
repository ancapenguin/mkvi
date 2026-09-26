/// The text fields, measured rather than eyeballed.
///
/// A field is where the token file either reaches the screen or does not, so
/// every assertion here is one of: the NUMBER in the counter, the SIZE of the
/// field, the COLOUR the error edge is painted, the DURATION the multi-line
/// block takes to grow, or the Turkish sentence a screen handed in and gets
/// back out. "The field has an error style" is not an assertion; "the error
/// edge is `role('danger')` and the field is announced invalid" is.
library;

import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/widget_fixtures.dart';

void main() {
  group('a refused value is reported, not just coloured', () {
    testWidgets('the error edge is the danger role and the field says so', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviTextField(
            label: 'Sinyal sunucusu',
            errorText: 'Sunucu adresi boş olamaz; kendi Worker adresinizi girin.',
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      // The edge: read off the decoration the decorator actually received, not
      // off the widget I passed, because the theme supplies it.
      final InputDecorator decorator = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      final OutlineInputBorder edge =
          decorator.decoration.errorBorder! as OutlineInputBorder;
      expect(edge.borderSide.color, style.role('danger'));
      expect(edge.borderSide.width, style.borderWidth);
      expect(edge.borderRadius.topLeft.x, style.radius('sm'));

      // The sentence: the one the screen handed in, unchanged, and painted
      // with the theme's own error type.
      const String reason = 'Sunucu adresi boş olamaz; kendi Worker adresinizi girin.';
      expect(textIn(tester, find.text(reason)), reason);
      expect(
        styleIn(tester, find.text(reason)).color,
        style.role('danger'),
        reason: 'the sentence is painted in the danger role, not in a default',
      );
      expect(
        styleIn(tester, find.text(reason)).fontSize,
        style.typeStep('sm').size,
      );

      // The announcement: the flag a platform turns into "invalid entry".
      expect(
        tester.getSemantics(find.byKey(MkviFieldKeys.field)).validationResult,
        SemanticsValidationResult.invalid,
      );
      handle.dispose();
    });

    testWidgets('an accepted value is not announced as invalid', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviTextField(
            label: 'Adınız',
            helperText: 'Karşı tarafta görünecek adınız',
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byKey(MkviFieldKeys.field)).validationResult,
        SemanticsValidationResult.none,
      );
      const String helper = 'Karşı tarafta görünecek adınız';
      expect(textIn(tester, find.text(helper)), helper);
      expect(find.text('Sunucu adresi boş olamaz.'), findsNothing);
      handle.dispose();
    });
  });

  group('the field is a real control', () {
    testWidgets('it is at least the hit target tall, and says so in type', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        InputHost(child: MkviTextField(label: 'Sinyal sunucusu')),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      expect(
        style.control('md').height,
        lessThan(style.hitTargetMin),
        reason: 'the md control is 34 dp at density 1 and the target is 44',
      );
      expectHitTarget(tester, find.byKey(MkviFieldKeys.input), style: style);
      expect(
        tester.widget<TextField>(find.byKey(MkviFieldKeys.input)).style?.fontSize,
        style.control('md').fontSize,
        reason: 'a field is a control, so it is sized like the button beside it',
      );
    });

    testWidgets('the counter counts the characters that are in the field', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviTextField(label: 'Adınız', maxLength: 40),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      expect(
        textIn(tester, find.byKey(MkviFieldKeys.counter)),
        '0/40',
        reason: 'an empty field still says what it is counting',
      );

      await tester.enterText(find.byKey(MkviFieldKeys.input), 'MKVI');
      await tester.pump();

      expect(textIn(tester, find.byKey(MkviFieldKeys.counter)), '4/40');
      expect(
        styleIn(tester, find.byKey(MkviFieldKeys.counter)).fontSize,
        style.typeStep('2xs').size,
        reason: 'a counter is a hint, so it is the smallest type step',
      );
    });
  });

  group('the multi-line block', () {
    testWidgets('it is at least gap(8) lines tall before anything happens', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        InputHost(child: MkviMultilineField(label: 'Notlar', lines: 3)),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      expect(
        tester.getSize(find.byKey(MkviFieldKeys.block)).height,
        greaterThanOrEqualTo(style.gap('8') * 3),
      );
      expectHitTarget(tester, find.byKey(MkviFieldKeys.input), style: style);
    });

    testWidgets('it grows when the caret arrives, over the fast duration', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        InputHost(child: MkviMultilineField(label: 'Notlar', lines: 3)),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      // The gap between the block and the field is the thing that animates, and
      // it is measured as a distance between two rects rather than as a widget
      // property: the field's own height belongs to the decoration, and mixing
      // it into this number would test Material rather than this widget.
      double gapAbove() {
        final Rect block = tester.getRect(find.byKey(MkviFieldKeys.block));
        final Rect field = tester.getRect(find.byKey(MkviFieldKeys.input));
        return field.top - block.top;
      }

      expect(gapAbove(), style.gap('2'));
      final double growth = style.gap('6') - style.gap('2');

      await tester.tap(find.byKey(MkviFieldKeys.input));
      await tester.pump();
      expect(
        gapAbove(),
        closeTo(style.gap('2'), 0.5),
        reason: 'the growth has been asked for but has not moved yet',
      );

      await tester.pump(style.duration('fast') ~/ 2);
      final double half = gapAbove();
      expect(half, greaterThan(style.gap('2')), reason: 'half way, it is up');
      expect(half, lessThan(style.gap('6')), reason: 'and not finished yet');

      await tester.pump(style.duration('fast'));
      expect(
        gapAbove(),
        closeTo(style.gap('6'), 0.5),
        reason: 'after exactly duration(fast), the padding is the focused one',
      );
      expect(growth, greaterThan(0), reason: 'and the growth is a real step');
    });

    testWidgets('it reports a refused value the same way a single line does', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviMultilineField(
            label: 'Notlar',
            errorText: 'Notlar çok uzun olamaz.',
          ),
        ),
      );

      expect(textIn(tester, find.text('Notlar çok uzun olamaz.')), 'Notlar çok uzun olamaz.');
      expect(
        tester.getSemantics(find.byKey(MkviFieldKeys.field)).validationResult,
        SemanticsValidationResult.invalid,
      );
      final InputDecorator decorator = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      expect(
        (decorator.decoration.errorBorder! as OutlineInputBorder).borderSide.color,
        mkviStyleOf(tester).role('danger'),
      );
      handle.dispose();
    });
  });

  group('the matrix ROADMAP.md Faz 2 asks for', () {
    testWidgets('both fields paint at every scale and density, with no overflow', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviScaleMatrix()) {
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          InputHost(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MkviTextField(label: 'Sinyal sunucusu', maxLength: 200),
                MkviMultilineField(label: 'Notlar', lines: 3),
              ],
            ),
          ),
          settings: settings,
        );
        expectNoOverflow(tester);
        final AppearanceStyle style = mkviStyleOf(tester);
        expectHitTarget(tester, find.byKey(MkviFieldKeys.input).first, style: style);
      }
    });

    testWidgets('a refused value stays legible in every theme and accent', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviAppearanceMatrix()) {
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          InputHost(
            child: MkviTextField(
              label: 'Sinyal sunucusu',
              helperText: 'Kendi Cloudflare Worker adresiniz (https://…)',
              errorText: 'Sunucu adresi boş olamaz.',
            ),
          ),
          settings: settings,
        );
        expectNoOverflow(tester);
        final AppearanceStyle style = mkviStyleOf(tester);
        expectTokenContrast(style, 'text', 'surfaceSoft');
        expectTokenContrast(style, 'textMuted', 'surfaceSoft');
        expectTokenContrast(style, 'danger', 'surfaceSoft');
        expect(
          styleIn(tester, find.text('Sunucu adresi boş olamaz.')).color,
          style.role('danger'),
        );
      }
    });
  });
}
