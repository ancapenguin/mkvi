# `app/test/support/fakes/` — MKVI'nin sahte seam'leri

`lib/` altındaki on katman saf Dart ve her dış dünyaya bağlandığı yer bir arayüz.
Ama katmanların denetleyicileri `final class`, yani arayüzü **uygulayamazsın** —
gerçek sınıfı sahte seam'lerle kurabilirsin. Bu dizin o kurulumun tek yeridir.

Tek giriş noktası:

```dart
import '../support/fakes/fakes.dart';
```

Katman başına ayrı dosyalar, ama dışarıya açık olan hepsi `fakes.dart` içinde.

---

## ÜÇ KURAL — bu dizinin var oluş sebebi

MKVI'nin en pahalı dersi **"test yeşildi, özellik bozuk"**. Bunun neredeyse
tamamı bir **sessiz no-op**'tu: açılmamış bir transfer için `0` dönen bir
`write`, hiçbir şey script'lenmemişken `PeerAbsent` diyen bir peer store, "cevap
script'lenmedi" diyen bir fetcher. Cevabı sorulmamış bir sahte hiçbir şey
kanıtlamaz — ve **gürültülü yeşil** olarak kanıtlar.

| # | kural | nerede |
|---|---|---|
| 1 | Bir davranış **karar** ise test tarafından yazılmalı. Yazılmadıysa çağrı `UnscriptedCallError` fırlatır; cevap üretmez. | `ScriptLog.record` |
| 2 | Her çağrı **sırayla** kaydedilir. `fake.log.order` bir `List<String>`'dir. | `ScriptLog.order` |
| 3 | Hata yolu da script'lenebilir. | her sahtede `fail*` / `throwsOn*` / `refuse*` |

`ScriptLog.define(member, açıklama)` "yazılmış varsayılan" bildirir: her girdi
için doğru bir cevabı olan, yani **totaldir**. `fake.log.writtenDefaults` bunları
listeler, böylece "bu sahte burada esnek" görünmez bir gelenek olmaz.

### Gerçekten kırmızıya düşen yerler

Kolaylık olsun diye sessiz kalan üç davranış, burada **patlar**:

| sahte | kolay hali | buradaki hali |
|---|---|---|
| `ScriptedFileSink.write` | açılmamış transfer için `0` dönerdi | `UnscriptedCallError`. `0`, "disk doldu" ile aynı cevap |
| `FakePeerStore.readPeer` | `PeerAbsent()` dönerdi | `UnscriptedCallError`. `PeerAbsent` **tek** eşleşme ekranına giden yol |
| `ScriptedUpdateFileStore.append` | var olmayan map girdisine yazıyordu, chunk sessizce düşüyordu | `UnscriptedCallError` |
| `ScriptedStatsProbe.framesEncoded` | her id'ye `0` derdi | beyan edilmemiş sender için `UnscriptedCallError` |
| `ScriptedHttpFetcher.read` | `FeedReadFailed('no answer scripted')` derdi | `UnscriptedCallError`. `FeedReadFailed` = "sunucu ölü", karıştırılamaz |
| `ScriptedInstallerLauncher.launch` | — | `UnscriptedCallError`. Varsayılan başarı **asla** olmaz |

---

## Dosyalar

| dosya | neyin yerine |
|---|---|
| `fakes.dart` | tek barrel |
| `script_log.dart` | `ScriptLog`, `UnscriptedCallError`, `RecordedCall`, `pumpUntil`, `settle` |
| `session_fakes.dart` | `PeerStore`, `LocalSettings`, `DeviceIdentityLoader`, `PairingVerifier`, `PairScopedDeviceIdFactory`, `PeerTransportBinding`, `SignalingSocket`(+factory), `Delay`, `RendezvousClientFactory` |
| `chat_fakes.dart` | `ChatChannelBinding`, `HistoryStore`, `FileSink`, `OutgoingFileSource` |
| `call_fakes.dart` | `CallTimerStarter` tabanlı kontrollü saat (`FakeCallClock`), `CallMachine` için id üreteci |
| `media_fakes.dart` | `MediaTrackHandle`, `MediaSenderHandle`, `MediaSenderRegistry`, `MediaStatsProbe`, `MediaCapture`, `MediaDelay`, diagnostics |
| `update_fakes.dart` | `HttpFetcher`, `SignatureVerifier`, `InstallerLauncher`, `UpdateFileStore`, `UpdateClock` + feed/kurulum sabitleri |
| `layer_harness.dart` | `FakeCallHarness`, `FakeChatHarness`, `FakeMediaHarness`, `FakeSessionHarness`, `FakeUpdateHarness` |
| `fakes_test.dart` | sahtelerin **kendi** testi |

