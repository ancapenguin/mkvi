/// The bridge must never be the reason the app dies.
///
/// This is the only one of the four suites that can pass on a machine with no
/// `mkvi_bridge` at all, and that is exactly its purpose: CI's Linux runner has no
/// compiled library, so if "no bridge" were an exception this suite could not run
/// there and the failure mode would only ever be discovered on a developer's
/// machine. The contract is therefore the whole of the test contract: **either the
/// real library, or explicitly the "no bridge" path, and nothing in between.** No
/// fake stands in for the bridge anywhere in this directory.
///
/// What is measured, with no library present:
/// * the search reports what it looked for, in Turkish, with a remedy;
/// * `RustCore.open` does not throw;
/// * the app reaches `SetupBroken`, not `SetupFirstRun` — the pairing screen must
///   not be reachable from a missing library, because that is the white pairing
///   screen all over again;
/// * no rejected transfer leaves a 0-byte file behind.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/file_sink.dart';
import 'package:mkvi/chat/history_store.dart';
import 'package:mkvi/chat/timeline_message.dart';
import 'package:mkvi/core/rust/rust_bridge_loader.dart';
import 'package:mkvi/core/rust/rust_core.dart';
import 'package:mkvi/core/rust/rust_file_sink.dart';
import 'package:mkvi/core/rust/rust_history_store.dart';
import 'package:mkvi/core/rust/rust_identity_loader.dart';
import 'package:mkvi/core/rust/rust_peer_store.dart';
import 'package:mkvi/session/peer_store.dart';
import 'package:mkvi/session/session_bootstrap.dart';
import 'package:mkvi/session/setup_state.dart';

/// A `RustCore` for a directory where the library is definitely absent.
///
/// The absence is *forced* by naming a file that does not exist through
/// `MKVI_BRIDGE_DLL`, so the result does not depend on whether this machine
/// happens to have `crates/mkvi_bridge/target/release` built. That is the point:
/// the "no bridge" path has to be reachable on purpose, not by accident.
Future<RustCore> openWithoutBridge(Directory temp) async {
  final RustCoreOpenResult result = await RustCore.open(
    dataDir: temp.path,
    environment: <String, String>{
      mkviBridgeLibraryEnvVar:
          '${temp.path}${Platform.pathSeparator}yok${Platform.pathSeparator}'
          '${mkviBridgeLibraryFileName()}',
    },
    workingDirectory: temp.path,
    executablePath: '${temp.path}${Platform.pathSeparator}mkvi.exe',
  );
  final RustCore core = (result as RustCoreNotAvailable).core;
  addTearDown(core.dispose);
  return core;
}

Directory newTempDirectory() =>
    Directory.systemTemp.createTempSync('mkvi-bridge-yok');

