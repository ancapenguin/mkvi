/// The compiled form of `design/tokens.json`, the design system's only source.
///
/// `tokens.json` is the file a designer edits. This library is its
/// COMPILED form, produced by `design/tool/generate_tokens.dart` and checked by
/// `design/test/contrast_test.dart`: if the generated file is stale, the gate
/// fails, so what a consumer imports here is always the file's own values.
///
/// ## The one import
///
/// ```dart
/// import 'package:mkvi_design/mkvi_design.dart';
/// ```
///
/// Everything is re-exported from the generated file, and nothing else is
/// declared here, so a consumer never has to know which generated file a
/// symbol came from.
///
/// ## Why `lib/`
///
/// The generated file used to live in `design/generated/`, outside `lib/`. A
/// library under `app/lib/` cannot import a file outside its own package, and
/// the analyzer refuses the relative path that would reach it, so the token
/// implementation ended up in the app's TEST tree - where no production code
/// could reach it and where it read `tokens.json` off disk, a file a packaged
/// app does not have. Emitting into `lib/` and taking the design package as a
/// path dependency is what makes the design system reachable from production
/// code, and it keeps the token file where it was: one source, in one place.
///
/// ## Editing
///
/// Never edit the generated file by hand. Edit `tokens.json`, then:
///
/// ```sh
/// cd design && dart run tool/generate_tokens.dart && dart test
/// ```
///
/// The file carries an `// ignore_for_file` for the two lints that only make
/// sense for hand-written code, because the names come from the token file
/// rather than from a Dart author.
library;

export 'generated/tokens.g.dart';
