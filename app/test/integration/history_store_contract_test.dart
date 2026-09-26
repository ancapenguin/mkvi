/// Two contracts the Rust history store has to bend to, measured.
///
/// 1. **A duplicate id is a no-op, not an error.** `history_store.dart:143-145`
///    says a retried send and a re-read of the timeline both land on `append`, so
///    a repeat must be silent. `mkvi_core` deliberately does the opposite —
///    `api.rs` documents "a duplicate `id` fails rather than overwriting" and
///    `security.rs:261` is a plain `INSERT` into a primary key. The adapter
///    therefore has to swallow exactly that one failure and rethrow everything
///    else. [classifyHistoryAppendFailure] is where it happens, and it is pure, so
///    it is measured here without a native library.
/// 2. **`retentionLimit` and what the core can return disagree.** The layer asks
///    for 5000 lines; the core clamps every read to 500. The gap is kept as a
///    value ([historyRetentionGap]) rather than closed by quietly changing either
///    number.
///
/// The paging arithmetic ([HistoryWindow]) is measured on its own, with real
/// `HistoryMessage` values, because the window's *order* and its *hasMore*
/// answer are what `ChatTimeline.exhausted` depends on and neither is visible
/// without a core.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/history_store.dart';
import 'package:mkvi/chat/timeline_message.dart';
import 'package:mkvi/core/rust/rust_history_store.dart';
// `mkvi_bridge`'in `lib/` altında genel bir kütüphane dosyası yok ve README'i tüketiciden tam olarak bu yolu istiyor.
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/api.dart' as bridge;
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/error.dart' as bridge;

bridge.HistoryMessage row(
  String id, {
  String conversationId = 'c-1',
  int sentAtMs = 0,
  String senderDeviceId = 'peer',
}) => bridge.HistoryMessage(
  id: id,
  conversationId: conversationId,
  senderDeviceId: senderDeviceId,
  sentAtMs: sentAtMs,
  body: 'gövde $id',
);

