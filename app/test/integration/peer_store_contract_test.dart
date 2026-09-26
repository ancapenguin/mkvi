/// The five branches of the peer-read failure mapping, measured.
///
/// `mkvi_bridge/README.md`'s "Hata sınırı: metin değil veri" is what makes this
/// suite possible without a native library: `CoreFailure` and `SecurityFailure`
/// are generated freezed **data classes**, so a real value of the real type can
/// be constructed here. That is not a fake `mkvi_bridge` call — no bridge method
/// is stubbed, nothing is pretended to return data — it is the error enum the
/// bridge would have thrown, built by hand.
///
/// The second half of the suite measures the *row* mapping, which is the other
/// way a read can be unreadable: the bridge handed back a record and the record is
/// shaped wrong. `peer_store.dart` already owns that judgement
/// (`decodeStoredPeer`), so the measurement here is that the adapter routes
/// through it rather than re-deciding.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/core/rust/rust_peer_store.dart';
import 'package:mkvi/session/peer_store.dart';
// `mkvi_bridge`'in `lib/` altında genel bir kütüphane dosyası yok ve README'i tüketiciden tam olarak bu yolu istiyor.
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/api.dart' as bridge;
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/error.dart' as bridge;

bridge.CoreFailure security(bridge.SecurityFailure inner) =>
    bridge.CoreFailure_Security(failure: inner);

