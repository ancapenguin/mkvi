/// The handoff to the platform installer.
///
/// A seam, and a narrow one on purpose. By the time anything is launched here,
/// two things have already happened: the bytes have been verified against the
/// release key, and they have been committed to their final name. The installer
/// is handed a file that is known good, or it is not called at all.
library;

import 'dart:io';

/// What the platform did with a verified artefact.
sealed class InstallOutcome {
  const InstallOutcome();
}

/// The installer was started. The application is expected to exit while it runs,
/// which is why this is a separate step rather than a download: a Windows
/// installer cannot replace the running executable.
final class InstallStarted extends InstallOutcome {
  const InstallStarted();

  @override
  String toString() => 'InstallStarted()';
}

/// The installer could not be started: the file is missing, the platform refused,
/// or the process died before it did anything. The file stays committed - it
/// verified, and a user who wants it can run it by hand.
final class InstallRefused extends InstallOutcome {
  const InstallRefused(this.detail);

  /// For a log line. Never shown: it may carry a path or an English platform
  /// message, and neither belongs in a notice.
  final String detail;

  @override
  String toString() => 'InstallRefused($detail)';
}

/// Hands a committed, verified artefact to the platform.
abstract class InstallerLauncher {
  /// Starts the installer for the file at [artifactPath].
  Future<InstallOutcome> launch(String artifactPath);
}

/// The production launcher: run the file.
///
/// The artefact is a plain installer, so the process is started detached and
/// this call does not wait for it: an installer that replaces the running
/// application cannot be waited on, and the app is expected to exit while it
/// runs. Nothing here is passed to the installer - no arguments, no flags, no
/// environment - because a verified file is already the whole job and anything
/// added to the command line is something a user cannot audit.
final class ProcessInstallerLauncher implements InstallerLauncher {
  const ProcessInstallerLauncher();

  @override
  Future<InstallOutcome> launch(String artifactPath) async {
    if (!Platform.isWindows) {
      return const InstallRefused('the desktop shell ships for Windows only');
    }
    final File file = File(artifactPath);
    if (!await file.exists()) {
      return InstallRefused('missing $artifactPath');
    }
    try {
      await Process.start(
        artifactPath,
        const <String>[],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return const InstallStarted();
    } on Object catch (error) {
      return InstallRefused('$error');
    }
  }
}