### Neden `script_log.dart` ayrı

Barrel `fakes.dart` altı dosyayı da dışa aktarıyor; altı dosya da aynı kaydı
paylaşmak zorunda. Barrel'in içinden bir şey import etmek döngüsel olur, bu
yüzden ortak ilkel tek bir dosyada duruyor. `fakes.dart` onu da dışa aktarıyor,
yani test yine tek import görüyor.

---

## Katman katman: hangi sahte neyin yerine

### Session

`FakeSessionHarness` gerçek `SessionController`'ı, gerçek `PeerStore` +
`LocalSettings` + `DeviceIdentityLoader` + `RendezvousClientFactory` +
`PairingVerifier` + `PeerTransportBinding` ile **tek satırda** kurar.

```dart
final harness = FakeSessionHarness()..seedPaired();
await harness.bootstrap();
harness.watchDriver();
await pumpUntil(() => harness.sockets.sockets.isNotEmpty);
await harness.verifyPeer();
```

- `seedAbsent()` · `seedPaired()` · `seedUnreadable(failure)` · `seedUnavailable()`
  — dördü de `PeerReadResult`'ın bir dalı; üçüncüsü olmadan `broken` ekranı
  test edilemez.
- **`harness.identity.calls`** — ROADMAP Faz 4'ün sayacı. Bugün başka hiçbir
  şey ölçmüyor.
- **`harness.bootstrapCalls`** ve **`harness.identityCallsAtBootstrap`** —
  Faz 4'ün dediği "sessizce ikinci kimlik üretilmesi". Reconnect döngüsü her
  denemede kimliği okur (bu doğru), yani iddia mutlak sayı değil, bootstrap'ın
  *kendisinin* kaç kez okuduğu.
- `harness.transport.closes` — her `closeChannel` anında kaç kanal açıktı. Süpürülmüş
  bir epoch'un canlı bir halefi yıktığı burada sayı olarak görünür.

### Chat

`FakeChatHarness` gerçek `ChatController` + `HistoryStore` + `FileSink`.

- `channel.wire` — kontrol ve ikili çerçevelerin **tek** sıralı listesi.
  `ROADMAP.md` Faz 5 siparişi veri olarak modelliyor; iki listeyi birleştirmek
  zorunda kalan bir test onu yanlış okur.
- `channel.refuse(reason: '...', times: n)` — kanal kapalıyken **reddi senin
  seçmen** gerekir. `reason` verilmeden `ChannelUnavailable` dönmez.
- `files.shortWriteBytes` / `zeroWrites` — "ilerleme gerçekten yazılan bayttan
  türetiliyor" iddiası çürütülebilir.
- `files.failOpenFor` / `failWriteFor` — hata yolları.

### Call

`FakeCallHarness` gerçek `CallMachine`'i `FakeCallClock` üzerine kurar.

`test/call/support/call_harness.dart` zamanlayıcıları elle tetikler; bu ikisi
ikisini de yapar. `advance(Duration)` **her bir vadeye sırayla atlar**, yani
kendi içinde yeniden kurulan bir zamanlayıcı gerçek olay döngüsünde olduğu gibi
işlenir — ve duvar saati hiç geçmez.

```dart
harness.ring(id);
harness.onlyLiveTimer.after;          // 45 s
harness.advance(const Duration(seconds: 45));   // ring zaman aşımı
```

`FakeCallClock` hiçbir yerde `Timer` kurmaz. `fireAll()` iptal edilmiş
zamanlayıcıları da tetikler — `dart:async` bunu imkânsız kılar, ve bu yüzden
makinenin bu garantiye **bağımlı olmadığını** gösteren testtir.

### Media

`FakeMediaHarness` gerçek `MediaController` + `MediaSeams`'in tamamı.

- **`harness.orphanedTracks`** — sızıntı dedektörü: OS'in tuttuğu ve kimsenin
  yayınlamadığı track. Canlı bir görüşmenin mikrofonu *öyle olmalıdır*; olmaması
  gereken şey canlı track + sender yokluğudur.
