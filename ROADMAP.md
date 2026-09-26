# MKVI — yol haritası

> Bu dosya projenin **kanonik planıdır**. Sıfır bağlamla açılan bir oturum önce
> `docs/adr/` kararlarını, sonra burayı okuyup işaretlenmemiş ilk kutuya devam eder.
> Kutu bitince `[x]` yap ve altına **tek satır kanıt** yaz (komut çıktısı, commit, test).
> Mimari kararlar `docs/adr/`'de, mimari harita `ARCHITECTURE.md`'de.

## Hedef

İki kişinin (sen + kuzenin) hesapsız, sunucuda içerik tutmayan, kurup unutacağın bir
iletişim uygulaması. **"Bitti" tanımı:**

- Windows'ta iki cihaz kurulumdan sonra **bir kez** kod girer, bir daha asla girmez.
- Mesaj, dosya, sesli/görüntülü arama ve ekran paylaşımı gerçekten çalışır.
- Kimlik doğrulaması uçtan uca güvenlidir (aradaki sunucu okuyamaz, **sunucu
  korsanlığı da ifadeyi değiştiremez**).
- Güncellemeler kendiliğinden iner ve imzayla doğrulanır.
- Windows + macOS + Linux çalışır; Android ikinci hedeftir.
- Herkes kendi sinyal sunucusunu kurabilir; MKVI kimseye hizmet vermez.

## Depo düzeni

```
mkvi/
├── app/                 Flutter uygulaması — Windows → macOS/Linux → Android
├── crates/
│   ├── mkvi_core/       Rust çekirdeği (Ed25519, keyring, şifreli SQLite, dosya)
│   └── mkvi_bridge/     flutter_rust_bridge yüzeyi (tek crate, iki platform)
├── cloudflare/          Sinyalleşme sunucusu (Worker + 2 Durable Object) — dokunulmaz
├── design/              tokens.json + generator + kontrast testi (tasarımın tek kaynağı)
├── vectors/             Ortak golden vector (sözleşme kanıtı)
├── docs/                Mimari, ADR, el testi prosedürü
└── tool.ps1             Tek kapı: `.\tool.ps1 gate`
```

**Katman kuralı:** Dart yalnızca `mkvi_bridge` üzerinden Rust'a dokunur. `mkvi_core`
UI çerçevesi bilmez. `cloudflare/` hiçbir şeyi bilmez.

---

## 2026-09-26 — 0.1.x Tauri hattı emekliye ayrıldı

**Karar (kullanıcı):** 0.1.x Tauri hattı (`src/`, `src-tauri/`, `spike/`, kök
Vite/TypeScript yapılandırması) **tamamen emekliye ayrıldı ve silindi**. Geriye
dönük uyumluluk, migration yolu veya eski istemcilerin otomatik güncellenmesi
**gerekmiyor**: uygulamayı kullanan iki kişi var (kullanıcı + kuzeni) ve ikisi de
yeni sürümü elle kuracak.

**Gerekçe:** hedef temiz bir Rust + Flutter projesi. 0.1.x hattı artık ne
derleniyor ne test ediliyordu; kapıda koşan üç adım (`tsc`, `vitest`, `cargo test
--locked src-tauri`) gerçekte **ölü kodun** doğrulamasıydı, 0.2.0'in bir parçası
değil.

**Yan etkiler, dürüstçe:**

| Etki | Durum |
|---|---|
| `docs/manual-test.md` — iki cihazlı el prosedürü | `spike/README.md`'den **kurtarıldı**; karar kuralı (`8/10` düz port, `4'ten fazla` vendor fork, `%30` NO-GO) kelimesi kelimesine korundu |
| `vectors/wire-v1.json` — ortak golden vector | TypeScript tarafı silindiği için **tek taraflı** oldu. Vektörler 0.1.x'in iki kusurunu (base64 alfabesi, UUID biçimi) hâlâ canlı tutuyor; kasıtlı bir kayıp |
| `mkvi-updates` deposu | Kullanıcı tarafından **silindi**. Özel feed + deploy key yaklaşımı yapısal olarak imkânsızdı: `raw.githubusercontent.com` gizli depoyu kimlik doğrulanmamış istemciye servis etmez |
| Yayın dağıtımı | GitHub Releases (resmî Tauri yolu): `releases/latest/download/latest.json` |
| `tool.ps1 gate` | 12 adımdan 9'a indi. `tsc`/`vitest`(kök)/`src-tauri` kalktı; `mkvi_bridge` testleri **eklendi** (daha önce hiçbir yerde koşmuyordu) |
| Sürüm kapısı | **Eklendi.** `VERSION` + `app/pubspec.yaml` + iki crate aynı sürümü göstermeli. Ölçüldü: `VERSION` 0.2.0 iken beş kaynak 0.1.4'te kalmıştı |
| `gercek_veri.rs` | `#[ignore]` **niteliği eklendi**. Dosya bunu yazıyordu ama nitelik yoktu: belgelenen komut hiçbir testle eşleşmiyor, kapı ise sessizce `return` ediyordu |

**Yayın sırası:** public → Actions ücretsiz → Releases dağıtımı → ilk Flutter
sürümü. Otomatik güncelleme **çalışmayacak**; iki kullanıcı da elle kuracak.
Bu `README.md` ve `SECURITY.md`'de açıkça yazılı.

## Öğrenilenler — 0.1.4 gerçek cihazlarda denendi

