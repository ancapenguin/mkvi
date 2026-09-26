/// Where the compiled Rust library is looked for, and how "it is not there" is
/// reported.
///
/// ## The decision, and why it is this one
///
/// The generated `frb_generated.dart` ships
/// `kDefaultExternalLibraryLoaderConfig(ioDirectory: '../target/release/')`, and
/// `flutter_rust_bridge` resolves that against **`Directory.current`** (measured:
/// `flutter_rust_bridge-2.13.0/lib/src/loader/_io.dart:18`,
/// `Directory.current.uri.resolve(ioDirectory)`). The current directory of a
/// Flutter application is whatever shell the developer happened to be in when
/// they typed `flutter run`. It is not a property of the application, so the
/// default cannot be used.
///
/// The three options that were on the table, and what happened to each:
///
/// * **(a) Hand `RustLib.init` an `ExternalLibraryLoaderConfig`.** Not possible
///   with flutter_rust_bridge 2.13.0. The generated `RustLib.init` takes exactly
///   `api`, `handler`, `externalLibrary` and `forceSameCodegenVersion`
///   (measured: `frb_generated.dart:23-35`); there is no `config` parameter, and
///   `defaultExternalLibraryLoaderConfig` is a getter on a `sealed`-by-convention
///   class the generator owns. The *intent* of (a) is reachable, but through
///   `externalLibrary`, not through a config.
/// * **(b) `rust_crate_flutter` / cargokit.** This is the correct **packaging**
///   answer and it should eventually be the one: it makes the Rust build part of
///   the Flutter build, so a release bundle carries the library without anybody
///   writing a path. It is not chosen here for two measured reasons. It adds a
///   build hook, so a Rust toolchain becomes a prerequisite of `flutter test` —
///   and the Dart CI job cannot be assumed to have one. And its effect is only
///   observable through `flutter build`, which this change was not allowed to
///   run, so choosing it would mean shipping an unverified mechanism. It is
///   recorded as the follow-up, not silently skipped.
/// * **(c) Resolve the path ourselves and open it.** Chosen. It is the only
///   option with **zero new dependencies**, it behaves identically on every
///   Flutter target, and — the load-bearing part — it lets the failure be
///   **caught and named** instead of escaping from inside a library initialiser.
///
/// The chosen shape is therefore (a)'s intent expressed with (c)'s mechanism:
/// [locateMkviBridgeLibrary] finds a file, and `RustCore` hands
/// `ExternalLibrary.open(path)` to `RustLib.init(externalLibrary: …)`.
///
/// ## Why the search is a list and not one path
///
/// There are three genuinely different places the library legitimately lives,
/// and no single one of them is right for all three situations:
///
/// 1. **A release bundle** - next to the executable, because that is where a
///    packager puts a dynamic library.
/// 2. **A development checkout** - `crates/mkvi_bridge/target/<profile>`, which
///    is a sibling of `app/`, not a child of it.
/// 3. **The `dart/bin/round_trip.dart` proof** in the bridge crate, whose
///    README documents running it from `crates/mkvi_bridge/dart`.
///
/// An explicit environment variable is checked first so a developer can point at
/// a build this search cannot guess (a cross-compiled one, a CI artifact, an
/// installed copy).
library;

import 'dart:io';

/// Names the library file outright, bypassing the search. An escape hatch, and
/// the only variable whose value is a file rather than a directory.
const String mkviBridgeLibraryEnvVar = 'MKVI_BRIDGE_DLL';

/// flutter_rust_bridge's own directory override. Honoured because it costs
/// nothing and because a developer who has already set it expects it to work.
const String frbNativeLibDirEnvVar = 'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR';

/// The library stem. Must be the Dart package name, the Rust `lib.name` and the
/// value `frb_generated.dart` carries; all three are `mkvi_bridge` today.
const String mkviBridgeLibraryStem = 'mkvi_bridge';

/// The file name this platform loads, without a directory.
///
/// Windows: `mkvi_bridge.dll`. macOS: `libmkvi_bridge.dylib`. Linux and Android:
/// `libmkvi_bridge.so` - Android's `lib` prefix is added by the loader, not
/// baked into the name, so the name is the same.
String mkviBridgeLibraryFileName() {
  if (Platform.isWindows) return '$mkviBridgeLibraryStem.dll';
  if (Platform.isMacOS || Platform.isIOS) return 'lib$mkviBridgeLibraryStem.dylib';
  return 'lib$mkviBridgeLibraryStem.so';
}

/// The outcome of the search. Two cases, and the second one is the normal state
/// of a CI Linux runner, so it is a value rather than an exception.
sealed class BridgeLibraryLookup {
  const BridgeLibraryLookup();

  /// Whether a loadable file was found. Does **not** mean the file loaded.
  bool get isFound => this is BridgeLibraryFound;
}

/// A candidate file exists.
final class BridgeLibraryFound extends BridgeLibraryLookup {
  const BridgeLibraryFound(this.path);

  /// The absolute path that was found.
  final String path;

  @override
  String toString() => 'BridgeLibraryFound($path)';
}

