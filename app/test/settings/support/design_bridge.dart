/// Test-side names for the token implementation, kept for the tests that use
/// them.
///
/// ## Why this file still exists
///
/// The implementation used to live HERE, in the test tree, because production
/// code could not reach the generated token file. It now lives in
/// `app/lib/settings/appearance_tokens_impl.dart` and is reached through the
/// `mkvi_design` path dependency. What is left here is a name: the tests and
/// the widget harness say `DesignTokens` and `DesignTokensFixture`, and there
/// is no reason to rename every call site to fix a file's location.
///
/// So this file re-exports the production class under its historical name and
/// owns the one thing only a test can own: reading `design/tokens.json` from
/// disk, so a test can assert the implementation against the file instead of
/// against a copy of it. That read is a TEST concern and belongs in a test -
/// `token_contract_test.dart` is where the two are compared, and it is why the
/// implementation can be free of `dart:io`.
///
/// The fixture keeps both halves: [file] is the token file as the test reads it,
/// [tokens] is the production implementation, and the tests compare them.
library;

import 'package:mkvi/settings/appearance_tokens_impl.dart';

import 'tokens_file.dart';

export 'package:mkvi/settings/appearance_tokens_impl.dart' show DesignTokens;

/// The token file and the production implementation, loaded once per test run.
final class DesignTokensFixture {
  DesignTokensFixture._(this.file, this.tokens);

  /// `design/tokens.json` as this test reads it: no resolver, no generation, no
  /// derived colour. Every expectation in the settings tests is looked up
  /// here, so a copied hex cannot survive a token change.
  final TokenFile file;

  /// The production [AppearanceTokens] implementation, over the generated
  /// token file. The thing under test.
  final DesignTokens tokens;

  static DesignTokensFixture? _cached;

  /// Loads both, or returns the ones already loaded.
  factory DesignTokensFixture.load() {
    return _cached ??= _load();
  }

  static DesignTokensFixture _load() {
    return DesignTokensFixture._(TokenFile.load(), const DesignTokens());
  }
}
