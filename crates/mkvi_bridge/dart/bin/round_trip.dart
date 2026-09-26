// Gidiş-dönüş kanıtı: üretilmiş Dart API'yi gerçekten çağırır ve bir değer
// basar. Elle bir şey yazmaz — buradaki her çağrı `dart/lib/src/rust/api.dart`
// içindeki üretilmiş imzalara karşılık gelir, yani imzalar yanlışsa bu dosya
// derlenmez.
//
// Çalıştırmak için `crates/mkvi_bridge/dart` dizininden:
//
//   cargo build --release --manifest-path ../Cargo.toml
//   dart run bin/round_trip.dart
//
// Konum önemli: üretilmiş yükleyici `../target/release/` dizinini çalışma
// dizinine göre çözer (ExternalLibraryLoaderConfig.ioDirectory), yani buradan
// çalıştırınca `crates/mkvi_bridge/target/release/mkvi_bridge.dll` bulunur.

import 'dart:io';

import 'package:mkvi_bridge/src/rust/api.dart';
import 'package:mkvi_bridge/src/rust/error.dart';
import 'package:mkvi_bridge/src/rust/frb_generated.dart';

/// Çıktının tamamı Türkçe: bu kanıt, kullanıcının göreceği metnin köprüde
/// bozulmadığını da göstermek için var.
Future<void> main() async {
  await RustLib.init();

  final dataDir = Directory.systemTemp.createTempSync('mkvi-bridge-');
  try {
    // 1. Kurucu. Altı adet üretilmiş çağrıdan ilki.
    final core = await openCore(dataDir: dataDir.path);
    print('veri dizini açıldı: ${dataDir.path}');

    // 2. Kimlik. Anahtar açıklamada söylendiği gibi 43 karakter.
    final publicKey = await devicePublicKey(core: core);
    print('cihaz anahtarı: $publicKey (${publicKey.length} karakter)');

    // 3. İmza ve doğrulama. `message` Dart'ta bayt listesi, Rust'ta &[u8].
    final message = <int>[...'mkvi/bridge-round-trip/v1'.codeUnits];
    final signature = await sign(core: core, message: message);
    final verified = await verify(
      publicKey: publicKey,
      message: message,
      signature: signature,
    );
    final tampered = await verify(
      publicKey: publicKey,
      message: <int>[...'mkvi/bridge-round-trip/v2'.codeUnits],
      signature: signature,
    );
    print('imza doğrulandı: $verified, değiştirilmiş mesaj: $tampered');
    print('imza: $signature (${signature.length} karakter)');

    // 4. Şifreli geçmiş: yaz, sonra oku.
    await appendHistory(
      core: core,
      message: HistoryMessage(
        id: 'm-1',
        conversationId: 'c-1',
        senderDeviceId: 'd-1',
        sentAtMs: 42,
        body: 'gizli mesaj',
      ),
    );
    final history = await listHistory(core: core, limit: 10);
    print('geçmiş: ${history.length} kayıt, ilk gövde: "${history.first.body}"');

    // 5. Eş. `discovery_id` 43 karakter olmak zorunda.
    await rememberPeer(
      core: core,
      peer: KnownPeer(
        publicKey: 'test-public-key',
        discoveryId: 'A' * 43,
        displayName: 'Kuzenim',
        pairedAtMs: 7,
      ),
    );
    final peers = await listPeers(core: core);
    print('eşler: ${peers.length}, ad: "${peers.first.displayName}"');

    // 6. Hata, metin değil veri olarak geçmeli. Boş kimlik reddedilir ve Dart
    //    bunu CoreFailure.security(failure: …) olarak yakalar; Rust tarafındaki
    //    SecurityError çeşidi kaybolmaz.
    try {
      await appendHistory(
        core: core,
        message: HistoryMessage(
          id: '',
          conversationId: 'c-1',
          senderDeviceId: 'd-1',
          sentAtMs: 43,
          body: 'reddedilecek',
        ),
      );
      throw StateError('boş kimlik reddedilmeliydi');
    } on CoreFailure catch (failure) {
      // Freezed's generated variant sınıfları üzerinden düz `is` denetimi:
      // constructor-tear-off kalıbı yerine, hangi hata *çeşidinin* geldiğini
      // göstermesi için bilerek bu biçimde yazıldı.
      if (failure is! CoreFailure_Security ||
          failure.failure is! SecurityFailure_InvalidMessageId) {
        throw StateError('beklenmeyen hata çeşidi: $failure');
      }
      final inner = failure.failure as SecurityFailure_InvalidMessageId;
      print('hata çeşidi: CoreFailure_Security → '
          'SecurityFailure_InvalidMessageId');
      print('hata metni: ${inner.message}');
    }

    // Kanıt tamam: Dart tarafı Rust'ı gerçekten çağırdı ve bir değer aldı.
    stdout.writeln('SONUÇ: geçti');
  } finally {
    // `core` Rust tarafında açık bir SQLite bağlantısı tutmaya devam eder ve
    // dosya kilitli kalır; temizlik başarısız olursa bu kanıtı etkilemez, çünkü
    // kanıt yukarıda tamamlandı. Geçici dizin `mkvi-bridge-*` adıyla bırakılır.
    try {
      dataDir.deleteSync(recursive: true);
    } on FileSystemException {
      stdout.writeln('not: geçici dizin silinemedi, dosya Rust tarafında açık');
    }
  }
}