/// No candidate exists. [tried] is kept so the failure can be reported in full
/// instead of as "not found", which is the difference between a user who can
/// fix it and a user who restarts the app twice.
final class BridgeLibraryMissing extends BridgeLibraryLookup {
  const BridgeLibraryMissing(this.tried, {this.environmentPath});

  /// Every path that was checked, in order.
  final List<String> tried;

  /// The path the environment variable named, when it named one. Separated from
  /// [tried] because it is the one that was *meant* to be right.
  final String? environmentPath;

  /// One Turkish sentence saying what happened.
  ///
  /// User-visible, so Turkish: the whole point of catching this is that the
  /// person in front of the app is the one who can act on it.
  String get messageTr =>
      'Uygulamanın güvenlik çekirdeği yüklenemedi; MKVI verinizi şifreleyemiyor.';

  /// One Turkish sentence saying what to do about it.
  String get recoveryTr =>
      'Uygulamayı yeniden başlat. Sorun sürerse MKVI kurulumunu yeniden yap.';

  @override
  String toString() =>
      'BridgeLibraryMissing(${tried.length} aday, env: $environmentPath)';
}

/// Every directory that is searched, most specific first.
///
/// Split out from [locateMkviBridgeLibrary] so the *order* is a value a test can
/// read, rather than a side effect of the file system.
List<String> mkviBridgeLibraryCandidates({
  Map<String, String>? environment,
  String? workingDirectory,
  String? executablePath,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String cwd = workingDirectory ?? Directory.current.path;
  final List<String> directories = <String>[];

  void add(String? path) {
    if (path == null || path.isEmpty) return;
    if (!directories.contains(path)) directories.add(path);
  }

  // 1. Explicit, and it names a file rather than a directory.
  final String? explicit = env[mkviBridgeLibraryEnvVar];
  if (explicit != null && explicit.trim().isNotEmpty) {
    return <String>[explicit.trim()];
  }

  // 2. flutter_rust_bridge's own override, which is a directory.
  add(env[frbNativeLibDirEnvVar]);

  // 3. Beside the running executable, and its `lib/` subdirectory. This is the
  //    release-bundle case and the only one that survives being installed.
  if (executablePath != null && executablePath.isNotEmpty) {
    add(File(executablePath).parent.path);
    add('${File(executablePath).parent.path}${Platform.pathSeparator}lib');
  }

  // 4. The development checkout. `app/` is a sibling of `crates/`, so from
  //    there the bridge's build output is one level up.
  for (final String profile in <String>['release', 'debug']) {
    add(
      '$cwd${Platform.pathSeparator}..${Platform.pathSeparator}crates'
      '${Platform.pathSeparator}mkvi_bridge${Platform.pathSeparator}target'
      '${Platform.pathSeparator}$profile',
    );
  }

  // 5. Run from the repository root.
  for (final String profile in <String>['release', 'debug']) {
    add(
      '$cwd${Platform.pathSeparator}crates${Platform.pathSeparator}mkvi_bridge'
      '${Platform.pathSeparator}target${Platform.pathSeparator}$profile',
    );
  }

  // 6. What the generated default resolves to, kept so the bridge crate's own
  //    `round_trip.dart` proof keeps working unchanged.
  add('$cwd${Platform.pathSeparator}..${Platform.pathSeparator}target${Platform.pathSeparator}release');

  return directories;
}

/// The environment variable's value, or null. Separated so the report can name
/// it even though the candidate list stops being a list when it is set.
String? mkviBridgeExplicitLibraryPath({
  Map<String, String>? environment,
}) {
  final String? explicit = (environment ?? Platform.environment)[mkviBridgeLibraryEnvVar];
  final String trimmed = explicit?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Finds the library, or says where it looked.
///
/// Pure enough to test: pass [environment], [workingDirectory] and
/// [executablePath] and it touches nothing but those.
BridgeLibraryLookup locateMkviBridgeLibrary({
  Map<String, String>? environment,
  String? workingDirectory,
  String? executablePath,
  bool Function(String path)? exists,
}) {
  final bool Function(String) present = exists ?? _fileExists;
  final String name = mkviBridgeLibraryFileName();

  final String? explicit = mkviBridgeExplicitLibraryPath(environment: environment);
  if (explicit != null) {
    return present(explicit)
        ? BridgeLibraryFound(explicit)
        : BridgeLibraryMissing(
            <String>[explicit],
            environmentPath: explicit,
          );
  }

  final List<String> tried = <String>[];
  for (final String directory in mkviBridgeLibraryCandidates(
    environment: environment,
    workingDirectory: workingDirectory,
    executablePath: executablePath,
  )) {
    final String candidate = _join(directory, name);
    tried.add(candidate);
    if (present(candidate)) return BridgeLibraryFound(candidate);
  }
  return BridgeLibraryMissing(tried);
}

bool _fileExists(String path) => File(path).existsSync();

String _join(String directory, String name) {
  if (directory.endsWith(Platform.pathSeparator)) return '$directory$name';
  return '$directory${Platform.pathSeparator}$name';
}
