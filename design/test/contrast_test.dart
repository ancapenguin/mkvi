// The accessibility gate for the mkvi design tokens.
//
//   cd design && dart pub get && dart test
//
// This is the test that makes the 17 WCAG contrast violations found in the
// frozen React/Tauri UI impossible to reintroduce. It fails when:
//
//   * any pair in tokens.json `contrast` is below its declared minimum in any
//     of the 4 themes x 4 accents combinations,
//   * a theme does not define exactly the same role set as every other theme
//     (the bug that let forest and plum fall back to midnight's accent),
//   * `focusRing` equals `accent` in any combination (1.00:1, invisible),
//   * a required pair is missing from the list, so the gate cannot be quietly
//     weakened by deleting a line from tokens.json,
//   * the stage is not dark with light text in every theme,
//   * lib/generated/tokens.g.dart is stale, i.e. somebody edited tokens.json
//     without re-running the generator.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/generate_tokens.dart';

/// Pairs that must exist in `contrast` because each one closes a measured
/// failure in the old UI. Removing a pair from tokens.json without removing it
/// from this list fails the build.
const List<ContrastPair> requiredPairs = <ContrastPair>[
  // Video / call-stage placeholder text measured 1.17:1 and 2.79:1 in the old
  // light theme. The stage is now always dark and always uses textOnStage.
  ContrastPair('textOnStage', 'stage', 4.5),

  // The old focus ring was literally the accent fill: 1.00:1, invisible.
  ContrastPair('focusRing', 'accent', 3.0),
  ContrastPair('focusRing', 'surface', 4.5),
  ContrastPair('focusRing', 'bg', 4.5),

  // Hairline separators measured 1.6:1 - 2.3:1 in all four themes.
  ContrastPair('border', 'surface', 3.0),
  ContrastPair('border', 'bg', 3.0),
  ContrastPair('border', 'surfaceRaised', 3.0),
  ContrastPair('borderStrong', 'surface', 3.0),

  // The progress-bar track used surfaceSoft: 1.24:1. It now uses `border`,
  // so `border` must clear 3:1 on the surface the track sits in.
  ContrastPair('border', 'surfaceSoft', 3.0),

  // The outgoing message timestamp was 60% white on the accent: 4.47:1. It is
  // now full-opacity textOnAccent, validated on the fill and both states.
  ContrastPair('textOnAccent', 'accent', 4.5),
  ContrastPair('textOnAccent', 'accentHover', 4.5),
  ContrastPair('textOnAccent', 'accentActive', 4.5),

  // Disabled controls measured 3.20:1. The weakest text role now clears
  // 4.5:1 on every surface a disabled control can sit on.
  ContrastPair('textSubtle', 'surface', 4.5),
  ContrastPair('textSubtle', 'surfaceRaised', 4.5),
  ContrastPair('textSubtle', 'surfaceSoft', 4.5),
  ContrastPair('textSubtle', 'bg', 4.5),
];

/// Keeps concurrent test files from clobbering each other's temp output.
var counter = 0;

class Measurement {  const Measurement(this.theme, this.accent, this.ratio, this.fg, this.bg);

  final String theme;
  final String accent;
  final double ratio;
  final Rgb fg;
  final Rgb bg;

  String get where => '$theme/$accent';
}

late final Directory packageRoot;
late final TokenSpec spec;