> **Ayrıca iki sözleşme ihlali bulundu:** ortak vektör dosyası
> (`vectors/wire-v1.json`, 134 vaka) hem TypeScript hem Dart uygulamasını aynı
> kurallara bağladı ve 0.1.x'in **iki** gerçek kusurunu ortaya çıkardı. Bunlar
> `src/services/signaling-vectors.test.ts` içinde `it.fails` ile sabitlendi —
> kural ihlali gerçekken suite yeşil kalıyor, kaynak düzelince test kırmızıya
> dönmeye başlıyor. **8 vakit** iki kök nedenden geliyor:
>
> | # | Kök neden | Vaka sayısı | Durum |
> |---|---|---|---|
> | 11 | **`wss://` sessizce `ws://`'ye düşürülüyor.** `rendezvous.ts:13` yalnız `https:` → `wss:` eşlemesi yapıyor. Ayarlara `wss://` adresi yazan kullanıcı **şifresiz** sinyal bağlantısı alıyor; kimlik imzaları ve SDP açıkta. | 1 | Dart portu doğru; `test/signaling` yeşil |
> | 12 | **Geçersiz endpoint `connect()`'i senkron olarak `TypeError` ile kaçırıyor.** `new URL(path, endpoint)` (`rendezvous.ts:12`) promise'in dışında, yani `connect(...).catch(...)` hiç çalışmıyor; kullanıcı "Signaling sunucusuna bağlanılamadı." yerine ham bir `TypeError: Invalid URL` görüyor. | 7 | Dart portu doğru; `test/signaling` yeşil |
>
> Bu iki kusur donmuş 0.1.x hattında **düzeltilmiyor** — hat artık yayımlanmıyor ve
> kuzen Flutter build'ini elle kuracak. Vektörler ve `it.fails` işaretleri
> TypeScript satırı silinene kadar kanıt olarak kalıyor.

Bu on kusur **canlı testte** bulundu. Kaynak: kullanıcının canlı test raporu + her biri
için dosya/satır düzeyinde kök neden analizi.

> **Durum sütunu dürüsttür: bu on kusurun hiçbirinde regresyon testi YOK.**
> Doğrulandı: `src/services/peer-transport.test.ts` içindeki 27 testin **tamamı**
> ayrıştırıcı/doğrulama (parseControl, safeName, safeMime, randomTransferId).
> Çağrı durum makinesi, medya, müzakere, yeniden bağlanma, isim, bildirim ve kontrast
> için **sıfır** test var. Bu yüzden aşağıdaki maddeler "kilitlendi" değil,
> **taşınacak gerekliliklerdir**; her biri ilgili fazın çıkış koşulunda teste bağlanır.

| # | Kusur | Kök neden | Durum |
|---|---|---|---|
| 1 | Kamera ve ekran paylaşımı hiç çalışmıyor | **İki ayrı neden.** (a) Tauri hiçbir WebView2 izin handler'ı kaydetmiyor, wry `msWebOOUI`'yi kapatıyor → izin reddi. (b) `flutter_webrtc` **kamera yokken hata vermiyor**: `GetUserVideo` track'siz, hatasız dönüyor, `getUserMedia` boş `videoTracks` ile "başarılı" diyor. Yani yalnız istisna yakalayan bir merdiven "kamerasız başarılı" olur ve hiçbir şey göndermez. | (a) Flutter'la **ortadan kalkıyor**. (b) Flutter'a **özgü yeni bir tuzak** — sessiz başarısızlık; `MediaController` sonucu ayrıca denetliyor, 115 test. `Helper.switchCamera` de Windows'ta hiç çalışmıyor (`NotImplemented`), port yeniden yakalama yapıyor. |
| 2 | Görüntülü arama isteği sessizce sesliye düşüyor | İzin reddi `getUserMedia` zincirinde sessizce yutuluyordu | Kodda kısmen düzeltildi (`e567276`), **testi yok** |
| 3 | Cevap ekranı yok, arama direkt açılıyor | 0.1.4'te otomatik kabul vardı; cevap ekranı hiç yayımlanmamıştı | Kod **var** (`e567276`) ama kullanıcı hiç görmedi, **testi yok** |
| 4 | Yazılar okunmuyor | 17 WCAG ihlali; en kötüsü video placeholder ışık temada **1.17:1**, odak halkası vurguyla aynı (**1.00**) | **Testi yok** — `design/` kontrast testi yazılıyor |
| 5 | Ana sahne kendi kamerana sabit, karşı taraf 126 px'de | Kaynak seçimi `local-camera`'ya sabitlenmiş, uzak kamera gelince geçiş yok | Kodda kısmen düzeltildi, **testi yok** |
| 6 | Sesliyken kamera açılamıyor, kaleyen kamerasını açamıyor | Hata Türkçe olmayan ham `DOMException` metniydi; `acceptCall` medyadan sonra geliyordu | Kodda kısmen düzeltildi, **testi yok** |
| 7 | Takma ad, karşı tarafın gerçek adını eziyor | `App.tsx:119` → `peerAlias \|\| peerAnnouncedName`; ayrıca `ChatCallWorkspace.tsx:490` `aliasIsSet` tuzağı | **AÇIK** — bu satırlar hâlâ aynı, düzeltilmedi |
| 8 | Sağ alt bildirimi gitmiyor, gönder tuşunu kapatıyor | 6 yerden ~saniyede bir yeniden yazılıyor, sayaç hiç dolmuyor; `z-index:100` yazarın üstünde | **AÇIK** — sayaç eklendi ama döngü yeniden yazmaya devam ediyor |
| 9 | Kapat-aç geri bağlanmıyor, beyaz ekrana düşüyor | Bootstrap hatası "ilk kurulum" sanılıyor; Tauri IPC koruması yok; **keyring boşken sessizce yeni kimlik** üretiliyor | **AÇIK** — sessiz kimlik üretimi şu an `mkvi_core`'da kapatılıyor |
| 10 | Güncelleme hiç çalışmıyor | `ancapenguin/mkvi-updates` deposu **404** veriyor (canlı doğrulandı) | **AÇIK** — Faz 7 |