- `harness.availableDisplaySources` — sabit liste değil, OS'in listesi.
- **`stats.frameTally`** — ekran paylaşımı watchdog'ı için `framesEncoded`
  sayacı. `declareDefaultSenders(n)` harness'te varsayılan olarak çağrılır;
  beyan edilmemiş bir sender'a yapılan poll **patlar** çünkü `0` cevabı "ölü
  encoder" ile "olmayan sender"ı ayırt edilemez kılar.
- `capture.requireScript` — OS'in "istendiğini yaptım" varsayılanını açık bir
  iddiaya çevirir.

### Update

`FakeUpdateHarness` gerçek `UpdateClient` + beş seam.

- `ScriptedSignatureVerifier` **bayrak değildir**: elde dosya deposundaki gerçek
  baytları okur, tamamını hash'ler ve imzalı özetin karşılaştırır. Tek bir baytı
  çevirmek gerçek köprü gibi başarısız olur; `verifier.verified` listenin tamamı
  dosyayı devraldığını kanıtlar.
- `offerUpdate(bytes: ...)` imza özetini **yeniden imzalamaz** — sadece
  `bytes` verilmezse. Farklı bayt veren bir test bir reddi ölçüyordur;
  yeniden imzalamak o testi sessizce yeşile çevirirdi.
- Senaryolar: `feedNotFound()` (404 — bu ürünün gönderdiği arıza), `sizeMismatch()`,
  `truncateDownload()`, `useLegacyKey()` (`src-tauri/tauri.conf.json:41`deki
  emekli "Ed" anahtarı), `useUnreadableKey()`, `useUnavailableVerifier()`,
  `rejectSignature()`, `refuseInstall()`.

---

## Sahiplik

`app/test/support/mkvi_test_app.dart` ve `mkvi_test_app_test.dart` **lead
engineer'ın** dosyalarıdır. Bu dizin onları kullanır, değiştirmez. UI ajanları
widget testlerini `pumpMkvi(tester, child)` ile kurar ve katman sahtelerini
buradan alır:

```dart
await pumpMkvi(tester, MyScreen(controller: harness.controller));
```

Aynı şekilde `test/<katman>/support/` altındaki dosyalar o katmanın sahibine
aittir; bu dizin onları **kopyalamaz**, kendi yolunu yazar.

---

## Kendi testleri

`fakes_test.dart` sahteleri test eder. Kapsam turu değil, dönüşüm testi:

1. **Script'lenmemiş çağrı kırmızıya düşüyor** — her sahte için.
2. **Kayıt sırası bozulmuyor** — `log.order` sözleşme.
3. **Script'lenen hata yayılıyor** — `failNext*` / `throwsOn*` / `refuse*`.
4. **Teardown iz bırakmıyor** — `abort` diskte hiçbir şey bırakmıyor,
   `discard` çalıştırılabilir hiçbir şey bırakmıyor, `harness.dispose()` akışı
   kapatıyor.

```powershell
cd app; flutter test test/support/fakes
```

## Tuzak: `dispose()` `addTearDown`'a KONMAZ

`ChatController.dispose()` `await _states.close()` ile bitiyor. `testWidgets`
gövdesi **fake-async bölgesinde** koştuğu için o future **hiç tamamlanmaz:**

```dart
// YANLIŞ — 10 dakika sonra "test timed out" ile düşer.
addTearDown(harness.dispose);
```

`tester.runAsync` ile sarmalamak da **çalışmaz**; `addTearDown` içinden
`runAsync` çağırmak da kilitlenir. Ölçüldü ve çözüldü: `test/ui/workspace`
`disposeHarness(tester, harness)` yardımcısını koydu ve **gövdenin son satırında**
çağırıyor.

```dart
testWidgets('...', (WidgetTester tester) async {
  final FakeChatHarness h = FakeChatHarness();
  // ... iddialar ...
  await disposeHarness(tester, h);   // <- gövdenin sonunda, await ile
});
```

Bu tuzak `FakeChatHarness`, `FakeCallHarness` ve `FakeUpdateHarness` için geçerli
(üçü de `await ... close()` içeriyor). `FakeMediaHarness` ve `FakeSessionHarness`
senkron kapandığı için sorun yaşamıyor.