void main() {
  // Loaded eagerly: the group titles below report the real combination count,
  // and a broken token file should fail before any test is declared.
  packageRoot = _findPackageRoot();
  final tokens = File('${packageRoot.path}/tokens.json');
  if (!tokens.existsSync()) {
    throw StateError('tokens.json not found at ${tokens.path}');
  }
  spec = TokenSpec.parse(tokens.readAsStringSync(encoding: utf8), origin: 'tokens.json');

  group('token completeness', () {
    test('the token file declares four themes and four accents', () {
      expect(spec.themeIds, <String>['midnight', 'light', 'forest', 'plum'],
          reason: 'The shipped theme set changed; update the test and the docs.');
      expect(spec.accentIds, <String>['blue', 'teal', 'amber', 'rose']);
      expect(spec.combinations, hasLength(16));
    });

    test('every theme defines exactly the same roles, none missing, none extra', () {
      final expected = spec.roles.toSet();
      expect(expected, hasLength(29), reason: 'The role list is the contract; 29 roles expected.');

      for (final themeId in spec.themeIds) {
        final defined = spec.themeRoles(themeId).keys.toSet();
        final missing = expected.difference(defined).toList()..sort();
        final extra = defined.difference(expected).toList()..sort();
        expect(missing, isEmpty,
            reason: 'Theme "$themeId" is missing role(s) ${missing.join(', ')}. '
                'A missing role silently falls back to another theme, which is how '
                'forest and plum inherited midnight\'s accent in the old UI.');
        expect(extra, isEmpty,
            reason: 'Theme "$themeId" defines role(s) ${extra.join(', ')} that are not '
                'declared in meta.roles.');
      }
    });

    test('every role in the contrast list is declared and opaque', () {
      for (final pair in spec.contrastList) {
        expect(spec.roles, contains(pair.fg), reason: 'Unknown fg role "${pair.fg}".');
        expect(spec.roles, contains(pair.bg), reason: 'Unknown bg role "${pair.bg}".');
      }
      for (final themeId in spec.themeIds) {
        for (final accentId in spec.accentIds) {
          for (final pair in spec.contrastList) {
            for (final role in [pair.fg, pair.bg]) {
              final colour = spec.resolveColor(themeId, accentId, role);
              expect(colour.isOpaque, isTrue,
                  reason: 'Role "$role" is ${colour.toHex()} with alpha; a '
                      'translucent role cannot be contrast-checked in isolation.');
            }
          }
        }
      }
    });

    test('every theme and accent has a Turkish label for the settings UI', () {
      for (final themeId in spec.themeIds) {
        expect(spec.themeLabel(themeId), isNotEmpty, reason: 'Theme "$themeId" has no labelTr.');
      }
      for (final accentId in spec.accentIds) {
        expect(spec.accentLabel(accentId), isNotEmpty, reason: 'Accent "$accentId" has no labelTr.');
      }
    });
  });

  group('contrast', () {
    test('every declared pair holds in all ${spec.combinations.length} '
        'theme x accent combinations', () {
      for (final pair in spec.contrastList) {
        final measurements = <Measurement>[];
        for (final combination in spec.combinations) {
          final fg = spec.resolveColor(combination.theme, combination.accent, pair.fg);
          final bg = spec.resolveColor(combination.theme, combination.accent, pair.bg);
          measurements.add(Measurement(combination.theme, combination.accent, fg.contrastWith(bg), fg, bg));
        }
        measurements.sort((a, b) => a.ratio.compareTo(b.ratio));
        final worst = measurements.first;
        final runnerUp = measurements.length > 1 ? measurements[1] : null;
        final margin = worst.ratio - pair.min;
        expect(
          worst.ratio,
          greaterThanOrEqualTo(pair.min),
          reason: 'Worst case for "${pair.fg}" on "${pair.bg}": '
              '${worst.ratio.toStringAsFixed(2)}:1 in ${worst.where} '
              '(${worst.fg.toHex()} on ${worst.bg.toHex()}), required '
              '${pair.min.toStringAsFixed(1)}:1, margin ${margin >= 0 ? '+' : ''}'
              '${margin.toStringAsFixed(2)}. Next worst: '
              '${runnerUp == null ? 'n/a' : '${runnerUp.ratio.toStringAsFixed(2)}:1 in ${runnerUp.where}'}. '
              'All ${measurements.length} combinations were measured.',
        );
      }
    });

    test('the gate actually catches each old violation when it is reintroduced', () {
      // Negative controls. A gate that cannot fail is not a gate, so each case
      // below reintroduces one measured failure from the frozen React/Tauri UI
      // and asserts the same maths rejects it.
      final cases = <String, void Function(Map<String, dynamic>)>{
        // The old focus ring was literally the accent fill: 1.00:1.
        'focus ring painted in the accent fill': (json) {
          (json['themes']['light'] as Map<String, dynamic>)['focusRing'] = '#2457d6';
          for (final theme in ['midnight', 'forest', 'plum']) {
            (json['themes'][theme] as Map<String, dynamic>)['focusRing'] = '#2665ef';
          }
        },
        // The old light theme painted the call stage #e9edf3 and then put
        // near-white placeholder text on it: 1.17:1.
        'light stage with near-white placeholder text': (json) {
          (json['themes']['light'] as Map<String, dynamic>)['stage'] = '#e9edf3';
          (json['themes']['light'] as Map<String, dynamic>)['textOnStage'] = '#f8fafc';
        },
        // The 2.79:1 sibling: muted secondary text on that same light stage.
        'muted secondary text on a light stage': (json) {
          (json['themes']['light'] as Map<String, dynamic>)['stage'] = '#e9edf3';
          (json['themes']['light'] as Map<String, dynamic>)['textMuted'] = '#b8c1cc';
        },
        // The old hairline separators: 1.6:1 - 2.3:1 in all four themes.
        'hairline separators back to 1.6:1': (json) {
          for (final theme in ['midnight', 'light', 'forest', 'plum']) {
            (json['themes'][theme] as Map<String, dynamic>)['border'] = '#c5ccd6';
          }
        },
        // The old outgoing timestamp was 60% white on the accent: 4.47:1.
        '60% white timestamp on the accent': (json) {
          (json['accents']['blue'] as Map<String, dynamic>)['on'] = '#666666';
        },
        // The old disabled controls: 3.20:1.
        'disabled control text at 3.2:1': (json) {
          (json['themes']['midnight'] as Map<String, dynamic>)['textSubtle'] = '#5b6572';
        },
        // The old progress-bar track used surfaceSoft: 1.24:1.
        'progress track in surfaceSoft': (json) {
          (json['themes']['midnight'] as Map<String, dynamic>)['border'] = '#212c3c';
        },
        // An accent too light to carry near-white text.
        'amber accent too light for its on-colour': (json) {
          final amber = json['accents']['amber'] as Map<String, dynamic>;
          amber['base'] = '#fcd34d';
          amber['hover'] = '#fde68a';
          amber['active'] = '#fbbf24';
        },
        // Forest losing its accent: the silent-fallback bug from the old UI.
        'forest accent missing': (json) {
          (json['themes']['forest'] as Map<String, dynamic>).remove('accent');
        },
      };

      for (final entry in cases.entries) {
        final mutated = _mutate(entry.value);
        var caught = false;
        final rejected = <String>[];
        try {
          final broken = TokenSpec.parse(mutated, origin: 'negative-control');
          for (final pair in broken.contrastList) {
            for (final combination in broken.combinations) {
              final fg = broken.resolveColor(combination.theme, combination.accent, pair.fg);
              final bg = broken.resolveColor(combination.theme, combination.accent, pair.bg);
              final ratio = fg.contrastWith(bg);
              if (ratio < pair.min) {
                rejected.add('${pair.fg} on ${pair.bg} in ${combination.theme}/'
                    '${combination.accent} = ${ratio.toStringAsFixed(2)}:1');
              }
            }
          }
          // The stage-polarity rule is a third layer: even if a pair list were
          // weakened, a light stage with light text is refused outright.
          for (final themeId in broken.themeIds) {
            final stage = broken.resolveColor(themeId, broken.defaultAccent, 'stage');
            final onStage = broken.resolveColor(themeId, broken.defaultAccent, 'textOnStage');
            if (stage.luminance >= 0.02 || onStage.luminance <= 0.5) {
              rejected.add('stage polarity in $themeId: stage=${stage.toHex()} '
                  '(L=${stage.luminance.toStringAsFixed(3)}) '
                  'textOnStage=${onStage.toHex()} (L=${onStage.luminance.toStringAsFixed(3)})');
            }
          }
        } on TokenError catch (error) {
          // Rejected during validation rather than by the contrast maths. That is
          // an equally valid rejection, and it is what stops a missing role from
          // ever reaching the contrast stage.
          caught = true;
          rejected.add('validation: ${error.problems.first}');
        }
        expect(caught || rejected.isNotEmpty, isTrue,
            reason: 'Reintroducing "${entry.key}" was NOT detected by either the '
                'validation or the contrast maths. The gate would have passed a '
                'palette that reproduces a known violation.');
      }
    });

    test('the pairs that close the old 17 violations are all present', () {
      for (final required in requiredPairs) {
        final present = spec.contrastList.any((pair) => pair.fg == required.fg && pair.bg == required.bg);
        expect(present, isTrue,
            reason: 'tokens.json no longer declares "${required.fg}" on "${required.bg}". '
                'That pair closes a measured violation in the old UI; do not delete it.');
      }
    });

    test('the stage is dark and its text is light in every theme', () {
      for (final themeId in spec.themeIds) {
        final stage = spec.resolveColor(themeId, spec.defaultAccent, 'stage');
        final onStage = spec.resolveColor(themeId, spec.defaultAccent, 'textOnStage');
        expect(stage.luminance, lessThan(0.02),
            reason: 'Theme "$themeId" has a light stage (${stage.toHex()}). The video and '
                'call stage is always dark, in every theme; that is what fixes the '
                '1.17:1 placeholder text the old light theme shipped.');
        expect(onStage.luminance, greaterThan(0.5),
            reason: 'Theme "$themeId" has dark stage text (${onStage.toHex()}). '
                'textOnStage is always light.');
      }
    });
  });

  group('focus ring', () {
    test('focusRing is never the accent fill', () {
      for (final combination in spec.combinations) {
        final accent = spec.resolveColor(combination.theme, combination.accent, 'accent');
        final focusRing = spec.resolveColor(combination.theme, combination.accent, 'focusRing');
        expect(focusRing, isNot(equals(accent)),
            reason: 'In ${combination.theme}/${combination.accent} the focus ring is '
                '${focusRing.toHex()}, identical to the accent fill '
                '(${focusRing.contrastWith(accent).toStringAsFixed(2)}:1). '
                'The old UI measured exactly 1.00:1 here.');
      }
    });
  });

  group('generator', () {
    test('rejects a theme that is missing a role', () {
      final broken = _mutate((json) {
        (json['themes']['forest'] as Map<String, dynamic>).remove('borderStrong');
      });
      final error = _expectTokenError(broken);
      expect(error, contains('forest'),
          reason: 'The failure must name the offending theme.');
      expect(error, contains('borderStrong'),
          reason: 'The failure must name the missing role.');
    });

    test('rejects a theme that defines an extra role', () {
      final broken = _mutate((json) {
        (json['themes']['plum'] as Map<String, dynamic>)['brandPink'] = '#ff00ff';
      });
      expect(_expectTokenError(broken), contains('brandPink'));
    });

    test('rejects a contrast entry that references an unknown role', () {
      final broken = _mutate((json) {
        (json['contrast'] as List<dynamic>).add(<String, dynamic>{
          'fg': 'text',
          'bg': 'surfaceSparkle',
          'min': 4.5,
        });
      });
      expect(_expectTokenError(broken), contains('surfaceSparkle'));
    });

    test('rejects a malformed colour', () {
      final broken = _mutate((json) {
        (json['themes']['light'] as Map<String, dynamic>)['textMuted'] = 'bluish';
      });
      expect(_expectTokenError(broken), contains('textMuted'));
    });

    test('rejects a theme whose cached derived colour is stale', () {
      final broken = _mutate((json) {
        (json['themes']['forest'] as Map<String, dynamic>)['focusRing'] = '#123456';
      });
      expect(_expectTokenError(broken), contains('focusRing'));
    });

    test('is deterministic: the same input produces byte-identical output', () {
      final first = generateDart(spec);
      final second = generateDart(TokenSpec.parse(
        File('${packageRoot.path}/tokens.json').readAsStringSync(encoding: utf8),
        origin: 'tokens.json',
      ));
      expect(second, first, reason: 'The generator must not depend on run order or timing.');
    });

    test('writes lib/generated/tokens.g.dart and it is up to date', () {
      final committed = File('${packageRoot.path}/lib/generated/tokens.g.dart');
      expect(committed.existsSync(), isTrue,
          reason: 'lib/generated/tokens.g.dart is missing. Run: dart run tool/generate_tokens.dart');

      // Separator is explicit: systemTemp has no trailing slash, and on Linux
      // the bare concatenation pointed at an unwritable '/tmpmkvi_...' path.
      final temp = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
          'mkvi_tokens_check_${pid}_$counter.g.dart');
      counter++;
      try {
        final result = Process.runSync(
          Platform.resolvedExecutable,
          <String>['run', 'tool/generate_tokens.dart', '--out', temp.path],
          workingDirectory: packageRoot.path,
        );
        expect(result.exitCode, 0, reason: 'The generator failed:\n'
            '${result.stdout}\n${result.stderr}');

        final fresh = temp.readAsBytesSync();
        final existing = committed.readAsBytesSync();
        final difference = _describeDifference(fresh, existing);
        expect(difference, isNull,
            reason: 'lib/generated/tokens.g.dart is stale: $difference\n'
                'tokens.json and the generated Dart must agree. '
                'Run: dart run tool/generate_tokens.dart');
      } finally {
        if (temp.existsSync()) temp.deleteSync();
      }
    });

    test('emitted colours carry a comment naming the token and the theme', () {
      final source = generateDart(spec);
      for (final themeId in spec.themeIds) {
        final accentId = spec.accentIds.first;
        final colour = spec.resolveColor(themeId, accentId, 'surface');
        expect(source, contains('Color(${colour.toDartLiteral()}), // surface ($themeId/$accentId'),
            reason: 'Missing the "token (theme/accent)" comment for $themeId.');
      }
    });

    test('exports what a consumer cannot derive from a colour', () {
      // The app used to read these back out of tokens.json through dart:io,
      // which throws in a packaged app that has no token file. Each one is now
      // emitted, and this is what stops a later "simplification" of
      // generateDart() from quietly deleting one and putting the file read
      // back into production.
      final source = generateDart(spec);

      // The gate's own input.
      for (final pair in spec.contrastList) {
        expect(source, contains("foregroundRole: '${pair.fg}',"),
            reason: 'The contrast list is missing the ${pair.fg} on ${pair.bg} pair.');
        expect(source, contains("backgroundRole: '${pair.bg}',"),
            reason: 'The contrast list is missing the ${pair.fg} on ${pair.bg} pair.');
        expect(source, contains('minimum: ${_dartText(pair.min)},'),
            reason: 'The ${pair.fg} on ${pair.bg} pair lost its minimum.');
      }
      expect(_occurrences(source, 'MkviContrastRequirement('), spec.contrastList.length + 1,
          reason: 'The contrast list must be emitted exactly once, in order.');

      // Per theme: polarity and the three derive amounts.
      for (final themeId in spec.themeIds) {
        final target = tryParseColor(spec.themeDerive(themeId)['focusRingTarget'] as String?)!;
        expect(source, contains('focusRingTarget: Color(${target.toDartLiteral()}),'),
            reason: 'Theme $themeId does not export its focusRingTarget.');
        expect(source, contains('isDark: ${spec.isDarkTheme(themeId)},'),
            reason: 'Theme $themeId does not export its polarity.');
        expect(source, contains('focusRingMix: ${_dartText(spec.themeMix(themeId, 'focusRingMix'))},'),
            reason: 'Theme $themeId does not export its focusRingMix.');
        expect(source, contains('accentSoftMix: ${_dartText(spec.themeMix(themeId, 'accentSoftMix'))},'),
            reason: 'Theme $themeId does not export its accentSoftMix.');
      }

      // The radius presets, which the app used to type out beside the generated
      // file instead of reading.
      for (final preset in (spec.radius['presets'] as Map<String, dynamic>).keys) {
        expect(source, contains("const mkviRadii${_pascal(preset)} = MkviRadii("),
            reason: 'Radius preset $preset is not emitted.');
      }
      expect(source, contains('const List<String> mkviRadiusPresets ='),
          reason: 'The radius preset NAMES are not exported.');
    });

    test('rejects a theme whose derive block cannot be exported', () {
      // A focus ring target that is a role name instead of a colour has no
      // single value per theme, so it cannot become a generated constant. That
      // must be a token error, not a constant that lies.
      final broken = _mutate((json) {
        (json['themes']['midnight'] as Map<String, dynamic>)['derive']['focusRingTarget'] = 'text';
      });
      expect(_expectTokenError(broken), contains('focusRingTarget'));
    });

    test('rejects a derive mix amount outside 0.0..1.0', () {
      final broken = _mutate((json) {
        (json['themes']['light'] as Map<String, dynamic>)['derive']['accentSoftMix'] = 1.4;
      });
      expect(_expectTokenError(broken), contains('accentSoftMix'));
    });

    test('rejects a theme with no polarity', () {
      final broken = _mutate((json) {
        (json['themes']['plum'] as Map<String, dynamic>)['polarity'] = 'dim';
      });
      expect(_expectTokenError(broken), contains('polarity'));
    });
  });
}

