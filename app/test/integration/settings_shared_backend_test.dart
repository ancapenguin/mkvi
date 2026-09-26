/// Two writers, two interfaces, one backend.
///
/// `SettingsController.setSelfName` and `SessionController.setSelfName` both
/// write `mkvi.selfName`, and if they write to two different stores then a user
/// who renames themselves in the settings screen keeps sending the old name to
/// the peer. That is ADR 0002's P0.3, and this suite measures the fix by
/// **reading**, not by asserting two string constants agree — the two
/// `SettingsKeys` classes repeat the literals on purpose, so their agreeing is not
/// evidence.
///
/// What is measured:
/// * a name written through the settings layer is what the session layer reads;
/// * a name written through the session layer is what the settings layer reads;
/// * the session controller's own `selfName` getter sees the settings layer's
///   write, after a real `bootstrap()`;
/// * both survive a process restart, because the file is the durable copy and
///   the sync `LocalSettings` read is served from it;
/// * a `void` write is still a durable write once the backend is idle.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/core/rust/file_settings.dart';
import 'package:mkvi/session/local_settings.dart';
import 'package:mkvi/session/session_controller.dart';
import 'package:mkvi/settings/appearance_resolver.dart';
import 'package:mkvi/settings/appearance_tokens_impl.dart';
import 'package:mkvi/settings/settings_controller.dart';
import 'package:mkvi/settings/settings_repository.dart';
import 'package:mkvi/settings/settings_store.dart' as settings_layer;
import '../support/fakes/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late FileSettingsBackend backend;
  late FileLocalSettings localSettings;
  late FileSettingsStore settingsStore;
  late SettingsController settings;
  late SessionController session;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mkvi-ayarlar');
    // TEK arka uç. İki arayüz, iki denetleyici, bir dosya.
    backend = FileSettingsBackend.openAt(directory);
    localSettings = FileLocalSettings(backend);
    settingsStore = FileSettingsStore(backend);

    settings = SettingsController(
      repository: SettingsRepository(settingsStore),
      resolver: AppearanceResolver(const DesignTokens()),
      platformBrightness: Brightness.light,
    );
    settings.load();

    session = SessionController(
      peerStore: FakePeerStore.absent(),
      settings: localSettings,
      identityLoader: FakeDeviceIdentityLoader(),
      rendezvousClientFactory: () => throw UnimplementedError(),
      verifyPairing: FakePairingVerifier(accept: true).call,
      transport: FakePeerTransport(),
      pairScopedDeviceId: FakePairScopedDeviceIdFactory().call,
      delay: ScriptedDelay().call,
    );
  });

  tearDown(() async {
    await session.dispose();
    // Dosya silinmeden önce bekleyen yazma bitmeli; aksi halde Windows açık
    // dosyayı silmeyi reddeder ve hata testin konusu değildir.
    await backend.idle;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('iki yazar da aynı anahtara yazıyor', () {
    // İki ayrı sabit, iki ayrı katman. Aynı olmaları bir tesadüf, ölçülmesi
    // gereken bir gerçek.
    expect(SettingsKeys.selfName, localSettingsKeysSelfName);
    expect(settings_layer.selfNameKey, localSettingsKeysSelfName);
  });

  test('ayarlar katmanından yazılan adı oturum katmanı OKUYOR', () async {
    await settings.setSelfName('Ayşe');
    await session.bootstrap();
    expect(session.selfName, 'Ayşe');
  });

  test('oturum katmanından yazılan adı ayarlar katmanı OKUYOR', () async {
    session.setSelfName('Kerem');
    settings.load();
    expect(settings.settings.selfName, 'Kerem');
  });

  test('iki yazar art arda çalışınca son yazan kazanıyor', () async {
    // Sıralama iki arka uçta ayrı ayrı doğru olsa da, tek dosyada yazma
    // sırasının korunması gerekir: `LocalSettings.write` `void` döndüğü için
    // yazma senkron değildir ve iki yazma birbirini ezebilir.
    session.setSelfName('Kerem');
    await settings.setSelfName('Ayşe');
    await session.bootstrap();
    expect(session.selfName, 'Ayşe');
    expect(localSettings.read(localSettingsKeysSelfName), 'Ayşe');
  });

  test('void yazma da kalıcıdır, arka uç boşta olduğunda', () async {
    session.setSelfName('Kerem');
    expect(localSettings.read(localSettingsKeysSelfName), 'Kerem',
        reason: 'bellek yazımı senkron olmalı, yoksa senkron okuma eskiyi görür');
    await backend.idle;
    expect(_storedName(directory.path), 'Kerem');
  });

  test('await edilen yazma tamamlandığında dosyada duruyor', () async {
    await settingsStore.write(localSettingsKeysSelfName, 'Ayşe');
    expect(_storedName(directory.path), 'Ayşe');
  });

  test('dosya bir süreç yeniden başlatmasını atlıyor', () async {
    await settings.setSelfName('Ayşe');
    // Yeni bir arka uç, aynı dizin: süreç yeniden başladı demek.
    final FileSettingsBackend reopened = FileSettingsBackend.openAt(directory);
    expect(reopened.read(localSettingsKeysSelfName), 'Ayşe');
    expect(
      FileLocalSettings(reopened).read(localSettingsKeysSelfName),
      'Ayşe',
    );
    expect(FileSettingsStore(reopened).read(
      localSettingsKeysSelfName,
    ), 'Ayşe');
  });

  test('sinyal sunucusu da tek arka uçta birleşiyor', () async {
    // `local_settings.dart:76-87` iki anahtarı bir birim olarak yazar; ayarlar
    // katmanı da aynı iki anahtarı ayrı ayrı yazar. Aynı dosya olmaları
    // gerekiyor, yoksa ayarlar ekranı yazdığı sunucu oturumun okuduğu
    // sunucudan farklı olur.
    expect(
      await settings.setEndpoint('https://sinyal.example', iceServersText: ''),
      isTrue,
    );
    session.saveConnectionSettings(
      endpoint: 'https://kendi.example',
      iceText: 'stun:stun.example:3478',
    );
    expect(readEndpoint(localSettings), 'https://kendi.example');
    settings.load();
    expect(
      settings.settings.connection.signalingEndpoint?.toString(),
      'https://kendi.example',
    );
  });

  test('olmayan anahtar null, hata DEĞİL', () {
    expect(localSettings.read('mkvi.yok'), isNull);
    expect(settingsStore.read('mkvi.yok'), isNull);
  });

  test('silmek iki arayüzde de aynı sonucu veriyor', () async {
    session.setSelfName('Kerem');
    await settingsStore.remove(localSettingsKeysSelfName);
    expect(localSettings.read(localSettingsKeysSelfName), isNull);
    await backend.idle;
    expect(_storedName(directory.path), isNull);
  });

  test('bir listeden başka bir şey olan dosya SESSİZCE SİLİNMİYOR', () {
    // Bozuk dosyayı varsayılanlarla değiştirmek, elle düzeltilmiş bir dosyada
    // her şeyi bir kerede kaybetmektir.
    File('${directory.path}${Platform.pathSeparator}$settingsFileName')
        .writeAsStringSync('[1, 2, 3]');
    expect(
      () => FileSettingsBackend.openAt(directory),
      throwsA(
        isA<FileSettingsCorrupt>().having(
          (FileSettingsCorrupt e) => e.message,
          'message',
          contains('okunamadı'),
        ),
      ),
    );
  });
}

/// `local_settings.dart`'ın kendi sabiti. `settings/settings_store.dart`
/// anahtarları bilerek tekrarlar, ve tekrarların aynı olması kanıt değil.
const String localSettingsKeysSelfName = SettingsKeys.selfName;

String? _storedName(String directoryPath) {
  final File file = File(
    '$directoryPath${Platform.pathSeparator}$settingsFileName',
  );
  if (!file.existsSync()) return null;
  final Object? decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) return null;
  final Object? value = decoded[localSettingsKeysSelfName];
  return value is String ? value : null;
}
