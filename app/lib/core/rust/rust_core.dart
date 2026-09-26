/// The one handle the Dart side holds on `mkvi_core`, and the one place the
/// native library is loaded.
///
/// ## Why loading is lazy, tolerant, and happens exactly here
///
/// `crates/mkvi_bridge/dart` resolves its library through a path relative to the
/// current directory (see `rust_bridge_loader.dart` for the measurement and the
/// rejected alternatives). Loading it eagerly, at import time or in `main()`,
/// would buy nothing and cost a great deal:
///
/// * **CI has no library.** A Linux runner with a Rust toolchain but no built
///   `mkvi_bridge` would fail every Dart test at import time, including the
///   tests that have nothing to do with the bridge. The one behaviour that must
///   hold everywhere is "the app does not crash".
/// * **A failed load must be a state, not a stack trace.** The app's own type
///   for "the store cannot be read" already exists —
///   `PeerStoreUnavailable`, which `SessionBootstrap` turns into `SetupBroken`,
///   and `SetupBroken.showsPairingScreen` is false by construction. So the
///   missing library has exactly one correct destination and this class feeds
///   it.
///
/// `RustCore.isAvailable == false` is therefore not an error path; it is the
/// normal state of any machine where the Rust library was never built, and the
/// adapters below are written to answer their interfaces in that state rather
/// than to throw.
library;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
// `mkvi_bridge`'in `lib/` altında genel bir kütüphane dosyası yok; README'i de
// tüketicinin tam olarak bu yolu kullanmasını söylüyor
// ("package:mkvi_bridge/src/rust/api.dart içinden çağırır"), ve `RustLib`
// yalnız üretilmiş `frb_generated.dart` içinde yaşıyor.
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/api.dart';
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/frb_generated.dart';

import 'rust_bridge_loader.dart';

/// Thrown by [RustCore.requireCore] when the library did not load.
///
/// Only code that has already checked [RustCore.isAvailable] should reach it;
/// the store adapters answer their own interfaces instead of throwing, because
/// every one of their interfaces has a defined "cannot read" answer.
final class RustCoreUnavailable implements Exception {
  const RustCoreUnavailable(this.message);

  /// Turkish, and says what to do: this string can reach a screen.
  final String message;

  @override
  String toString() => 'RustCoreUnavailable: $message';
}

/// The result of trying to open the core: the handle, or the reason there is
/// none. A value, so "the bridge is missing" cannot be forgotten at a call site.
sealed class RustCoreOpenResult {
  const RustCoreOpenResult();
}

/// The library loaded and the core opened.
final class RustCoreOpened extends RustCoreOpenResult {
  const RustCoreOpened(this.core);

  final RustCore core;
}

/// The library could not be loaded, or the core could not be opened.
///
/// [core] is still handed out, so a caller can read [RustCore.isAvailable] and
/// the Turkish text without matching on the result type.
final class RustCoreNotAvailable extends RustCoreOpenResult {
  const RustCoreNotAvailable(this.core);

  final RustCore core;
}

/// The handle on `mkvi_core`.
///
/// Holds exactly one [Core] and the directory it was opened against. There is
/// no second constructor that takes a [Core] directly, so a [RustCore] in a test
/// can only be an unavailable one — which is the whole test contract: either the
/// real library, or explicitly the "no bridge" path, and nothing in between.
final class RustCore {
  RustCore._(this._core, {required this.dataDir});

  Core? _core;

  /// The directory the core was opened against. Kept for diagnostics and for the
  /// honest report of "which install".
  final String dataDir;

  /// Whether the Rust library is present and the core is open.
  bool get isAvailable => _core != null;

  /// Turkish: why the core is not open, or null when it is.
  String? get unavailableMessageTr =>
      isAvailable ? null : RustCore._missingMessage;

  /// Turkish: what the user can do about it, or null when it is.
  String? get unavailableRecoveryTr =>
      isAvailable ? null : RustCore._missingRecovery;

  /// The core, or a Turkish throw. Callers that can answer "cannot read" in
  /// their own vocabulary must check [isAvailable] instead.
  Core requireCore() {
    final Core? core = _core;
    if (core == null) {
      throw RustCoreUnavailable(
        '${RustCore._missingMessage} ${RustCore._missingRecovery}',
      );
    }
    return core;
  }

  /// The paths that were searched, when the library is missing. Empty otherwise.
  List<String> get searchedLibraryPaths =>
      isAvailable ? const <String>[] : _searchedPaths;

  List<String> _searchedPaths = const <String>[];

  /// Releases the handle. The library itself is not unloaded: `flutter_rust_bridge`
  /// tears its own wiring down with the process.
  Future<void> dispose() async {
    _core = null;
    _searchedPaths = const <String>[];
  }

  /// The message a missing library produces. One place, so the peer store, the
  /// history store and the identity loader cannot say three different things
  /// about the same failure.
  static const String _missingMessage =
      'Uygulamanın güvenlik çekirdeği yüklenemedi; MKVI verinizi şifreleyemiyor.';

  static const String _missingRecovery =
      'Uygulamayı yeniden başlat. Sorun sürerse MKVI kurulumunu yeniden yap.';

  /// Whether `RustLib.init` has already run in this isolate.
  ///
  /// Tracked here rather than read off `RustLib.instance.initialized`, because
  /// that getter lives on the singleton and the singleton is `@internal`. What
  /// this has to be right about is the second call in a test run: `RustLib.init`
  /// throws if it is called twice, and a second call is not a bug.
  static bool _libraryInitialised = false;

  /// Opens the core under [dataDir], or says why it could not be opened.
  ///
  /// Never throws. That is the contract, and it is the reason this method exists
  /// rather than a `try` at every call site: a missing native library is an
  /// expected state on a build machine, not an exception.
  static Future<RustCoreOpenResult> open({
    required String dataDir,
    Map<String, String>? environment,
    String? workingDirectory,
    String? executablePath,
  }) async {
    final BridgeLibraryLookup lookup = locateMkviBridgeLibrary(
      environment: environment,
      workingDirectory: workingDirectory,
      executablePath: executablePath,
    );

    switch (lookup) {
      case BridgeLibraryMissing(:final List<String> tried):
        final RustCore absent = RustCore._(null, dataDir: dataDir);
        absent._searchedPaths = tried;
        return RustCoreNotAvailable(absent);
      case BridgeLibraryFound(:final String path):
        try {
          if (!_libraryInitialised) {
            // The override that `RustLib.init` actually offers: an
            // already-opened library, rather than a configuration this
            // generator-owned class does not accept.
            await RustLib.init(
              externalLibrary: ExternalLibrary.open(
                path,
                debugInfo: ' (mkvi_bridge loader, $path)',
              ),
            );
            _libraryInitialised = true;
          }
          final Core core = await openCore(dataDir: dataDir);
          return RustCoreOpened(RustCore._(core, dataDir: dataDir));
        } on Object {
          // A library that opens and then fails its content-hash or
          // codegen-version check lands here too, and it must read exactly like
          // "no library": from the app's side the core is equally unusable.
          return RustCoreNotAvailable(RustCore._(null, dataDir: dataDir));
        }
    }
  }
}