## Verilmiş kararlar

- [x] **Arayüz Flutter.** 0.1.x Tauri hattı 2026-09-26'da emekliye ayrıldı ve silindi
      (karar ve yan etkiler yukarıda). Kanıt ve riskler: `docs/adr/0001`.
- [x] **Rust çekirdek korunur**, Tauri'den ayrılıp `mkvi_core` olur. Sinyalleşme
      sunucusu **hiç değişmez**.
- [x] **Lisans:** uygulama `Apache-2.0 OR MIT`; `cloudflare/` **AGPL-3.0** — kimse
      bedava kamu sunucusu işletip markalı hizmet satamaz.
- [x] **Varsayılan sunucu gömülmez.** Herkes kendi Worker'ını kurar; adresi ayarlara
      yazar. Sebep: ücretsiz katmanda bir eşleşme ~115 GB-s DO süresi yiyor
      (~110 eşleşme/gün), sonrası herkes için ölü; ayrıca keyfi kodla DO şişirme
      mümkün ve **kimseye hizmet vermiyoruz**.
- [x] **Tasarımın tek kaynağı `design/tokens.json`.** Kontrast testiyle kilitli;
      özel vurgu rengi, sistem teması, yüksek kontrast, hareket azaltma desteklenir.
- [x] **Güncelleme feed'i korunur** (resmi `latest.json` şeması + minisign imzası).
      Yalnızca istemci değişir: indirme Dart'ta, **doğrulama Rust'ta**.
- [x] **WebRTC sarmalayıcısı alınmaz.** simple-peer/PeerJS/werift bu projedeki
      dört hatayı engellemedi; WebView2 zaten WebRTC içeriyordu. Flutter tarafında da
      `flutter_webrtc` doğrudan kullanılır.
- [x] **UI kütüphanesi, i18n, durum yönetimi alınmaz.** El yazması tema + `ChangeNotifier`.
- [x] **Kullanıcı parolası yok.** "Kur, bir kez kod gir, bir daha asla" sözü korunur;
      Android'de anahtar platform kasasında (`flutter_secure_storage`).
- [x] **Kendi adını kullanıcı belirler**, `profile` mesajıyla karşıya gider. Takma ad
      yalnız yerelde kalır ve asla gerçek adın yerini almaz.

---

## Faz 0.5 — Taşıma ve depolama (P0, yeni mimari)

