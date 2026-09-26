// The filesystem rules, against a real directory.
//
// "A partial download must never be executable" is a claim about files, so this
// file uses real files. Everything else about the update is faked - no network, no
// key, no clock - but the thing under test is `File.rename`, `FileMode.append`
// and what a name ending in `.part` means to a platform.
//
// The client's own ordering is tested with the in-memory store in
// `update_client_test.dart`; this is the part a fake cannot vouch for.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/update/update_file_store.dart';
import 'package:mkvi/update/update_manifest.dart';
import 'package:mkvi/update/update_version.dart';

import 'support/fakes.dart';

void main() {
  late Directory directory;
  late IoUpdateFileStore store;
  late UpdateOffer offer;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mkvi-update-store-');
    store = IoUpdateFileStore(directory.path);
    final UpdateManifest parsed = parseUpdateManifest(
      feedJson(url: 'https://releases.example.invalid/mkvi-setup.exe'),
      ReleaseVersion.tryParse(currentVersion)!,
    );
    offer = (parsed as ManifestOffersRelease).offer;
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  List<String> namesIn() =>
      directory
          .listSync()
          .map(
            (FileSystemEntity e) => e.path.split(Platform.pathSeparator).last,
          )
          .toList()
        ..sort();

  test('the final path is the artefact name, in the download directory', () {
    expect(store.committedPath(offer), endsWith('mkvi-setup.exe'));
    expect(store.committedPath(offer), startsWith(directory.path));
  });

  test('a staging file is created with a name nothing would run', () async {
    final StagedArtifact staging = await store.openStaging(offer);

    // The whole claim in one assertion: whatever happens next, this file is not
    // an installer, and it is not the name the installer will be handed.
    expect(staging.path, endsWith(StagedArtifact.stagingExtension));
    expect(staging.path, isNot(store.committedPath(offer)));
    expect(staging.fileName, 'mkvi-setup.exe');
    expect(File(staging.path).existsSync(), isTrue);
  });

  test('every staging file is a different file', () async {
    // Two attempts in the same millisecond must not share a path, or the second
    // would append to the first one's leftovers.
    final StagedArtifact first = await store.openStaging(offer);
    final StagedArtifact second = await store.openStaging(offer);
    expect(first.path, isNot(second.path));
    expect(namesIn(), hasLength(2));
  });

  test(
    'appends accumulate, and nothing is written under the final name',
    () async {
      final StagedArtifact staging = await store.openStaging(offer);
      await store.append(staging, <int>[1, 2, 3]);
      await store.append(staging, <int>[4, 5]);

      expect(File(staging.path).readAsBytesSync(), <int>[1, 2, 3, 4, 5]);
      expect(File(store.committedPath(offer)).existsSync(), isFalse);
      expect(await store.committedLength(offer), isNull);
    },
  );

  test('an empty append writes nothing', () async {
    final StagedArtifact staging = await store.openStaging(offer);
    await store.append(staging, const <int>[]);
    expect(File(staging.path).lengthSync(), 0);
  });

  test('a commit renames into place and leaves no staging file', () async {
    final StagedArtifact staging = await store.openStaging(offer);
    await store.append(staging, <int>[7, 7, 7]);

    final String path = await store.commit(staging);

    expect(path, store.committedPath(offer));
    expect(File(path).readAsBytesSync(), <int>[7, 7, 7]);
    expect(File(staging.path).existsSync(), isFalse);
    expect(namesIn(), <String>['mkvi-setup.exe']);
  });

  test('a re-download of the same version replaces the committed file', () async {
    // `File.rename` onto an existing file fails on Windows, so this is the case
    // that would break on the platform this product ships on.
    final StagedArtifact first = await store.openStaging(offer);
    await store.append(first, <int>[1]);
    await store.commit(first);

    final StagedArtifact second = await store.openStaging(offer);
    await store.append(second, <int>[2, 2]);
    await store.commit(second);

    expect(File(store.committedPath(offer)).readAsBytesSync(), <int>[2, 2]);
    expect(namesIn(), <String>['mkvi-setup.exe']);
  });

  test('a discard removes the partial file', () async {
    final StagedArtifact staging = await store.openStaging(offer);
    await store.append(staging, List<int>.filled(2048, 0xab));

    await store.discard(staging);

    expect(File(staging.path).existsSync(), isFalse);
    expect(File(store.committedPath(offer)).existsSync(), isFalse);
    expect(await store.committedLength(offer), isNull);
    expect(namesIn(), isEmpty);
  });

  test('a discard of a file that is already gone does not throw', () async {
    // It runs in a `finally`. A cleanup that can fail the operation it is
    // cleaning up after is worse than a leftover file.
    final StagedArtifact staging = await store.openStaging(offer);
    await File(staging.path).delete();
    await expectLater(store.discard(staging), completes);
    await expectLater(store.discard(staging), completes);
  });

  test('the download directory is created on first use', () async {
    // A fresh install has no downloads folder yet, and refusing to update because
    // of that would be its own silent failure.
    final String nested = '${directory.path}${Platform.pathSeparator}alt';
    final IoUpdateFileStore nestedStore = IoUpdateFileStore(nested);
    expect(Directory(nested).existsSync(), isFalse);

    final StagedArtifact staging = await nestedStore.openStaging(offer);
    await nestedStore.append(staging, <int>[1]);
    final String path = await nestedStore.commit(staging);

    expect(File(path).readAsBytesSync(), <int>[1]);
  });
}