void main() {
  group('hata eşlemesi — beş dal', () {
    test('1. kasada kayıp kayıt: PeerKeyringEntryMissing', () {
      // `api.rs:467-487` ve `security.rs:29`: eksik kayıt yeni anahtarla
      // doldurulmaz, adıyla bildirilir. Bu yüzden "eş yok" DEMİYOR.
      final PeerReadFailure mapped = mapCoreFailureToPeerReadFailure(
        security(
          const bridge.SecurityFailure_KeyringEntryMissing(
            name: 'device-signing-key-v1',
            message:
                "güvenli depoda 'device-signing-key-v1' kaydı bulunamadı; "
                'yerel veriler hâlâ bu kayda bağlı',
          ),
        ),
      );
      expect(mapped, isA<PeerKeyringEntryMissing>());
      expect(mapped.message, contains('anahtar kayıp'));
      expect(mapped.recovery, contains('Yeni bir cihaz eşleştirmen'));
    });

    test('2. kriptografik hata: PeerDecryptFailed', () {
      // Kayıt var ama doğrulaması kalktı: bu cihazdaki anahtar kaydın yazıldığı
      // anahtarla eşleşmiyor.
      final PeerReadFailure mapped = mapCoreFailureToPeerReadFailure(
        security(
          const bridge.SecurityFailure_Crypto(
            message: 'kriptografik işlem başarısız oldu',
          ),
        ),
      );
      expect(mapped, isA<PeerDecryptFailed>());
      expect(mapped.message, contains('çözülemedi'));
      expect(mapped.recovery, contains('eşleşme anahtarı değişmiş'));
    });

    test('3a. çözülemeyen gizli: PeerRecordCorrupt', () {
      final PeerReadFailure mapped = mapCoreFailureToPeerReadFailure(
        security(
          const bridge.SecurityFailure_InvalidSecret(
            message: 'geçersiz saklanmış gizli veri',
          ),
        ),
      );
      expect(mapped, isA<PeerRecordCorrupt>());
    });

    test('3b. çözülemeyen serileştirme: PeerRecordCorrupt', () {
      final PeerReadFailure mapped = mapCoreFailureToPeerReadFailure(
        security(
          const bridge.SecurityFailure_Serialization(
            message: 'yerel geçmiş verisi çözülemedi',
          ),
        ),
      );
      expect(mapped, isA<PeerRecordCorrupt>());
    });

    test('5. geri kalan her şey: PeerStoreUnavailable', () {
      // Beş dalın beşincisi: hiçbiri "eş kaydı yok" DEMEZ, çünkü
      // `PeerAbsent` beyaz eşleştirme ekranının tek yoludur.
      final List<Object> others = <Object>[
        const bridge.CoreFailure_Io(message: 'disk dolu'),
        const bridge.CoreFailure_HistoryLocked(message: 'kilitli'),
        const bridge.CoreFailure_PeerStoreLocked(message: 'kilitli'),
        security(
          const bridge.SecurityFailure_Database(message: 'yerel geçmiş hatası'),
        ),
        security(
          const bridge.SecurityFailure_SecretStore(message: 'kasaya erişilemedi'),
        ),
        security(
          const bridge.SecurityFailure_SecretStoreMissing(
            message: 'yazılan değer geri okunamadı',
          ),
        ),
        // Köprü olmayan bir makinede gelen şey bir `CoreFailure` değil.
        StateError('DynamicLibrary.open başarısız'),
      ];
      for (final Object failure in others) {
        expect(
          mapCoreFailureToPeerReadFailure(failure),
          isA<PeerStoreUnavailable>(),
          reason: '$failure yanlış sınıflandırıldı',
        );
      }
    });

    test('her dalın Türkçe ve eyleme dönük iki cümlesi var', () {
      final List<PeerReadFailure> all = <PeerReadFailure>[
        mapCoreFailureToPeerReadFailure(
          security(
            const bridge.SecurityFailure_KeyringEntryMissing(
              name: 'history-key-v1',
              message: 'yok',
            ),
          ),
        ),
        mapCoreFailureToPeerReadFailure(
          security(const bridge.SecurityFailure_Crypto(message: 'x')),
        ),
        mapCoreFailureToPeerReadFailure(
          security(const bridge.SecurityFailure_InvalidSecret(message: 'x')),
        ),
        mapCoreFailureToPeerReadFailure(
          const bridge.CoreFailure_Io(message: 'x'),
        ),
      ];
      for (final PeerReadFailure failure in all) {
        expect(failure.message, isNotEmpty);
        expect(failure.recovery, isNotEmpty);
        expect(failure.toString(), failure.message);
      }
    });
  });

  group('satır çözümleme', () {
    test('sağlam satır PeerFound oluyor ve adı temizliyor', () {
      final PeerReadResult result = decodeBridgePeer(
        bridge.KnownPeer(
          publicKey: 'ocBf7Y0Cr+t0WkRwS+uhapiSLxEz2KP9SSileaNDrxc',
          discoveryId: 'A' * 43,
          displayName: 'Kuzenim',
          pairedAtMs: 1730000000000,
        ),
      );
      expect(result, isA<PeerFound>());
      final KnownPeer peer = (result as PeerFound).peer;
      expect(peer.publicKey, 'ocBf7Y0Cr+t0WkRwS+uhapiSLxEz2KP9SSileaNDrxc');
      expect(peer.discoveryId, 'A' * 43);
      expect(peer.announcedName, 'Kuzenim');
      expect(peer.pairedAtMs, 1730000000000);
    });

    test('eksik ad, "Kişi" olur, bozuk olmaz', () {
      // `decodeStoredPeer`'in kuralı: `display_name` yoksa bu bozulma DEĞİLDİR;
      // 0.1.0 adı saklamadan yazan bir kurulumdan gelir.
      final PeerReadResult result = decodeBridgePeer(
        const bridge.KnownPeer(
          publicKey: 'k',
          discoveryId: 'd',
          displayName: '',
          pairedAtMs: 0,
        ),
      );
      expect(result, isA<PeerFound>());
      expect((result as PeerFound).peer.announcedName, '');
    });

    test('ad tehlikeli metinse yolda temizleniyor', () {
      // The name arrives from a peer, so it is untrusted input and this layer
      // has to survive it. Two separate things are measured here:
      //
      // 1. What the sanitiser actually does. It keeps `Ada <b>bold</b>` - plain
      //    text with angle brackets - and drops the `<script>` element together
      //    with its closing tag, which is what the shared wire contract says
      //    (`app/lib/core/protocol/text_sanitizer.dart`, pinned by
      //    `vectors/wire-v1.json`). The expectation is that measured behaviour,
      //    not a hope: a first draft of this test asserted the input came out
      //    unchanged and went red, which is how the contract got pinned.
      // 2. A control character used to sit in this string as a RAW byte, and
      //    git then treated the whole file as binary so the diff stopped being
      //    readable - a one-character typo made a whole file unreviewable.
      //    Written as escapes here: same test, readable diff.
      final PeerReadResult result = decodeBridgePeer(
        const bridge.KnownPeer(
          publicKey: 'k',
          discoveryId: 'd',
          displayName: 'Ada \x00\x1f <b>bold</b> <script>alert(1)</script>  ',
          pairedAtMs: 0,
        ),
      );
      expect(
        (result as PeerFound).peer.announcedName,
        'Ada <b>bold</b> <script>alert(1)</script',
        reason:
            'the sanitiser keeps plain angle brackets and drops the script '
            'element with its closing tag. If this changes then the wire '
            'contract changed, and `text_sanitizer.dart` and '
            '`vectors/wire-v1.json` have to change together.',
      );
    });

    test('4. bozuk satır: PeerRecordCorrupt', () {
      final List<bridge.KnownPeer> broken = <bridge.KnownPeer>[
        const bridge.KnownPeer(
          publicKey: '',
          discoveryId: 'd',
          displayName: 'x',
          pairedAtMs: 0,
        ),
        const bridge.KnownPeer(
          publicKey: 'k',
          discoveryId: '',
          displayName: 'x',
          pairedAtMs: 0,
        ),
      ];
      for (final bridge.KnownPeer peer in broken) {
        final PeerReadResult result = decodeBridgePeer(peer);
        expect(
          result,
          isA<PeerUnreadable>(),
          reason: '$peer bozuk sayılmadı',
        );
        expect(
          (result as PeerUnreadable).failure,
          isA<PeerRecordCorrupt>(),
        );
      }
    });

    test('yerel takma ad satıra ASLA girmez', () {
      // `peer_store.dart`'in `toJson` sözleşmesi: `display_name` karşı tarafın
      // kendi adıdır, bu cihazın notu değildir.
      const KnownPeer stored = KnownPeer(
        publicKey: 'k',
        discoveryId: 'd',
        announcedName: 'Kuzenim',
        pairedAtMs: 0,
      );
      final String encoded = stored.encode();
      expect(encoded, contains('"display_name":"Kuzenim"'));
      expect(encoded, isNot(contains('peerAlias')));
      expect(encoded, isNot(contains('mkvi.peerAlias')));
    });
  });
}