> **Neden ayrı bir faz:** 0.2.0'ın on katmanı yazılı ve testli, ama
> **`PeerTransportBinding`, `ChatChannelBinding`, `HistoryStore`, `FileSink`,
> `PeerStore`, `LocalSettings`, `DeviceIdentityLoader`** arayüzlerinin
> **hiçbirinin üretim implementasyonu yok** (ölçüldü: `app/lib` altında bu
> arayüzleri uygulayan sınıf sayısı **sıfır**). Yani bugün iki cihaz arasında
> **hiçbir mesaj gidemez** — uygulama birbirini göremez. `main.dart`'ı bağlamak
> bunu çözmez; çünkü bağlanacak bir taşıma yok.
>
> **Mimari karar:** `docs/adr/0002-transport-architecture.md` (821 satır).
> Özet: Cloudflare DO **tek** sınıfa iner (`RendezvousRoom`, hibernating) ve
> **oturum ömürlü, tek kullanımlık biletler** üretir; `identity` zarfı
> Worker'dan kalkar, teklif/cevap cihazlar arasında Ed25519 imzasıyla taşınır;
> bağlantı **tek seferlik üç transceiver'lı** müzakereyle kurulur; SAS ifadesi
> **DTLS sertifika parmak izlerinden** üretilir ve `Faz 4`'teki açık güvenlik
> maddesi böylece kapanır.
>
> **Doğrulanan iki ölçüm** (ADR'ın kilitleyici bulguları, bağımsız teyit edildi):
> - `flutter_webrtc` **C++ katmanında `rollback` yok** — `grep` → 0 eşleşme.
>   Perfect-negotiation tabanlı hiçbir seçenek kabul edilemez. **Ama MKVI'ye
>   gerekmiyor:** üç transceiver `open()`'da bir kez kuruluyor, medya yöntemleri
>   transceiver eklemiyor → glare penceresi yapısal olarak yok.
> - `getStats()` **`certificate` raporu üretmiyor** — `grep certificate` → 0 eşleşme.
>   SAS parmak izi SDP'den alınacak, `getStats()` yalnız çapraz doğrulama.
>
> **Tekerlek kuralı:** DTLS, ICE, kripto, veritabanı ve sıkıştırma **yeniden
> icat edilmeyecek** — `AGENTS.md` → "Tekerleği yeniden icat etme". El yazımı
> yalnız sinyalleşme protokolü, eşleştirme akışı, çağrı durum makinesi ve
> arayüz durumunda. Kütüphane seçimleri: `docs/adr/0003-library-decisions.md`.

- [ ] **P0.1 · Sahiplik tablosu.** 10 arayüzün her biri tek bir katmana ait olur.
      Kabul: `docs/adr/0002` §1'deki tablo `app/lib/` dosyalarıyla eşleşiyor.
- [ ] **P0.2 · `PeerStore` + `HistoryStore`** — `mkvi_core` üzerinden Rust
      implementasyonu. `crates/mkvi_bridge` zaten `listPeers`/`appendHistory`/
      `listHistory` açıyor; **bağlantı kurulmamış** (`app/pubspec.yaml`
      `mkvi_bridge` içermiyor).
- [ ] **P0.3 · `LocalSettings` + `SettingsStore` tek arka uca.** İki arayüz aynı
      anahtarları kullanıyor ama **farklı imzalar** taşıyor (senkron vs asenkron
      yazma) ve **iki ayrı yazar** var. Bağlanmazsa ayarlarda adını değiştiren
      kullanıcı karşı tarafa eski adını gönderir.
- [ ] **P0.4 · `FileSink` + `OutgoingFileSource`.** `app/lib/core/rust/rust_file_sink.dart`
      **yazıldı (2026-09-26).** Eksik kalan: `open_sink` / `write_sink` /
      `close_sink` / `abort_sink` **köprüde yok** (`mkvi_bridge/README.md:135-143`) —
      dört ince sarmalayıcı gerekiyor.
      *Düzeltme:* daha önce "çekirdek imzası değişmeli" yazılmıştı. **Yanlıştı**
      ve ölçüldü: `state.rs:155` `sink.handle.write_all(bytes)?` — `write_all`
      hep-ya-hiçtir, kısa yazma imkânsızdır. Yani `write_sink` `Ok(())` döndüğünde
      **her bayt yazılmıştır** ve Dart'ın `FileSink.write` sözleşmesi
      (`chunk.length` döndür) çekirdek **değişmeden** karşılanabilir.
- [ ] **P0.5 · `PeerTransportBinding` + `ChatChannelBinding`** — `flutter_webrtc`
      üzerine kurulu tek taşıma sınıfı. `grep -rl "package:flutter_webrtc" app/lib`
      **tam olarak 2** dosya dönmeli (mevcut `webrtc_media_backend.dart` + yeni
      transport). Üçüncüsü kapıyı kırmızıya döndürür.
- [ ] **P0.6 · Sinyalleşme protokolü** — ADR 0002 seçenek (c): tek hibernating
      `RendezvousRoom`, oturum ömürlü bilet, `identity` zarfının kaldırılması.
      `cloudflare/src/index.ts` yeniden yazılır; `isSignalPayload` beyaz listesi
      fikri korunur. **Uyumluluk zorunlu değil** (iki kullanıcı, ikisi de yeni
      sürümü kuracak).
- [ ] **P0.7 · DTLS parmak izi SAS.** `Faz 4`'teki açık güvenlik maddesini kapatır.
- [ ] **P0.8 · iki cihazlı el senaryoları** — ADR 0002 §3'teki 11 senaryo
      (`docs/manual-test.md`'ye eklenir), S11 dahil: ADR-0001'in ≥8/10 kuralı.
- [ ] **P0.9 · `main.dart` gerçek kabuk.** P0 tamamlanmadan bağlanırsa hiçbir
      mesaj gitmez. Sıra: `SettingsController` → `SessionController` →
      `ChatController` + `CallUiHost` + `MediaController` + `UpdateClient`.
      Kabuğun ele alması gereken ve **hiçbir ekranın çözmediği** dört bağ:
      1. `SessionController.restartDiscovery()` **hiçbir yerden çağrılmıyor.**
         Ayar ekranı yalnız `SettingsController.setEndpoint` çağırıyor → kullanıcı
         sunucu adresini değiştiriyor, oturum **eski adreste kalıyor.**
      2. Aynı şekilde `SessionController.setSelfName` çağrılmıyor →
         `session.selfName` bayat kalır, karşı tarafa **eski ad** gider.
      3. `ChatController.markAllRead()` çağrılmıyor → gelen satırlar hiç okunmuş
         işaretlenmiyor.
      4. `reportChannelOpen(bool)` **iki** denetleyiciye birden gitmeli
         (`SessionController` + `ChatController`) — tek olay, iki hedef.
      Çözüm: `SettingsController`'a `addListener`, değişiklik olduğunda
      `session.restartDiscovery()`. `UpdateClient.preflight()` da açılışta
      çağrılmalı.
- [ ] **P0.10 · `iceServers` zincirini tamamla — sıfır yeni paket.** Ölçüldü
      (2026-09-26): `iceServersText` **6 katmanda** tanımlı ve saklanıyor
      (`local_settings.dart`, `connection_settings.dart`, `settings_catalog.dart`,
      `settings_controller.dart`, `settings_repository.dart`, `settings_store.dart`)
      ama **`createPeerConnection`'a hiçbir yerde ulaşmıyor.** Yani kullanıcı
      ayarlardan TURN sunucusu yazıyor ve uygulama **sessizce yok sayıyor** —
      kullanıcı yanlış bir güvenlik izlenimi ediniyor. Kapat: ayar → transport.
      Kabul: bir test, ayarlarda yazılan `iceServers` değerinin
      `RTCPeerConnection` yapılandırmasına **ulaştığını** kanıtlar.
- [ ] **P0.11 · `sha2` bağımlılığını ekle** (SAS parmak izi türetimi ve `pair`
      yeteneği SHA-256 istiyor). **El yazımı hash reddedildi** — tekerlek kuralı.
      Önce `docs/adr/0003`'ün dört sorusu geçmeli.
- [ ] **P0.12 · `PairingRoom` `server.accept()` maliyetini düzelt.** Ölçüldü:
      `PairingRoom` WebSocket'i `server.accept()` ile açıyor (15 dk boyunca tam
      GB-s), `PeerRendezvous` ise `state.acceptWebSocket()` kullanıyor (maliyet
      yok). Bu bir hata değil, **kapatılabilir bir maliyet.** Yeni tasarımda tek
      DO'ya inince yapısal olarak kaybolur.

**Kabul ölçümü:** 10 arayüzün her biri için `app/lib` altında en az bir üretim
sınıfı (grep ile kanıtlanır) ve `flutter test` ile gerçek bir senaryo. Sahte
implementasyonla geçen bir kutu **kabul edilmez.**

### Kütüphane kararları (2026-09-26, `docs/adr/0003`)

**Alınacak** — tekerlek kuralının gerektirdiği, gerekçesi ölçülmüş:
`web_socket_channel` 3.0.3 (`SignalingSocket`'ı `dart:io`'dan ayırır; aynı depo
`dart-lang/http` — zaten bağımlılık, **yeni bakımcı +0**) · `file_picker` 13.1.0
(242 sürüm, 26/1 yıl, MIT) · `clock` 1.1.3.

**Alınmayacak** — 14 kalem, tekerlek kuralına veya ölçülen riskine aykırı:
`sqlx` (`mkvi_core`'un "async yok" kararına aykırı) · `libsql` (en yenisi hâlâ
pre-release) · SQLCipher (OpenSSL taşıma + Android riski) · `str0m` ve
`webrtc-rs` (kendi README'ları: capture yok, encode/decode yok, render yok;
"received less testing", Android **derleniyor ama test edilmiyor**) · `quinn`/
`s2n-quic` (QUIC NAT geçişi çözmüyor) · `flutter_riverpod`/`flutter_bloc`/
`provider`/`rxdart` · sıkıştırma (`zstd`/`brotli`/`archive`) · `sentry_flutter` ·
`pointycastle`/`cryptography` · `sqflite`/`drift`/`sembast`/`isar`/`hive`/
`objectbox`/`realm` · `mocktail`.

**Ölçülen iki düzeltme:**
1. **`dart_webrtc` doğrudan bağımlılık OLMAZ** — kanıtlandı:
   `rtc_data_channel_impl.dart` baştan sona `dart:js_interop` + `package:web`
   üzerine, yani **web-only**; masaüstü/Android'de `lib/src/native/...` kullanılıyor.
   Arayüz/iş ayrımı gerçek ama MKVI'de doğrudan bağımlılık yapmak boş iş.
2. **"WebRTC pahlı/kapalı" ön varsayımı yanlıştı** — `flutter_webrtc` MIT,
   altındaki libwebrtc BSD-3. Maliyet lisans değil, **sarmalayıcı olgunluğu**
   (718 açık issue, #2137 ve #2205 hâlâ açık). Bu yüzden "vendor fork" hâlâ gerçek
   bir seçenek olarak duruyor.

**`minisign-verify` 0.3.0 bir gün önce yayımlandı** (0.2.5 → 2026-03-03). Risk
**ölçüldü ve düşük çıktı**: iki sürümün `src/lib.rs` dosyası **SHA-256 olarak
birebir aynı** (526 satır, 12 `pub fn`, fark yok). Fark yalnız `description`,
anahtar kelimeler ve `[[bench]]` bloğunda. Yani imza doğrulayan tek güvenlik
dayanağımızda **kod değişmemiş.** İzlemede kalır.

**Gerekçesi çürüyen bir ROADMAP maddesi:** Faz 9'un "keyring Android'de yok"
gerekçesi **artık doğru değil** — `keyring` 4.x'te `android-native-keyring-store`
var. Ama o arka uç `default` özelliğinde değil ve o depo 14★ / 1 issue / son push
2026-04-21. Karar: **`keyring` 3.6.3'te kal**, Android'e geçerken özellik adları
tamamen değiştiği için (`windows-native` → `windows-native-keyring-store`) o
geçiş ayrı bir iş olacak.

---

## Faz 0 — Karar kapısı (Hafta 0)

- [x] **Flutter spike derlemesi yeşil.** `flutter_webrtc 1.6.2+hotfix.3`,
      `flutter build windows --release` → `mkvi_spike.exe`, **143 sn**,
      libwebrtc `m150.7871.02` otomatik indi. Kanıt: `spike/README.md`.
- [x] **Repo hijyeni.** `.gitattributes` (tek satır sonu kuralı), `.gitignore`
      (Flutter + beyin katmanı), 15 MB ölü feed klonu silindi.
- [x] **Karar günlüğü.** `docs/adr/0001-flutter-migration.md`.
- [ ] **Spike gün 3-7: iki makinede gerçek arama.** Protokol ve **önceden sabitlenmiş
      karar kuralı** `spike/README.md`'de. Sonuç buraya yazılacak.
      *İnsan katılımı gerekiyor: iki cihazda elle deneme.*
- [ ] **Avenox beyin kurulumu** (`avenoxai/avenoxbeyin` v3): `AGENTS.md` + skill'ler.
      Beyin **çalışma hafızası**; bu dosya **kalıcı kararlar**. İkisi karışmaz.
- [ ] **`docs/manual-test.md` gün 3-7 iki makinede elle uygulanır.** `spike/`
      iskeleti silindi ama **prosedür yaşar**; karar kuralı
      `docs/manual-test.md`'de kelimesi kelimesine duruyor. *İnsan katılımı
      gerekiyor: iki cihazda elle deneme.*

**Çıkış koşulu:** spike karar kuralı "düz port" ya da "vendor fork" demezse Faz 1 başlamaz.

## Faz 1 — Çekirdek ve iskelet

> **2026-09-26 düzeltmesi:** Bu kutular `[ ]` görünüyordu ama **fiilen
> tamamlanmıştı.** Kanıt: `crates/mkvi_core` 25 test, `crates/mkvi_bridge` 15 test
> (gerçek DLL üzerinden, `round_trip.dart`), `app/` iskeleti ve test harness'ı
> ayakta, `.\tool.ps1 gate` 12/12 yeşildi. Kutular iş bitmeden işaretlenmemişti;
> işaretlenmemiş iş **yapılmamış** iş sanılıyordu.

- [x] **`crates/mkvi_core`:** `security.rs` Tauri'den ayrıldı. Doğrulandı:
      `Cargo.toml`'da `tauri` **yok**, `src/` içinde `use tauri` **yok**.
      *Not:* 14 yorumda "Tauri" geçiyor — hepsi tarihsel kayıt ve wire şeması
      adı; bağımlılık değil.
- [x] **Sessiz sır üretimi kapatılır.** `security.rs:166-168` ve `:356-358`:
      keyring boş **ve** diskte bir şey varsa `KeyringEntryMissing` fırlatır, yeni
      kimlik üretmez. Yazma-okuma doğrulaması `store_verified` (`:371-381`).
      `SecretOrigin::from_known_peers` / `from_database_file` ayrımı bunu
      mümkün kılıyor.
- [x] **`crates/mkvi_bridge`:** `flutter_rust_bridge` yüzeyi. **Yedi alan çağrısı
      doğrulandı** (`api.rs` 9 `pub fn`, biri kurucu) + `open_core_with_store`
      (`#[frb(ignore)]`, Android'in bağlanacağı dikiş).
- [x] **`app/`** Flutter iskeleti + test harness'ı (`app/test/support/`).
- [x] **Tek kapı:** `.\tool.ps1 gate`. 2026-09-26'da 9 adıma indirildi: `tsc`/
      kök `vitest`/`cargo test src-tauri` **kaldırıldı** (0.1.x emekli), `mkvi_bridge`
      ve `design` analizi **eklendi**, sürüm kapısı ve `CLAUDE.md` aynası **eklendi**.
- [x] **CI** (`ci.yml`) bu kapıyı PR'da koşuyor: sürüm · Rust çekirdek + köprü
      (3 işletim sistemi) · tasarım · Flutter · Worker.

**Çıkış koşulu:** "Rust'tan bir değer okuyup Dart'ta gösteriyor" — **kısmen
karşılanmadı**: `mkvi_bridge` gerçek DLL üzerinden çalışıyor (`round_trip.dart`
geçiyor) ama **`app/` onu import etmiyor.** Bu artık Faz 0.5 → P0.2'nin konusu.

## Faz 2 — Tasarım sistemi ve kabuk

- [x] **`design/tokens.json`** → generator → `tokens.g.dart`. 4 tema × 4 vurgu, 29 rol,
      816 ölçülmüş kontrast oranı, 17 test. Ölçülen en kötü oranlar:
      video placeholder 1.17:1 → **17.11:1**, odak halkası 1.00:1 → **3.28:1**,
      ayırıcı 1.6–2.3:1 → **3.59:1**, ilerleme izi 1.24:1 → **3.59:1**,
      zaman damgası 4.47:1 → **4.99:1**, devre dışı metin 3.20:1 → **4.87:1**.
- [x] **Kapı kırılabilir olduğu kanıtlandı:** iki negatif kontrol yapıldı — odak
      halkası vurguya eşitlenince ve sahne rengi açık yapılınca test kırmızıya
      düştü. Hata mesajı hangi tarihsel kusuru geri getirdiğini adıyla söylüyor.
- [ ] **Vurgu dolu düğme, yükseltilmiş yüzeyde `borderStrong` kenarı alacak.**
      Bu bir token kuralı değil, arayüz kuralı: token testi bunu ölçemez,
      vurgu dolu her düğme `bg`/`surface` üzerinde durmalı, `surfaceRaised`/
      `surfaceSoft` üzerinde ise kenarı olmalı. Kod yazarken uygulanacak.
- [ ] **Sahne kutuplaşması testle korunuyor** (`stage` koyu, `textOnStage` açık,
      her temada) — 0.1.x'teki 1.17:1 sınıfının yapısal olarak geri dönmesini
      engelleyen şey bu.
- [ ] **Ölçek/yoğunluk her yerde** (0.1.x'te `fontScale` ilk ekranlarda etkisizdi).
- [ ] **Üç ekran:** eşleştirme, çalışma alanı, arama.

**Çıkış koşulu:** `dart test` kontrast testleri yeşil; üç ekran tema/vurgu/ölçek
kombinasyonlarında bozulmadan.

## Faz 3 — Sinyalleşme

- [ ] **`rendezvous` Dart'a taşınır**, zarf doğrulama ve ayrışma bildirimiyle.
- [ ] **Ortak golden vector:** TS ve Dart aynı dosyadan aynı testi koşar. 0.1.x'teki
      base64 alfabesi ve UUID biçimi hataları tam olarak bu eksiklikten doğdu.
- [ ] **Worker sözleşme testleri** CI'da.

## Faz 4 — Kimlik, eşleştirme, geri bağlanma

- [ ] **Faz 1 güvenlik açığı kapatılır:** SAS ifadesi DTLS parmak izine bağlanır
      (SDP'den veya `getStats`'ten — spike gün 3 hangisini verirse). Sinyal
      sunucusunu kontrol eden biri artık iki tarafa da aynı ifadeyi gösteremez.
- [x] **`SetupState` + oturum denetleyicisi (saf Dart).** 79 test. Beyaz ekranın kök
      nedeni yapısal olarak kapandı: eşleştirme ekranı **yalnız** `firstRun` ve
      açık `needsPairing` durumlarından erişilebilir (`showsPairingScreen` tek
      bekçi). Başarısız eş okuma, şifreleme hatası, anahtar kasası eksikliği ve
      bozuk kayıt artık `broken(reason)` — eşleştirme ekranına düşmüyor, Türkçe
      eyleme dönük sebep veriyor. Yeniden bağlanma: 700 ms → 12 s; **geçici kimlik
      hatası döngüyü öldürmüyor** (eskiden kalıcı `return` vardı), bayat dönemin
      sökümü yeni dönemin durumunu ezmiyor.
- [ ] **Keyring hataları yüzeye çıkar**, sessizce yeni kimleme düşmez.
      *(Çekirdekte `KeyringEntryMissing` eklendi; Dart yüzeyi session'a bağlı.)*
- [x] **İsimler:** ilan edilen ad yetkili, takma ad ikincil ve yalnız yerelde.
      34 test: takma ad ne görünen adı ne de kaydedilen `display_name`'i
      değiştiriyor, tel üzerinden **hiç** gitmiyor (serileştirilmiş çıktı
      üzerinden iddia), bir eşin takma adı diğerine sızmıyor, yeniden eşleşmede
      daha önce kayıtlı ad korunuyor.
- [ ] **GERÇEK VERİ DOĞRULAMASI — "Kişi" tuzağı.** `App.tsx:438` kaydedilen
      `display_name` alanına `peerAnnouncedName || "Kişi"` yazıyordu ve `:159`
      onu **karşı tarafın gerçek adıymış gibi** geri okuyordu. Bu makinede
      `history.sqlite3` gerçekten var (28 KB) — yani bir eşleşme yapılmış;
      kuzenin veritabanında da "Kişi" yazıyor olabilir. Dart tarafı bunu
      "bilinmiyor" sayıyor (migration gerekmiyor) ama **kanıtlanmalı**:
      `mkvi_core` ile gerçek veritabanını açıp `peers()` çalıştıran tek seferlik
      bir `cargo run`. Kaynak: `%APPDATA%\com.mkvi.desktop\history.sqlite3`, anahtar
      Credential Manager'da `app.mkvi.desktop / history-key-v1`. *Bu aynı zamanda
      çekirdek ayrımının gerçek veriye karşı ilk kanıtı olur.* Ağır derleme
      olduğu için ajanlar bitince koşulacak.

## Faz 5 — Arama

- [x] **Çağrı durum makinesi (saf Dart, donanımsız).** 110 test. Dört canlı kusur
      testle kilitli: (1) cevap ekranı olmadan arama açılmıyor — `accept()` dışında
      hiçbir yol `connected`'a gidemiyor; (2) **ara tarafta 45 sn zil zaman aşımı**
      yoktu, diyalog sonsuza kadar kalıyor ve tuşlar kilitliydi; (3) `call-declined`
      hiç işlenmiyordu, şimdi ayrı bir sonuç; (4) kaleye kabul medyadan önce
      gidiyordu, artık `call-accept` **önce** gönderiliyor ve yarışta (arayan
      zaman aşımına uğradıysa) kabul reddediliyor.
      Sipariş sözleşmesi veri olarak modellendi: `accept` → `[SendFrame, PublishMedia]`.
      Sesli→görüntülü yükseltme yeni çağrı ve yeni müzakere üretmiyor.
- [ ] **`stopCall` rastgele id gönderiyor (yeni bulundu).**
      `peer-transport.ts:203`: `activeCallId ?? pending ?? incoming ?? randomTransferId()`
      — hiç çağrı yokken **hiçbir çağrıya ait olmayan rastgele bir id ile**
      `call-end` gönderiyor. Karşı taraf bu id'yi bilmediği için `finishCallRequest`
      çalışmıyor, sonra `stopCall(false)` ve `remote-call-ended` yayıyor: yani
      **kimsenin kapatmadığı bir arama, karşı tarafın kendi medyasını düşürüyor.**
      Dart tarafında `end()` canlı çağrı yoksa saf no-op; donmuş hatta düzeltilmedi.
- [ ] **`remote-stream` yanlış sinyalle `connected`'a atıyor (yeni bulundu).**
      `App.tsx:399`: `outgoing` sırasında gelen bir `remote-stream` doğrudan
      `connected` yapıyor, `onStartCall`'in koyduğu `connecting` durumunu atlayarak.
      Dart makinesinde `connected`'a giden tek kapı `onMediaReady()`.

- [ ] **Cevap / Reddet** ekranı; iki tarafta da 45 sn zil zaman aşımı; cevapsız
      arama kaydı; `call-declined` işlenir. *(Durum makinesi tamam; ekran kaldı.)*
- [ ] **Kabul medyadan önce** — diyalogun verdiği sözün tutulması.
- [ ] **Kamera/mikrofon/ekran:** cihaz değiştirme, hata sınıflandırması (Türkçe),
      **arama sırasında kamerayı açma**, sesli→görüntülü yükseltme.
- [ ] **Ekran paylaşımı için "ilk kare bekleniyor" durumu.** Plugin sessizce boş
      track verebiliyor (`#2137`); `outbound-rtp.framesEncoded` izlenmeli.
- [ ] **PiP kendi görüntü + tam ekran**, uzak kamera gelince otomatik geçiş.

## Faz 6 — Sohbet ve dosya

- [ ] Mesaj listesi + geçmiş (şifreli SQLite), gönderme durumu.
- [ ] Dosya aktarımı çekirdek üzerinden akışlı yazım, ilerleme, iptal, çakışma yok.

## Faz 7 — Güncelleme, dağıtım, açık kaynak

- [ ] **Yayın anahtarı yeniden üretilmeli (prehashed).** Doğrulandı: `tauri.conf.json`
      içindeki anahtar minisign'in **eski `Ed`** biçiminde. Katı doğrulayıcı
      (`update.rs:116`, `allow_legacy` sabit `false`) her `ED` imzasını kabul eder,
      ama bu anahtar yalnız `Ed` imzası üretebilir — yani **0.2.0'ın** doğrulaması
      sessizce her şeyi reddeder. `mkvi_core::update` bunu `LegacyKey` hatası olarak
      **adıyla** söyler (testli).
      *Düzeltme, 2026-09-26:* bu anahtar **0.1.x'i engellemiyordu.** Ölçüldü:
      `tauri-plugin-updater` 2.10.1 `allow_legacy = true` ile çağırıyor
      (`src/updater.rs:1461`) ve `minisign-verify` 0.3.0 iki etiketi de kabul ediyor
      (`lib.rs:296-299`). 0.1.x'i **ölü feed** durdurdu, anahtar değil. Aşağıdaki
      yayın hattı maddeleri bu yüzden feed'i birincil iş sayar.
      **Kök çözüm:** yeni `tauri signer generate` ile prehashed anahtar +
      `TAURI_SIGNING_PRIVATE_KEY` secret'ının yenilenmesi.
      **Sonuç:** 0.1.x istemcileri kendini güncelleyemez (zaten ölü feed yüzünden
      edemiyorlardı) — ilk Flutter sürümü elle kurulur.
- [ ] **Önce feed'i ayağa kaldır.** `ancapenguin/mkvi-updates` anonim isteğe **404** veriyor
      (canlı doğrulandı). Sebep ya yok ya da gizli; `raw.githubusercontent.com` gizli bir
      depoyu kimlik doğrulanmamış istemciye **hiç servis etmez** — deploy key yalnız *yazma*
      izni verir. İki yol: depoyu public yap, ya da `ancapenguin/mkvi` public olunca feed'i
      bu deponun Releases'ine taşı (`releases/latest/download/latest.json`, resmî Tauri
      yolu) ve `mkvi-updates`'i + deploy key'i emekliye ayır.
- [ ] **`mkvi_core::update`:** `latest.json` oku → sürüm karşılaştır → indir →
      **imzayı doğrula** → kur. Doğrulama indirilen baytın **tamamı** üzerinde,
      bayt bayt kontrolsüz geçilemez. *(Çekirdek kısmı yazıldı: 24 test.)*
- [ ] **`release.yml`:** etiketle tetiklenir, taslak yayın, sürüm üç dosyada eşleşmeli.
- [ ] **Feed GitHub Releases'e taşınır** → `mkvi-updates` deposu ve deploy anahtarı
      emekli. `ancapenguin/mkvi` **public** olunca updater endpoint'i
      `releases/latest/download/latest.json` olur (resmi Tauri yöntemi).
- [ ] **Public'a çıkış:** lisanslar, `SECURITY.md` (özel bildirim kanalıyla),
      `CONTRIBUTING`, `CODE_OF_CONDUCT`, `THIRD-PARTY-NOTICES`, `cloudflare/README.md`.
- [ ] **Yanlış iddialar düzeltilir:** README "tek kullanımlık kod" diyor (aslında kayan
      pencere, `MAX_ADMISSIONS = 8`); CLAUDE "CSP daraltıldı" diyor (aslında `https:`
      jokeri *genişletilmiş*); "0.1.4 indirilebilir" diyor (link ölü).

**Çıkış koşulu:** 0.2.0 yayında, iki cihazda kendiliğinden güncelleniyor.

## Faz 8 — Ölü kodun temizliği — **TAMAMLANDI (2026-09-26)**

- [x] **`spike/` silindi.** El testi prosedürü `docs/manual-test.md`'ye kurtarıldı,
      karar kuralı korundu. İskelet kalıcı değildi, zaten yalnız README kalmıştı.
- [x] **`src/`, `src-tauri/` silindi.** 0.1.x emekliye ayrıldı. Bu, ROADMAP'ın
      eski koşulundan (0.2.0 + iki cihazda gerçek test) **erken** gerçekleşti:
      kullanıcı kararı, iki kullanıcının da elle kuracağı.
- [x] `index.html`, `vite.config.ts`, `tsconfig*`, kök `package.json` gitti.
- [ ] **Kalan:** `cloudflare/` içindeki Worker testi hâlâ `vitest` kullanıyor ve
      `cloudflare/package.json` **kalıyor** — sinyalleşme sunucusu 0.2.0'ın parçası.

## Faz 9 — Android

- [ ] `keyring` Android'de yok → `flutter_secure_storage` beslemeli `SecretStore`.
- [ ] Ekran paylaşımı **MediaProjection** ister; `getDisplayMedia` Android WebView
      eşdeğeri değildir.
- [ ] Kamera/mikrofon izin akışı ve kalıcı izin iptali.

---

## Çalışma kuralları (acıyla öğrenildi)

- **Tam kapı yeşil olmadan commit önerme:** `.\tool.ps1 gate`.
- **DOSYA İÇERİĞİNİ ASLA PowerShell İLE YAZMA.** `Get-Content -Raw` Türkçeyi bozar,
  `Set-Content -Encoding utf8` BOM yazar ve derlemeyi kırar. Kurtarma:
  `git checkout -- <dosya>`. Bayt seviyesinde yamalar (ör. ham NUL → `\0`) istisnadır,
  çünkü yeniden kodlama yapmaz.
- **Türkçe metin UTF-8, BOM'suz.** Bir dosyayı düzenledikten sonra
  `grep -n 'Ã\|Å\|Ä' <dosya>` çalıştır; çıktı boş olmalı.
- **Kod yorumları İngilizce**, kullanıcıya görünen her string Türkçe.
- **Worker içerik taşımaz.** `isSignalPayload` anahtar bazında beyaz liste kullanır.
  Yeni alan eklemek Worker'ı içerik tüneline çevirir; gerekçesiz genişletme.
- **Protokol daraltmak kırıcıdır.** `isSignalPayload`'dan alan çıkarmak, o alanı hâlâ
  gönderen eski istemcileri `close(1008)` ile düşürür.
- **Özel kripto yazma.** Yalnız denetimli crate'ler (`ed25519-dalek`,
  `chacha20poly1305`). Yeni şema gerekiyorsa önce sor.
- **Ajanlar commit atmaz, push atmaz.** Her dosyanın tek sahibi olur; sahiplik
  çakışması iki ajanın işini birbirine ezdirir. Commit'i lead engineer yapar.
- **Lane/ajan raporu iddiadır, kanıt değil.** Her iddia kodda veya resmî dokümanda
  doğrulanır.
