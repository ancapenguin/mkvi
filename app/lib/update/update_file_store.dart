/// Where downloaded bytes live, and when they are allowed to have a name.
///
/// The store is a seam because the interesting property of this layer is a
/// property of the *filesystem*: a partial download must never be something a
/// platform will launch. That is only testable against a real directory, so
/// `test/update/update_file_store_test.dart` drives [IoUpdateFileStore] on a
/// real temporary folder, and the client tests drive a fake that records the
/// order of operations.
library;

import 'dart:io';
import 'dart:typed_data';

import 'update_manifest.dart';

/// A staging file the update owns.
///
/// Immutable, and only meaningful to an [UpdateFileStore]. The bytes exist
/// nowhere else, and nothing outside this layer is handed a [path] until
/// [UpdateFileStore.commit] has promoted it.
final class StagedArtifact {
  const StagedArtifact({
    required this.path,
    required this.fileName,
    required this.byteLength,
  });

  /// The staging path. Its name always ends in `.part`, so no platform treats it
  /// as a runnable file however it is left behind.
  final String path;

  /// The name this artefact will have once committed.
  final String fileName;

  /// How many bytes have been written so far. The client keeps its own count as
  /// the authority; this is here so a store can refuse to be lied to.
  final int byteLength;

  /// The suffix that keeps a partial download unrunnable.
  static const String stagingExtension = '.part';

  @override
  String toString() => 'StagedArtifact($path, $fileName, $byteLength bytes)';
}

/// The filesystem side of an update: open, append, and either commit or delete.
///
/// The order is the whole design, and the interface is shaped so that it cannot
/// be got wrong from the outside:
///
/// * [openStaging] hands out a path that is not the final name.
/// * [append] is the only way bytes reach a file.
/// * [commit] is the only way a file gets its final name, and the client calls it
///   from exactly one place - after verification.
/// * [discard] is the other way out, and the client calls it from a `finally`, so
///   every failure path removes the partial file rather than remembering to.
///
/// There is deliberately no `findExisting(url)` and no read path. A download
/// cache keyed by URL is the hole this file is shaped to close: the bytes at
/// that URL are worth nothing until the release key has signed them, and a
/// lookup that answers "already have it" from the URL alone would skip the one
/// check that matters. [committedLength] exists only so a test can prove a failed
/// verification left nothing behind.
abstract class UpdateFileStore {
  /// Opens a fresh staging file for [offer]. Every call returns a new path.
  Future<StagedArtifact> openStaging(UpdateOffer offer);

  /// Appends [chunk] to [staging]. Called only while the stream is running.
  Future<void> append(StagedArtifact staging, List<int> chunk);

  /// Promotes a verified staging file to `<directory>/<fileName>` and returns the
  /// committed path.
  ///
  /// Replaces whatever was there: a committed file is a result, not a cache
  /// entry, and re-downloading the same version is expected to overwrite it.
  Future<String> commit(StagedArtifact staging);

  /// Removes a staging file. Never throws - it runs in a `finally`, and a
  /// cleanup that can fail the operation it is cleaning up after is worse than a
  /// leftover file.
  Future<void> discard(StagedArtifact staging);

  /// The committed path for [offer], whether or not anything is there.
  String committedPath(UpdateOffer offer);

  /// The size of the committed file, or null when there is none.
  Future<int?> committedLength(UpdateOffer offer);
}

/// The production store: one directory, real files.
///
/// The staging file is created in the *same* directory as the final file, for
/// two reasons. [File.rename] is only atomic within a volume, so a staging file
/// in the system temp directory would turn every commit into a copy, and a copy
/// is a window in which a half-written installer has its real name. A rename
/// within one directory is the atomic promotion this design depends on.
final class IoUpdateFileStore implements UpdateFileStore {
  IoUpdateFileStore(this.directory);

  /// The download directory. Created on first use.
  final String directory;

  int _attempts = 0;

  @override
  String committedPath(UpdateOffer offer) => '$directory/${offer.fileName}';

  @override
  Future<StagedArtifact> openStaging(UpdateOffer offer) async {
    await Directory(directory).create(recursive: true);
    _attempts += 1;
    final String path =
        '$directory/.${offer.fileName}.$_attempts${StagedArtifact.stagingExtension}';
    final File file = File(path);
    // Truncated, not appended: a staging file is only ever this attempt's.
    await file.writeAsBytes(const <int>[], flush: true);
    return StagedArtifact(path: path, fileName: offer.fileName, byteLength: 0);
  }

  @override
  Future<void> append(StagedArtifact staging, List<int> chunk) async {
    if (chunk.isEmpty) return;
    await File(staging.path).writeAsBytes(
      Uint8List.fromList(chunk),
      mode: FileMode.append,
      flush: false,
    );
  }

  @override
  Future<String> commit(StagedArtifact staging) async {
    final File source = File(staging.path);
    final String target = '$directory/${staging.fileName}';
    final File destination = File(target);
    // `rename` onto an existing file fails on Windows, and a re-download of the
    // same version has to land. The old file is removed first, which is the one
    // non-atomic moment here and the reason a failed update leaves no file at
    // all rather than a stale one.
    if (await destination.exists()) await destination.delete();
    await source.rename(target);
    return target;
  }

  @override
  Future<void> discard(StagedArtifact staging) async {
    try {
      final File file = File(staging.path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A file that cannot be deleted is not worth failing the update over, and
      // it is not runnable: it is still named `.part`.
    }
  }

  @override
  Future<int?> committedLength(UpdateOffer offer) async {
    final File file = File(committedPath(offer));
    if (!await file.exists()) return null;
    return file.length();
  }
}