void main() {
  group('yinelenen id sessiz no-op', () {
    test('birincil anahtar çakışması "duplicate" sayılıyor', () {
      // `security.rs:261` düz bir `INSERT`; `id` birincil anahtar. SQLite'in
      // kendi metni (bu makinede ölçüldü: `UNIQUE constraint failed:
      // encrypted_history.id`), `SecurityError::Database` üzerinden
      // `SecurityFailure_Database` içine geçiyor.
      final HistoryAppendFailure verdict = classifyHistoryAppendFailure(
        const bridge.CoreFailure_Security(
          failure: bridge.SecurityFailure_Database(
            message:
                'yerel geçmiş veritabanı hatası: UNIQUE constraint failed: '
                'encrypted_history.id',
          ),
        ),
      );
      expect(verdict, HistoryAppendFailure.duplicateId);
    });

    test('veritabanı hatası her zaman duplicate DEĞİL', () {
      // Aynı enum çeşidi, farklı sebep. "duplicate" demek bu ikisini
      // ayırt edilemez hale getirirdi.
      final HistoryAppendFailure verdict = classifyHistoryAppendFailure(
        const bridge.CoreFailure_Security(
          failure: bridge.SecurityFailure_Database(
            message: 'yerel geçmiş veritabanı hatası: disk dolu',
          ),
        ),
      );
      expect(verdict, HistoryAppendFailure.rejected);
    });

    test('boş veya çok uzun id "duplicate" DEĞİL, yeniden fırlatılır', () {
      // `security.rs:245-247` bunu her G/Ç öncesinde reddeder. Yutmak bir
      // satırı izsiz kaybederdi.
      final HistoryAppendFailure verdict = classifyHistoryAppendFailure(
        const bridge.CoreFailure_Security(
          failure: bridge.SecurityFailure_InvalidMessageId(
            message: 'mesaj kimliği boş veya çok uzun',
          ),
        ),
      );
      expect(verdict, HistoryAppendFailure.rejected);
    });

    test('kriptografik, serileştirme ve köprü hataları yeniden fırlatılır', () {
      const List<bridge.CoreFailure> rest = <bridge.CoreFailure>[
        bridge.CoreFailure_Security(
          failure: bridge.SecurityFailure_Crypto(
            message: 'kriptografik işlem başarısız oldu',
          ),
        ),
        bridge.CoreFailure_Security(
          failure: bridge.SecurityFailure_Serialization(
            message: 'yerel geçmiş verisi çözülemedi',
          ),
        ),
        bridge.CoreFailure_Security(
          failure: bridge.SecurityFailure_KeyringEntryMissing(
            name: 'history-key-v1',
            message: 'kayıp',
          ),
        ),
        bridge.CoreFailure_HistoryLocked(message: 'kilitli'),
        bridge.CoreFailure_Io(message: 'disk dolu'),
      ];
      for (final bridge.CoreFailure failure in rest) {
        expect(
          classifyHistoryAppendFailure(failure),
          HistoryAppendFailure.rejected,
          reason: '$failure yutuldu; sessiz no-op yalnız yinelenen id içindir',
        );
      }
    });

    test('sınıflandırıcı köprü dışı bir hatayı da reddediyor', () {
      expect(
        classifyHistoryAppendFailure(StateError('DynamicLibrary.open')),
        HistoryAppendFailure.rejected,
      );
    });
  });

  group('saklama sayısı uyuşmazlığı görünür kalıyor', () {
    test('katman 5000 istiyor, çekirdek 500 döndürüyor', () {
      // `history_store.dart:160` ve `security.rs:268` (`limit.min(500)`).
      expect(HistoryStore.retentionLimit, 5000);
      expect(historyWindowRows, 500);
      expect(historyRetentionGap.requestedLimit, HistoryStore.retentionLimit);
      expect(historyRetentionGap.bridgeRowLimit, historyWindowRows);
    });

    test('uyumsuzluk "anlaşılmaz" diye işaretleniyor', () {
      expect(historyRetentionGap.isAgreement, isFalse);
      expect(historyRetentionGap.enforcedLimit, 500);
      expect(historyRetentionGap.messageTr, contains('500'));
      expect(historyRetentionGap.messageTr, contains('5000'));
    });

    test('bir sayfa asla pencerenin dışına çıkmıyor', () {
      // 10000 satır isteyen bir çağıran 500 alır; çekirdek kırpmasına güveniyoruz.
      expect(RustHistoryStore.rowsFor(10000), historyWindowRows);
      expect(RustHistoryStore.rowsFor(0), 1, reason: 'sıfır satır "hiç yok" demek');
      expect(RustHistoryStore.rowsFor(20), 80, reason: 'konu filtresi sonra uygulanıyor');
    });
  });

  group('sayfalama aritmetiği', () {
    test('en yeni sayfa ESKİDEN YENİYE sıralanıyor', () {
      // `HistoryPage` sözleşmesi: en eski satır önce. Ters çevirme, listenin
      // nereden geldiğine bağımlı olmamak için tipten gelir.
      final HistoryPageResult result = HistoryWindow.newest(
        rows: <bridge.HistoryMessage>[
          row('m-3', sentAtMs: 300),
          row('m-1', sentAtMs: 100),
          row('m-2', sentAtMs: 200),
        ],
        conversationId: 'c-1',
        limit: 10,
        requested: 10,
      );
      expect(
        result.page.messages.map((StoredMessage m) => m.id).toList(),
        <String>['m-1', 'm-2', 'm-3'],
      );
      expect(result.page.hasMore, isFalse);
      expect(result.reachedWindowStart, isFalse, reason: 'pencere dolu değil');
    });

    test('limit dolunca hasMore doğru, ve en yeniler kalıyor', () {
      final HistoryPageResult result = HistoryWindow.newest(
        rows: <bridge.HistoryMessage>[
          row('m-3', sentAtMs: 300),
          row('m-2', sentAtMs: 200),
          row('m-1', sentAtMs: 100),
        ],
        conversationId: 'c-1',
        limit: 2,
        requested: 10,
      );
      expect(
        result.page.messages.map((StoredMessage m) => m.id).toList(),
        <String>['m-2', 'm-3'],
      );
      expect(result.page.hasMore, isTrue);
    });

    test('başka konuşmanın satırları sayfaya karışmıyor', () {
      final HistoryPageResult result = HistoryWindow.newest(
        rows: <bridge.HistoryMessage>[
          row('m-9', conversationId: 'c-2', sentAtMs: 900),
          row('m-3', sentAtMs: 300),
          row('m-2', sentAtMs: 200),
          row('m-1', sentAtMs: 100),
        ],
        conversationId: 'c-1',
        limit: 10,
        requested: 10,
      );
      expect(
        result.page.messages.map((StoredMessage m) => m.id).toList(),
        <String>['m-1', 'm-2', 'm-3'],
      );
    });

    test('imleçten eski satırlar, imleçten yenilere göre sıralanıyor', () {
      final HistoryPageResult result = HistoryWindow.older(
        rows: <bridge.HistoryMessage>[
          row('m-5', sentAtMs: 500),
          row('m-4', sentAtMs: 400),
          row('m-3', sentAtMs: 300),
          row('m-2', sentAtMs: 200),
          row('m-1', sentAtMs: 100),
        ],
        conversationId: 'c-1',
        beforeMs: 300,
        beforeId: 'm-3',
        limit: 10,
        requested: 10,
      );
      expect(
        result.page.messages.map((StoredMessage m) => m.id).toList(),
        <String>['m-1', 'm-2'],
      );
      expect(result.page.hasMore, isFalse);
    });

    test('aynı zaman damgasında id sıralaması imleci TAM kılar', () {
      // `security.rs:267` yalnız `created_at_ms` ile sıralar; SQLite eşit
      // zaman damgalarında hangi satırı önce vereceğini seçebilir. Sıralama
      // Dart'ta tekrarlanıyor, yoksa bir sayfa SQLite'ın o günkü haline bağlı
      // olurdu.
      final HistoryPageResult result = HistoryWindow.older(
        rows: <bridge.HistoryMessage>[
          row('m-a', sentAtMs: 300),
          row('m-b', sentAtMs: 300),
          row('m-c', sentAtMs: 300),
        ],
        conversationId: 'c-1',
        beforeMs: 300,
        beforeId: 'm-b',
        limit: 10,
        requested: 10,
      );
      expect(
        result.page.messages.map((StoredMessage m) => m.id).toList(),
        <String>['m-a'],
      );
    });

    test('imleç satırı pencerenin dışındaysa bu KAYDEDİLİR', () {
      // 500 satırlık pencerenin ötesine sayfa atlamak sessizce "daha eski yok"
      // demek olurdu. Sayaç bunu görünür kılar.
      final HistoryPageResult result = HistoryWindow.older(
        rows: <bridge.HistoryMessage>[
          for (int i = 0; i < 500; i += 1) row('m-$i', sentAtMs: 100000 - i),
        ],
        conversationId: 'c-1',
        beforeMs: 1,
        beforeId: 'm-yok',
        limit: 10,
        requested: 500,
      );
      expect(result.reachedWindowStart, isTrue);
    });

    test('imleç satırı penceredeyse son hâli güvenilir', () {
      final HistoryPageResult result = HistoryWindow.older(
        rows: <bridge.HistoryMessage>[
          row('m-3', sentAtMs: 300),
          row('m-2', sentAtMs: 200),
          row('m-1', sentAtMs: 100),
        ],
        conversationId: 'c-1',
        beforeMs: 300,
        beforeId: 'm-3',
        limit: 10,
        requested: 10,
      );
      expect(result.reachedWindowStart, isFalse);
    });

    test('yön diski satırın göndereninden geliyor', () {
      // `security.rs:261` `sender_device_id`'yi saklıyor, yönü saklamıyor.
      final HistoryPageResult result = HistoryWindow.newest(
        rows: <bridge.HistoryMessage>[
          row('m-1', sentAtMs: 100, senderDeviceId: 'local'),
          row('m-2', sentAtMs: 200, senderDeviceId: 'peer'),
        ],
        conversationId: 'c-1',
        limit: 10,
        requested: 10,
      );
      expect(
        result.page.messages
            .map((StoredMessage m) => m.direction)
            .toList(),
        <MessageDirection>[
          MessageDirection.outgoing,
          MessageDirection.incoming,
        ],
      );
    });

    test('teslim durumu KAYDEDİLEMEDİĞİ için ölçülüyor', () {
      // Şifreli kayıtta teslim sütunu YOK. `StoredMessage`'in kendi yorumu
      // "gönderilirken yazılan bir satır gönderilmiş olarak dirilmesin" diyor;
      // bugün bu sütun çekirdekte olmadığı için okuma `sent` veriyor. Bu ölçüm
      // kırmızıya döndüğü gün sütunun eklendiğinin işareti.
      final HistoryPageResult result = HistoryWindow.newest(
        rows: <bridge.HistoryMessage>[row('m-1', sentAtMs: 100)],
        conversationId: 'c-1',
        limit: 10,
        requested: 10,
      );
      expect(
        result.page.messages.single.delivery,
        MessageDelivery.sent,
        reason: 'şifreli kayıtta teslim sütunu yok; çekirdek sahibi bunu '
            'düzeltirse bu ölçüm kırmızıya döner',
      );
    });
  });

  group('trimTo dürüst', () {
    test('yapmadığı bir temizliği bildirmiyor', () {
      // Köprüde silme çağrısı yok ve arkasında bir `Core` çağrısı da yok.
      // Sessiz bir no-op, "sınırlı" dediği bir log'un sınırsız büyümesi olurdu.
      const HistoryTrimUnsupported refusal = HistoryTrimUnsupported('c-1');
      expect(refusal.messageTr, contains('temizlenemedi'));
      expect(refusal.recoveryTr, contains('sınırı'));
      expect(refusal.toString(), contains('c-1'));
    });
  });
}