/// Mutates the real token file in memory so the failure modes can be tested
/// without writing a broken file to disk.
String _mutate(void Function(Map<String, dynamic>) change) {
  final source = File('${packageRoot.path}/tokens.json').readAsStringSync(encoding: utf8);
  final json = jsonDecode(source) as Map<String, dynamic>;
  change(json);
  return const JsonEncoder.withIndent('  ').convert(json);
}

String _expectTokenError(String source) {
  try {
    TokenSpec.parse(source, origin: 'mutated-tokens.json');
  } on TokenError catch (error) {
    return error.problems.join('\n');
  }
  throw StateError('Expected the token file to be rejected, but it was accepted.');
}

/// How many times [needle] appears in [haystack]. Used to assert a list was
/// emitted exactly once rather than at least once.
int _occurrences(String haystack, String needle) {
  var count = 0;
  var index = haystack.indexOf(needle);
  while (index != -1) {
    count++;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

/// The same number spelling the generator emits, so the assertions above do not
/// encode a second, drifting idea of how a double is formatted.
String _dartText(num value) {
  var text = value.toStringAsFixed(4);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

/// `cozy` -> `Cozy`: the generated constant's own name for a preset.
String _pascal(String value) => value
    .split(RegExp(r'[^A-Za-z0-9]'))
    .where((part) => part.isNotEmpty)
    .map((part) => part[0].toUpperCase() + part.substring(1))
    .join();

/// Returns null when the byte lists are equal, otherwise a short description of
/// the first difference.
String? _describeDifference(List<int> fresh, List<int> existing) {
  if (fresh.length == existing.length) {
    var identical = true;
    for (var i = 0; i < fresh.length; i++) {
      if (fresh[i] != existing[i]) {
        identical = false;
        break;
      }
    }
    if (identical) return null;
  }
  final freshLines = utf8.decode(fresh).split('\n');
  final existingLines = utf8.decode(existing).split('\n');
  final limit = freshLines.length < existingLines.length ? freshLines.length : existingLines.length;
  for (var i = 0; i < limit; i++) {
    if (freshLines[i] != existingLines[i]) {
      return 'line ${i + 1} differs:\n'
          '  committed: ${existingLines[i]}\n'
          '  generated: ${freshLines[i]}';
    }
  }
  return 'line count differs: committed has ${existingLines.length} lines, '
      'generated has ${freshLines.length}';
}

Directory _findPackageRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File('${directory.path}/pubspec.yaml');
    if (pubspec.existsSync() && pubspec.readAsStringSync(encoding: utf8).contains('mkvi_design')) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not find the mkvi_design package root from ${Directory.current.path}');
    }
    directory = parent;
  }
}
