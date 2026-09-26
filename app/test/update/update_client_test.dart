// The flow, and the two properties that make it safe.
//
// 1. **A manifest an attacker controls must not be able to point at an unsigned
//    artefact.** The feed supplies a URL and a signature; the signature is
//    checked against the key compiled into the app, over the whole downloaded
//    file. So a fully rewritten feed can point anywhere and can only ever cause a
//    download of something that is not signed by the release key - which is then
//    never installed. Every test below that rewrites the feed asserts exactly
//    that.
// 2. **A partial download is never executable and never in the final location.**
//    Bytes go to a staging file whose name ends in `.part`, are counted by the
//    client as they arrive, and are promoted with a rename only after the
//    signature passes. Every failure path deletes the staging file in a
//    `finally`, so no branch has to remember to.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/update/update_client.dart';
import 'package:mkvi/update/update_config.dart';
import 'package:mkvi/update/update_fetcher.dart';
import 'package:mkvi/update/update_failure.dart';
import 'package:mkvi/update/update_file_store.dart';
import 'package:mkvi/update/update_installer.dart';
import 'package:mkvi/update/update_manifest.dart';
import 'package:mkvi/update/update_messages.dart';
import 'package:mkvi/update/update_verifier.dart';

import 'support/fakes.dart';

void main() {
  group('the happy path, end to end', () {
    test(
      'a newer release is offered, then verified, then installed once',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        harness.offerUpdate();

        final UpdateReport offered = await harness.client.check();
        expect(offered, isA<UpdateOffered>());
        final UpdateOffer offer = (offered as UpdateOffered).offer;
        expect(offer.version.toString(), offeredVersion);

        final UpdateReport installed = await harness.client.install(offer);
        expect(installed, isA<UpdateInstalled>());
        expect(
          (installed as UpdateInstalled).offer.version.toString(),
          offeredVersion,
        );
        expect(installed.message, UpdateMessage.installed.text);

        // Exactly once, and the path it was given is the committed one.
        expect(harness.installer.launches, 1);
        expect(
          harness.installer.launched.single,
          harness.files.committedPath(offer),
        );
      },
    );

    test(
      'the installer is invoked after verification and never before',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();

        await harness.client.install(offer);

        // The verification happened, on the whole file, before the launch.
        expect(harness.verifier.verified, hasLength(1));
        expect(
          harness.verifier.verified.single.byteLength,
          harness.artifact.length,
        );
        expect(
          harness.files.operations,
          containsAllInOrder(<String>['open', 'append', 'commit']),
        );
        expect(harness.files.operations, isNot(contains('discard')));
        expect(harness.installer.launches, 1);
      },
    );

    test('checkAndInstall does both, and the staging file is gone', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.offerUpdate();

      expect(await harness.client.checkAndInstall(), isA<UpdateInstalled>());
      expect(harness.installer.launches, 1);
      expect(harness.files.hasStagingFiles, isFalse);
      expect(harness.files.commits, 1);
    });

    test('the same or an older version is never offered', () async {
      for (final String version in <String>[
        currentVersion,
        '0.1.0',
        '$currentVersion-rc.1',
        '$currentVersion+build.9',
      ]) {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        harness.fetcher.feed = FeedReadOk(
          body: feedJson(version: version),
          declaredLength: null,
        );
        harness.fetcher.events = <DownloadEvent>[];

        final UpdateReport report = await harness.client.check();
        expect(report, isA<UpdateUpToDate>(), reason: 'version $version');
        expect(report.message, UpdateMessage.alreadyUpToDate.text);
        expect(
          harness.fetcher.downloadUrls,
          isEmpty,
          reason: 'nothing to download',
        );
        await harness.dispose();
      }
    });
  });

  group('an artefact whose signature does not verify is never installed', () {
    test(
      'a single flipped byte at the front, with the whole file rejected',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final List<int> tampered = harness.artifact;
        tampered[0] ^= 0x01;
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.offerUpdate(download: tampered);

        final UpdateReport report = await harness.client.install(offer);
        expect(
          harness.failureOf(report),
          isA<UpdateFailureSignatureRejected>(),
        );
        expect(report.message, UpdateMessage.signatureRejected.text);
        expect(harness.installer.launches, 0);
      },
    );

    test('a flipped byte in the MIDDLE, not just the first', () async {
      // The failure a prefix-only or windowed check would miss. The verifier is
      // handed a path, so there is no offset for a partial check to live in, and
      // the digest the fake compares covers every byte.
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      final List<int> tampered = harness.artifact;
      tampered[tampered.length ~/ 2] ^= 0xff;
      harness.offerUpdate(download: tampered);

      expect(
        harness.failureOf(await harness.client.install(offer)),
        isA<UpdateFailureSignatureRejected>(),
      );
      expect(harness.installer.launches, 0);
    });

    test(
      'a flipped byte in the LAST chunk, and the client still checked it all',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        final List<int> tampered = harness.artifact;
        tampered[tampered.length - 1] ^= 0x80;
        harness.offerUpdate(download: tampered);

        expect(
          harness.failureOf(await harness.client.install(offer)),
          isA<UpdateFailureSignatureRejected>(),
        );
        // The whole artefact was handed over, not the part that was intact.
        expect(harness.verifier.verified.single.byteLength, tampered.length);
        expect(harness.installer.launches, 0);
      },
    );

    test('an artefact truncated to its first chunk', () async {
      // A prefix is not the artefact. `verify_artifact` hashes the whole buffer,
      // and the length the client reports has to match what is on disk.
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      harness.offerUpdate(
        download: harness.artifact.sublist(0, 512),
        declaredLength: 512,
      );

      expect(
        harness.failureOf(await harness.client.install(offer)),
        isA<UpdateFailureSignatureRejected>(),
      );
      expect(harness.installer.launches, 0);
    });

    test(
      'an unreadable signature and a legacy key are each their own failure',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();

        harness.verifier.scripted = const ArtifactSignatureUnreadable();
        expect(
          harness.failureOf(await harness.client.install(offer)),
          isA<UpdateFailureSignatureUnreadable>(),
        );

        harness.verifier.scripted = const ArtifactKeyIsLegacy();
        expect(
          harness.failureOf(await harness.client.install(offer)),
          isA<UpdateFailureLegacyKey>(),
        );

        expect(harness.installer.launches, 0);
      },
    );

    test(
      'a bridge that throws has verified nothing, so nothing is installed',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.verifier.throwsOnVerify = StateError('bridge yok');

        expect(
          harness.failureOf(await harness.client.install(offer)),
          isA<UpdateFailureVerificationUnavailable>(),
        );
        expect(harness.installer.launches, 0);
        expect(harness.files.hasStagingFiles, isFalse);
      },
    );
  });

  group('a failed verification leaves nothing behind', () {
    test('no committed file, and the staging file is deleted', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      final List<int> tampered = harness.artifact;
      tampered[100] ^= 0x01;
      harness.offerUpdate(download: tampered);

      await harness.client.install(offer);

      expect(await harness.files.committedLength(offer), isNull);
      expect(harness.files.committed, isEmpty);
      expect(harness.files.hasStagingFiles, isFalse);
      expect(harness.files.operations.last, 'discard');
      expect(harness.files.operations, isNot(contains('commit')));
    });

    test('the staging path a verifier is given is not the final name', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();

      await harness.client.install(offer);

      // The verifier was pointed at a `.part` file, and the installer at a name
      // that does not end in one. Nothing ever runs off the staging path.
      final String verifiedPath = harness.verifier.verified.single.path;
      expect(verifiedPath, endsWith(StagedArtifact.stagingExtension));
      expect(verifiedPath, isNot(harness.files.committedPath(offer)));
      expect(
        harness.installer.launched.single,
        isNot(endsWith(StagedArtifact.stagingExtension)),
      );
    });
  });

  group('an oversized stream is aborted and the partial file is removed', () {
    test('a stream that ignores the cap still cannot fill the disk', () async {
      final UpdateHarness harness = UpdateHarness(artifactMaxBytes: 2048);
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      // Four kilobytes through a two kilobyte cap, in 512 byte chunks, with no
      // `DownloadLimitReached` anywhere: the transport is behaving badly and the
      // client has to notice by itself.
      harness.fetcher.events = <DownloadEvent>[
        DownloadAnnounced(4096),
        ...chunksOf(harness.artifact, 512).map(DownloadChunk.new),
        DownloadComplete(4096),
      ];

      final UpdateReport report = await harness.client.install(offer);
      expect(harness.failureOf(report), isA<UpdateFailureArtifactTooLarge>());
      expect(report.message, UpdateMessage.artifactTooLarge.text);

      // Aborted, not merely stopped.
      expect(harness.fetcher.tokens.last.isAborted, isTrue);
      // The stream was cut short rather than drained.
      expect(harness.fetcher.chunksDelivered, lessThan(8));
      // Nothing on disk at all, in either place.
      expect(harness.files.hasStagingFiles, isFalse);
      expect(await harness.files.committedLength(offer), isNull);
      expect(harness.installer.launches, 0);
    });

    test('the crossing chunk is never written', () async {
      final UpdateHarness harness = UpdateHarness(artifactMaxBytes: 1024);
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      harness.fetcher.events = <DownloadEvent>[
        DownloadAnnounced(null),
        DownloadChunk(List<int>.filled(1024, 1)),
        DownloadChunk(List<int>.filled(512, 2)),
        DownloadComplete(1536),
      ];

      expect(
        harness.failureOf(await harness.client.install(offer)),
        isA<UpdateFailureArtifactTooLarge>(),
      );
      // One append of 1024 bytes, and nothing for the chunk that crossed the cap.
      final int appended = harness.files.operations
          .where((String op) => op == 'append')
          .length;
      expect(appended, 1);
    });

    test(
      'a server that announces more than the cap is refused before any byte',
      () async {
        final UpdateHarness harness = UpdateHarness(artifactMaxBytes: 1024);
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.fetcher.events = <DownloadEvent>[
          DownloadAnnounced(50 * 1024 * 1024),
          ...chunksOf(harness.artifact, 512).map(DownloadChunk.new),
          DownloadComplete(50 * 1024 * 1024),
        ];

        expect(
          harness.failureOf(await harness.client.install(offer)),
          isA<UpdateFailureArtifactTooLarge>(),
        );
        expect(
          harness.fetcher.chunksDelivered,
          0,
          reason: 'nothing was read at all',
        );
        expect(harness.files.hasStagingFiles, isFalse);
      },
    );

    test(
      'a transport that stops itself at the cap reports the same failure',
      () async {
        final UpdateHarness harness = UpdateHarness(artifactMaxBytes: 1024);
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.fetcher.events = <DownloadEvent>[
          DownloadAnnounced(1024),
          DownloadChunk(List<int>.filled(1024, 7)),
          const DownloadLimitReached(),
        ];

        expect(
          harness.failureOf(await harness.client.install(offer)),
          isA<UpdateFailureArtifactTooLarge>(),
        );
        expect(harness.installer.launches, 0);
      },
    );
  });

  group('a manifest an attacker controls still cannot reach the installer', () {
    test('a rewritten url with a signature that does not verify', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      // The attack: serve a feed pointing at a payload the attacker hosts, with
      // the real release's signature attached. The URL is followed - there is no
      // reason not to - and the bytes are then refused.
      harness.fetcher.feed = FeedReadOk(
        body: feedJson(url: 'https://evil.example.invalid/payload.exe'),
        declaredLength: null,
      );
      harness.fetcher.events = artifactEvents(harness.artifact);
      harness.verifier.signedDigest = digest64(<int>[0xde, 0xad, 0xbe, 0xef]);

      final UpdateReport offered = await harness.client.check();
      expect(offered, isA<UpdateOffered>());
      final UpdateReport report = await harness.client.install(
        (offered as UpdateOffered).offer,
      );

      expect(harness.failureOf(report), isA<UpdateFailureSignatureRejected>());
      expect(
        harness.fetcher.downloadUrls.single.toString(),
        contains('evil.example.invalid'),
      );
      expect(harness.installer.launches, 0);
    });

    test(
      'a feed that swaps the key as well is still pinned to the configured one',
      () async {
        // Nothing in the feed can change which key is used: the key comes from
        // `UpdateConfig`, and the fake records every one it was handed.
        final UpdateHarness harness = UpdateHarness(publicKey: prehashedKey);
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();

        await harness.client.install(offer);

        expect(harness.verifier.classifiedKeys, everyElement(prehashedKey));
        expect(harness.verifier.verified.single.key, prehashedKey);
      },
    );

    test(
      'a feed that is not the pinned manifest stops before any download',
      () async {
        final List<int> pinned = feedJson(version: '0.2.1');
        final UpdateHarness harness = UpdateHarness(pinnedManifest: pinned);
        addTearDown(harness.dispose);
        harness.fetcher.feed = FeedReadOk(
          body: feedJson(
            version: '9.9.9',
            url: 'https://evil.example.invalid/x.exe',
          ),
          declaredLength: null,
        );
        harness.fetcher.events = artifactEvents(harness.artifact);

        final UpdateReport report = await harness.client.check();
        expect(harness.failureOf(report), isA<UpdateFailureFeedPinMismatch>());
        expect(report.message, UpdateMessage.feedPinMismatch.text);
        expect(harness.fetcher.downloadUrls, isEmpty);
        expect(harness.installer.launches, 0);
      },
    );

    test('a feed that matches the pin byte for byte is accepted', () async {
      final List<int> pinned = feedJson(version: '0.2.1');
      final UpdateHarness harness = UpdateHarness(pinnedManifest: pinned);
      addTearDown(harness.dispose);
      harness.fetcher.feed = FeedReadOk(
        body: pinned,
        declaredLength: pinned.length,
      );

      expect(await harness.client.check(), isA<UpdateOffered>());
    });
  });

  group('a committed artefact is never reused because a url matched', () {
    // The cache-shaped hole: "we already have that file" is an answer about a
    // URL, and a URL says nothing about whether the bytes are signed. There is no
    // lookup in the store at all, so the second install downloads and verifies
    // from scratch.
    test('installing twice downloads and verifies twice', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();

      expect(await harness.client.install(offer), isA<UpdateInstalled>());
      expect(await harness.client.install(offer), isA<UpdateInstalled>());

      expect(harness.fetcher.downloadUrls, hasLength(2));
      expect(harness.verifier.verified, hasLength(2));
      expect(harness.installer.launches, 2);
    });

    test(
      'an artefact that was tampered with after committing is re-verified',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        await harness.client.install(offer);
        // Something rewrote the file on disk between the two attempts.
        final String path = harness.files.committedPath(offer);
        harness.files.committed[path] = <int>[0, 1, 2, 3];
        harness.fetcher.events = <DownloadEvent>[
          DownloadAnnounced(4),
          DownloadChunk(<int>[0, 1, 2, 3]),
          DownloadComplete(4),
        ];

        expect(
          harness.failureOf(await harness.client.install(offer)),
          isA<UpdateFailureSignatureRejected>(),
        );
      },
    );
  });

  group('the feed itself', () {
    test('a 404 is unreachable, not a malformed manifest', () async {
      // A release with no artefact attached to it, and the everyday answer of
      // 0.1.x: a feed nobody could read answered 404 forever. Either way it is a
      // transport failure, and the address asked is the release endpoint.
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.fetcher.feed = const FeedReadFailed('http 404');

      final UpdateReport report = await harness.client.check();
      expect(harness.failureOf(report), isA<UpdateFailureFeedUnreachable>());
      expect(report.message, UpdateMessage.feedUnreachable.text);
      expect(harness.fetcher.readUrls.single, releaseFeedUrl);
      expect(
        harness.fetcher.downloadUrls,
        isEmpty,
        reason: 'nothing to download from a feed that was not there',
      );
    });

    test('and the release endpoint is the only one a shipped build reads', () async {
      // The harness default is the production address, so every other test in
      // this file is already asking the same question. Asserted once, here, so
      // a change to the address cannot pass quietly through the rest.
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.fetcher.feed = const FeedReadOk(body: <int>[0x6e], declaredLength: null);

      await harness.client.check();
      expect(harness.fetcher.readUrls, <Uri>[releaseFeedUrl]);
    });

    test('a transport that throws is unreachable, not a crash', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.fetcher.readThrows = StateError('socket kapandı');

      expect(
        harness.failureOf(await harness.client.check()),
        isA<UpdateFailureFeedUnreachable>(),
      );
    });

    test('a malformed feed is an error, not an upgrade', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.fetcher.feed = const FeedReadOk(
        body: <int>[0x6e, 0x6f],
        declaredLength: null,
      );

      expect(
        harness.failureOf(await harness.client.check()),
        isA<UpdateFailureFeedUnreadable>(),
      );
      expect(harness.fetcher.downloadUrls, isEmpty);
      expect(harness.installer.launches, 0);
    });

    test('a feed past the manifest cap is refused', () async {
      final UpdateHarness harness = UpdateHarness(manifestMaxBytes: 64);
      addTearDown(harness.dispose);
      harness.fetcher.feed = const FeedReadTooLarge();

      expect(
        harness.failureOf(await harness.client.check()),
        isA<UpdateFailureFeedTooLarge>(),
      );
    });

    test(
      'a body past the cap is refused even when the transport says otherwise',
      () async {
        final UpdateHarness harness = UpdateHarness(manifestMaxBytes: 64);
        addTearDown(harness.dispose);
        // The transport hands back a complete, well formed feed and claims it is
        // fine. The client counted it itself and refuses.
        harness.fetcher.feed = FeedReadOk(
          body: feedJson(),
          declaredLength: null,
        );

        expect(
          harness.failureOf(await harness.client.check()),
          isA<UpdateFailureFeedTooLarge>(),
        );
      },
    );

    test(
      'a body shorter than its own content-length is unreadable, not a feed',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        harness.fetcher.feed = FeedReadOk(
          body: feedJson(),
          declaredLength: 9999,
        );

        expect(
          harness.failureOf(await harness.client.check()),
          isA<UpdateFailureFeedUnreadable>(),
        );
      },
    );

    test(
      'the caps the client hands the transport are the configured ones',
      () async {
        final UpdateHarness harness = UpdateHarness(
          manifestMaxBytes: 1024,
          artifactMaxBytes: 4096,
        );
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();

        await harness.client.install(offer);

        expect(harness.fetcher.readCaps.single, 1024);
        expect(harness.fetcher.downloadCaps.single, 4096);
      },
    );
  });

  group('the artefact transfer', () {
    test(
      'a stream that stops without saying it finished is a failed download',
      () async {
        // The end of a stream is not a completed download. Treating it as one is
        // how a truncated installer becomes an installer.
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.fetcher.events = <DownloadEvent>[
          DownloadAnnounced(4096),
          DownloadChunk(harness.artifact.sublist(0, 1024)),
        ];

        expect(
          harness.failureOf(await harness.client.install(offer)),
          isA<UpdateFailureDownloadFailed>(),
        );
        expect(harness.files.hasStagingFiles, isFalse);
        expect(harness.installer.launches, 0);
      },
    );

    test(
      'a declared length that does not match the bytes is refused',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.fetcher.events = <DownloadEvent>[
          DownloadAnnounced(4096),
          ...chunksOf(harness.artifact, 512).map(DownloadChunk.new),
          DownloadComplete(2048),
        ];

        expect(
          harness.failureOf(await harness.client.install(offer)),
          isA<UpdateFailureArtifactSizeMismatch>(),
        );
        expect(harness.installer.launches, 0);
      },
    );

    test('an empty download is empty, not tampered with', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      harness.fetcher.events = <DownloadEvent>[
        DownloadAnnounced(0),
        DownloadComplete(0),
      ];

      final UpdateFailure failure = harness.failureOf(
        await harness.client.install(offer),
      );
      expect(failure, isA<UpdateFailureArtifactEmpty>());
      expect(
        failure,
        isNot(isA<UpdateFailureSignatureRejected>()),
        reason: 'nothing arrived; nobody modified anything',
      );
    });

    test('a transport that throws mid-stream leaves nothing on disk', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      harness.fetcher.downloadThrows = StateError('bağlantı koptu');

      expect(
        harness.failureOf(await harness.client.install(offer)),
        isA<UpdateFailureDownloadFailed>(),
      );
      expect(harness.files.hasStagingFiles, isFalse);
      expect(harness.installer.launches, 0);
    });

    test('an abort stops the transfer and the file', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      harness.fetcher.events = <DownloadEvent>[
        DownloadAnnounced(4096),
        ...chunksOf(harness.artifact, 512).map(DownloadChunk.new),
        DownloadComplete(4096),
      ];
      // A user pressing cancel after two chunks. Driven from the transport seam
      // so the point in the stream is exact rather than a matter of timing.
      harness.fetcher.beforeEvent = (int index) {
        if (index == 2) harness.client.abort();
      };

      final UpdateReport report = await harness.client.install(offer);
      expect(harness.failureOf(report), isA<UpdateFailureAborted>());
      expect(report.message, UpdateMessage.aborted.text);
      expect(harness.fetcher.tokens.last.isAborted, isTrue);
      expect(
        harness.fetcher.chunksDelivered,
        2,
        reason: 'the stream really stopped',
      );
      expect(harness.files.hasStagingFiles, isFalse);
      expect(await harness.files.committedLength(offer), isNull);
      expect(harness.installer.launches, 0);
    });
  });

  group('the install handoff', () {
    test(
      'an installer that refuses leaves the verified file in place',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.installer.outcome = const InstallRefused('blocked by policy');

        final UpdateReport report = await harness.client.install(offer);
        expect(harness.failureOf(report), isA<UpdateFailureInstallFailed>());
        expect(report.message, UpdateMessage.installFailed.text);
        // The bytes verified, so they are kept: a user can run this one by hand.
        expect(
          await harness.files.committedLength(offer),
          harness.artifact.length,
        );
        expect(harness.installer.launches, 1);
      },
    );

    test(
      'an installer that throws is an install failure, not a crash',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.installer.throwsOnLaunch = StateError('yok');

        expect(
          harness.failureOf(await harness.client.install(offer)),
          isA<UpdateFailureInstallFailed>(),
        );
      },
    );

    test(
      'a download directory that cannot be written is its own failure',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.files.throwOnOpen = StateError('disk full');

        final UpdateReport report = await harness.client.install(offer);
        expect(
          harness.failureOf(report),
          isA<UpdateFailureStorageUnavailable>(),
        );
        expect(report.message, UpdateMessage.storageUnavailable.text);
        expect(harness.installer.launches, 0);
      },
    );
  });

  group('the check throttle', () {
    test(
      'a second check inside the interval is deferred, not repeated',
      () async {
        final UpdateHarness harness = UpdateHarness(
          minCheckInterval: const Duration(hours: 6),
        );
        addTearDown(harness.dispose);
        harness.offerUpdate();

        expect(await harness.client.check(), isA<UpdateOffered>());
        harness.clock.advance(const Duration(hours: 1));

        final UpdateReport second = await harness.client.check();
        expect(second, isA<UpdateCheckDeferred>());
        expect(
          (second as UpdateCheckDeferred).retryIn,
          const Duration(hours: 5),
        );
        expect(second.message, UpdateMessage.checkDeferred.text);
        expect(
          harness.fetcher.readUrls,
          hasLength(1),
          reason: 'the feed was not re-read',
        );
      },
    );

    test(
      'the interval is measured on the injected clock, not on a timer',
      () async {
        final UpdateHarness harness = UpdateHarness(
          minCheckInterval: const Duration(hours: 6),
        );
        addTearDown(harness.dispose);
        harness.offerUpdate();
        await harness.client.check();

        harness.clock.advance(const Duration(hours: 5, minutes: 59));
        expect(await harness.client.check(), isA<UpdateCheckDeferred>());

        harness.clock.advance(const Duration(minutes: 1));
        expect(await harness.client.check(), isA<UpdateOffered>());
      },
    );

    test('a check that never reached the server does not throttle', () async {
      // Somebody whose train arrived should be able to press the button again.
      final UpdateHarness harness = UpdateHarness(
        minCheckInterval: const Duration(hours: 6),
      );
      addTearDown(harness.dispose);
      harness.fetcher.feed = const FeedReadFailed('offline');
      expect(
        harness.failureOf(await harness.client.check()),
        isA<UpdateFailureFeedUnreachable>(),
      );

      harness.offerUpdate();
      expect(await harness.client.check(), isA<UpdateOffered>());
    });

    test(
      'the preflight is never throttled, because it fetches nothing',
      () async {
        final UpdateHarness harness = UpdateHarness(
          minCheckInterval: const Duration(hours: 6),
        );
        addTearDown(harness.dispose);
        expect(await harness.client.preflight(), isA<UpdatePreflightOk>());
        expect(await harness.client.preflight(), isA<UpdatePreflightOk>());
        expect(harness.fetcher.requests, 0);
        expect(harness.clock.reads, greaterThanOrEqualTo(2));
      },
    );
  });

  group('the progress stream', () {
    test(
      'reports progress, then verification, then the install handoff',
      () async {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();

        await harness.client.install(offer);
        await harness.settle();

        final List<UpdateDownloadProgress> progress = harness
            .eventsOf<UpdateDownloadProgress>();
        expect(progress, isNotEmpty);
        expect(progress.last.received, harness.artifact.length);
        expect(progress.last.total, harness.artifact.length);
        expect(harness.eventsOf<UpdateArtifactVerified>(), hasLength(1));
        expect(
          harness.eventsOf<UpdateArtifactVerified>().single.byteLength,
          harness.artifact.length,
        );
        expect(harness.eventsOf<UpdateInstallStarted>(), hasLength(1));
      },
    );

    test('reports the offer when the feed names one', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.offerUpdate();

      await harness.client.check();
      await harness.settle();

      expect(harness.eventsOf<UpdateCheckStarted>(), hasLength(1));
      expect(
        harness.eventsOf<UpdateOfferFound>().single.offer.version.toString(),
        offeredVersion,
      );
    });

    test('never carries a key, a url or a path', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.offerUpdate();
      await harness.client.checkAndInstall();
      await harness.settle();

      for (final UpdateEvent event in harness.events) {
        final String text = event.toString();
        expect(text, isNot(contains(prehashedKey)));
        expect(text, isNot(contains('evil.example.invalid')));
        expect(text, isNot(contains('C:/downloads')));
      }
    });
  });
}