void main() {
  group('köprü arama sırası', () {
    test('isim, platformun beklediği dosya adıyla birleşiyor', () {
      // frb `_io.dart:60-92` yükleyicisinin `stem` + platform son eki
      // kombinasyonunun aynısı olmalı; değilse sessizce başka bir dosya aranır.
      final String name = mkviBridgeLibraryFileName();
      if (Platform.isWindows) {
        expect(name, 'mkvi_bridge.dll');
      } else if (Platform.isMacOS || Platform.isIOS) {
        expect(name, 'libmkvi_bridge.dylib');
      } else {
        expect(name, 'libmkvi_bridge.so');
      }
    });

    test('ortam değişkeni aday listesini tek yola indirgiyor', () {
      final List<String> candidates = mkviBridgeLibraryCandidates(
        environment: <String, String>{
          mkviBridgeLibraryEnvVar: '/opt/mkvi/libmkvi_bridge.so',
        },
        workingDirectory: r'C:\repo',
      );
      expect(candidates, <String>['/opt/mkvi/libmkvi_bridge.so']);
    });

    test('boş ortam değişkeni "belirtilmemiş" demek, "yok" değil', () {
      // Yoksa geliştirme build çıktısına düşülür; "yok" sayılırsa
      // geliştirici hiçbir zaman köprüyü bulamaz.
      final List<String> candidates = mkviBridgeLibraryCandidates(
        environment: <String, String>{mkviBridgeLibraryEnvVar: '  '},
        workingDirectory: r'C:\repo\app',
      );
      expect(candidates.length, greaterThan(1));
    });

    test('aday listesi çalışma dizinindeki geliştirme çıktısını içeriyor', () {
      final List<String> candidates = mkviBridgeLibraryCandidates(
        environment: const <String, String>{},
        workingDirectory: r'C:\repo\app',
      );
      // `app/` bir kardeşidir; köprünün build çıktısı bir seviye yukarıda.
      expect(
        candidates.any(
          (String c) => c.contains('mkvi_bridge') && c.endsWith('release'),
        ),
        isTrue,
        reason: 'geliştirme build çıktısı arama yolunda değil: $candidates',
      );
      // Üretilen varsayılan da korunur, böylece `round_trip.dart` çalışmaya devam eder.
      expect(
        candidates.last,
        endsWith('target${Platform.pathSeparator}release'),
      );
    });

    test('hiçbir aday yoksa Türkçe ve eyleme dönük bir hata veriyor', () {
      final BridgeLibraryLookup lookup = locateMkviBridgeLibrary(
        environment: const <String, String>{},
        workingDirectory: r'C:\yok',
        executablePath: r'C:\yok\mkvi.exe',
        exists: (String _) => false,
      );
      expect(lookup, isA<BridgeLibraryMissing>());
      final BridgeLibraryMissing missing = lookup as BridgeLibraryMissing;
      expect(missing.tried, isNotEmpty, reason: 'hiç bakılmamış demektir');
      expect(missing.messageTr, contains('güvenlik çekirdeği'));
      expect(missing.messageTr, contains('şifreleyemiyor'));
      expect(missing.recoveryTr, contains('yeniden başlat'));
    });

    test('bulunan dosya yalnız BULUND denir, "yüklendi" denmez', () {
      // `ExternalLibrary.open` ile gerçekten açılması ayrı bir adım; bu
      // fonksiyonun iddiası bu değil.
      final BridgeLibraryLookup lookup = locateMkviBridgeLibrary(
        environment: <String, String>{mkviBridgeLibraryEnvVar: r'C:\yok\a.dll'},
        exists: (String _) => true,
      );
      expect(lookup, isA<BridgeLibraryFound>());
      expect((lookup as BridgeLibraryFound).path, r'C:\yok\a.dll');
    });
  });

  group('köprü yokken RustCore', () {
    test('open fırlatmıyor, isAvailable false dönüyor', () async {
      final Directory temp = newTempDirectory();
      addTearDown(() => temp.deleteSync(recursive: true));
      final RustCore core = await openWithoutBridge(temp);

      expect(core.isAvailable, isFalse);
      expect(core.unavailableMessageTr, isNotNull);
      expect(core.unavailableRecoveryTr, isNotNull);
      expect(core.unavailableMessageTr, contains('şifreleyemiyor'));
      expect(core.unavailableRecoveryTr, contains('yeniden başlat'));
      expect(core.dataDir, temp.path);
    });

    test('requireCore Türkçe bir hata fırlatıyor', () async {
      final Directory temp = newTempDirectory();
      addTearDown(() => temp.deleteSync(recursive: true));
      final RustCore core = await openWithoutBridge(temp);

      expect(
        () => core.requireCore(),
        throwsA(
          isA<RustCoreUnavailable>().having(
            (RustCoreUnavailable e) => e.message,
            'message',
            contains('yeniden başlat'),
          ),
        ),
      );
    });

    test('aradığı yollar hatırlanıyor, dispose() temizliyor', () async {
      final Directory temp = newTempDirectory();
      addTearDown(() => temp.deleteSync(recursive: true));
      final RustCore core = await openWithoutBridge(temp);

      expect(core.searchedLibraryPaths, isNotEmpty);
      await core.dispose();
      expect(core.isAvailable, isFalse);
      expect(core.searchedLibraryPaths, isEmpty, reason: 'ikinci kez aranmaz');
    });
  });

  group('köprü yokken uygulama', () {
    test('SetupBroken düşüyor, eşleştirme ekranı DEĞİL', () async {
      final Directory temp = newTempDirectory();
      addTearDown(() => temp.deleteSync(recursive: true));
      final RustCore core = await openWithoutBridge(temp);

      // Gerçek `SessionBootstrap`, gerçek `RustPeerStore`. Sahte yok.
      final BootstrapOutcome outcome = await SessionBootstrap(
        RustPeerStore(core),
      ).restore();

      expect(outcome.state, isA<SetupBroken>());
      expect(outcome.state.showsPairingScreen, isFalse);
      expect(outcome.state.showsWorkspace, isFalse);
      expect(outcome.state.canRetry, isTrue);
      expect(outcome.peer, isNull);
      expect(
        (outcome.state as SetupBroken).failure,
        isA<PeerStoreUnavailable>(),
      );
      // Ekranda görünecek iki cümle de Türkçe ve eyleme dönük.
      expect(outcome.state.title, contains('açılamadı'));
      expect(outcome.state.detail, contains('yeniden başlat'));
    });

    test('eş deposu PeerAbsent DEMİYOR', () async {
      // `PeerAbsent` beyaz eşleştirme ekranının TEK yoludur; eksik köprü
      // oraya götürürse aynı hata geri gelir.
      final Directory temp = newTempDirectory();
      addTearDown(() => temp.deleteSync(recursive: true));
      final RustCore core = await openWithoutBridge(temp);

      final PeerReadResult result = await RustPeerStore(core).readPeer();
      expect(result, isA<PeerUnreadable>());
      expect(
        (result as PeerUnreadable).failure,
        isA<PeerStoreUnavailable>(),
      );
    });

    test('dosya lavabosu hiçbir şey açmıyor, 0 baytlık dosya bırakmıyor', () async {
      final Directory temp = newTempDirectory();
      addTearDown(() => temp.deleteSync(recursive: true));
      final RustCore core = await openWithoutBridge(temp);

      final Directory downloads = Directory(
        '${temp.path}${Platform.pathSeparator}indirilen',
      )..createSync(recursive: true);
      final RustFileSink sink = RustFileSink(
        directory: downloads.path,
        core: core,
      );

      await expectLater(
        sink.open(transferId: 't1', name: 'rapor.pdf', mime: 'application/pdf'),
        throwsA(
          isA<FileSinkException>().having(
            (FileSinkException e) => e.message,
            'message',
            contains('yeniden başlat'),
          ),
        ),
      );
      expect(sink.opened, isEmpty);
      expect(
        downloads.listSync().whereType<File>().toList(),
        isEmpty,
        reason: 'reddedilen her aktarım için 0 baytlık dosya bırakmak bu '
            'katmanın yazdığı asıl kusurdur',
      );
    });

    test('kimlik yükleyici fırlatıyor, yeni anahtar sessizce üretmiyor', () async {
      final Directory temp = newTempDirectory();
      addTearDown(() => temp.deleteSync(recursive: true));
      final RustCore core = await openWithoutBridge(temp);

      await expectLater(
        RustIdentityLoader(core).load(),
        throwsA(isA<RustCoreUnavailable>()),
      );
    });

    test('geçmiş deposu okumada boş sayfa döndürüyor, yazmada fırlatıyor', () async {
      final Directory temp = newTempDirectory();
      addTearDown(() => temp.deleteSync(recursive: true));
      final RustCore core = await openWithoutBridge(temp);
      final RustHistoryStore store = RustHistoryStore(core);

      final HistoryPage page = await store.loadNewest(
        conversationId: 'c-1',
        limit: 20,
      );
      expect(page.isEmpty, isTrue);
      expect(page.hasMore, isFalse);
      // Boş sayfa "geçmiş gerçekten boş" demektir, okunamadı demek değil. Bu
      // yüzden yazma fırlatıyor: okuma sessizce yalan söylemiyor.
      await expectLater(
        store.append(
          conversationId: 'c-1',
          message: StoredMessage(
            id: 'm-1',
            body: 'gizli',
            sentAt: DateTime.fromMillisecondsSinceEpoch(1),
            direction: MessageDirection.outgoing,
            delivery: MessageDelivery.sent,
          ),
        ),
        throwsA(isA<RustCoreUnavailable>()),
      );
    });
  });
}
