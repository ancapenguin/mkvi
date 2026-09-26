# 0003 — Kütüphane kararları: her katmanda ne alınacak, ne alınmayacak

**Tarih:** 2026-09-26
**Durum:** **Kabul.** Bir kısmı lead engineer'a devredildi (§15) — o maddeler bu
belgede *öneri* olarak durur, karar değil.
**Etki:** `app/pubspec.yaml`, `crates/mkvi_core/Cargo.toml`,
`crates/mkvi_bridge/Cargo.toml`, `THIRD-PARTY-NOTICES.md`,
`docs/adr/README.md` (satır eklenecek)
**İlgili:** `docs/adr/0001` (Flutter taşıması) · `docs/adr/0002` (taşıma mimarisi)

> Bu bir **karar kaydıdır**, kullanım kılavuzu değildir. Yazıldığı gün doğru olan
> betimlemeleri tarihsel olarak korur.

> ### Durumlandırma — okumadan önce
>
> **Bu belge yazılırken hiçbir şey derlenmedi, kurulmadı ve koşulmadı.** Ne
> `cargo build`, ne `pub get`, ne `flutter test`, ne de `cargo test` çalıştı. Her
> "derleniyor" denecek ifade bilerek kullanılmadı. Bir paketin *kurulup
> denendiğine* dair hiçbir iddia bu belgede yoktur.
>
> Kaynak kod okunarak doğrulananlar "**kodda okundu**", uzak depodan alınanlar
> "**kaynaktan okundu**" olarak işaretlidir. Sayısal istatistiklerin tamamı
> 2026-09-26 tarihinde **crates.io API**, **pub.dev API**, **pub.dev paket
> sayfası** ve **GitHub REST API**'den okundu; kaynağı satırda yazılıdır.
> GitHub API'si anonim çağrılarda saatte 60 istekle sınırlı olduğu için
> değişkenler ölçüldükten sonra sabitlendi.

## Bağlam

Kullanıcı 2026-09-26'da kalıcı bir kural koydu: *"bazı belirgin şeylerde çok iyi
bir kütüphane varsa bize uyan kesinlikle al."* `AGENTS.md` bunu genel bir
kurula çevirdi: DTLS, ICE, DTLS-SRTP, bir dosya biçimi, bir sıkıştırma algoritması
veya bir veritabanı motoru **kendi başımıza yazılmaz.**

Bu, bir eğilim değil bir **yükümlülük**tür; çünkü yazılmayan şeyin bedeli
 görünmez: kimsenin güvenmediği, kimsenin güncellemediği ve iki kişilik bir
 projede değiştiremeyeceğimiz bir kod parçası. Ama "her şeyi al" diye okumak da
yanlış olur; o zaman da el yazdığımız her satır bir bağımlılık sürüm
güncellemesine dönüşür. Bu belgenin işi ikisini ayırmak.

ADR 0002 bu sorunun **mimari** yarısını cevaplıyor (hangi taşıma, hangi güvenlik
varsayımları). Bu belge **kütüphane** yarısını cevaplıyor. İkisi birlikte
okunmalı; biri diğeri olmadan eksiktir.

## Yöntem

`AGENTS.md`'deki dört soru, her aday için aynı sırayla soruldu:

1. Bu işi yapıyor mu, yoksa sadece isim mi benzer?
2. Bakımı kim yapıyor, son sürümü ne zaman?
3. Denetim/lisans durumu ne?
4. Doğru mu bildiğimiz?

Dördüncü soru bu belgede en pahalı soruydu, çünkü **birçok şeyi yanlış
biliyduk.** §2 bunları tek tek listeler.

## 1. Mevcut bağımlılık envanteri

Altı ayrı bağımlılık yüzeyi var. Kilit dosyalarındaki **çözümlenmiş** sürümler
okundu (aralıklar değil); çözümlenen sürüm, `pubspec.yaml`/`Cargo.toml`'daki
aralıktan farklı olabilir.

| Yüzey | Kilit dosyası | Paket sayısı | `THIRD-PARTY-NOTICES.md` iddiası | Ölçülen | Tutarlı? |
|---|---|---|---|---|---|
| Rust çekirdek | `crates/mkvi_core/Cargo.lock` | 189 | 189 | 189 | ✅ |
| Rust köprüsü | `crates/mkvi_bridge/Cargo.lock` | 238 | 238 | 238 | ✅ |
| Dart/Flutter uygulaması | `app/pubspec.lock` | 76 | 76 | 76 | ✅ |
| Worker | `cloudflare/package-lock.json` | 163 | 163 | 162 + kök | ✅ |
| Tasarım | `design/pubspec.lock` | 47 | 47 | 47 | ✅ |
| Köprü Dart tarafı | `crates/mkvi_bridge/dart/pubspec.lock` | 50 | 50 | 50 | ✅ |

**Paket sayıları tutarlı.** Doğrudan bağımlılıkların sürümleri de tek tek
karşılaştırıldı ve tamamı kilit dosyasındaki çözümlenmiş değerle eşleşiyor:
`flutter_webrtc 1.6.2+hotfix.3`, `dart_webrtc 1.8.2`, `webrtc_interface 1.5.1`,
`flutter_secure_storage 11.2.0`, `path_provider 2.1.6`, `http 1.6.0`,
`cupertino_icons 1.0.9`, `flutter_lints 6.0.0`, `freezed 3.2.5`,
`build_runner 2.15.1`, `freezed_annotation 3.1.0`, `flutter_rust_bridge 2.13.0`,
`ed25519-dalek 2.2.0`, `chacha20poly1305 0.10.1`, `keyring 3.6.3`,
`rusqlite 0.32.1`, `libsqlite3-sys 0.30.1`, `minisign-verify 0.3.0`,
`zeroize 1.9.0`, `rand_core 0.6.4`, `serde 1.0.229`, `serde_json 1.0.151`,
`base64 0.22.1`, `thiserror 2.0.21`, `tempfile 3.27.0`, `curve25519-dalek 4.1.3`,
`wrangler 4.114.0`, `typescript 5.9.3`, `vitest 4.1.10`.

**Bu iyi haber:** bildirim dosyası, depodaki kilit dosyalarının iyi bir kaydı.
Elle düzeltilecek bir sürüm hatası yok.

### 1.1 Doğrudan/dolaylı ayrımı (ölçüldü)

`pubspec.lock` ve `Cargo.toml` okunarak her paketin `dependency: direct |
transitive` durumu veya `[dependencies]` / `[dev-dependencies]` / `[target.*.dependencies]`
başlığı belirlendi. Dikkat çeken üç ayrım:

- **`keyring` doğrudan ama hedef-koşullu.** Üç ayrı `[target.'cfg(...)'.dependencies]`
  bloğunda geçiyor; `windows-native` (Windows), `apple-native` (macOS),
  `sync-secret-service` + `crypto-rust` (Linux). **Android ve iOS'ta hiç
  tanımlı değil.** `AGENTS.md` ve `ROADMAP.md` Faz 9'un bu yüzden blokaj
  olduğunu söylemesi doğru.
- **`base64` iki ayrı yerde doğrudan.** Hem `mkvi_core` hem `mkvi_bridge`
  `Cargo.toml`'unda duruyor. Aynı sürümü (0.22) çözümleniyor, yani çift
  derleme yok — ama gerekçe farklı: çekirdekde anahtar baytları, köprüde imza
  tel biçimi. Yanlış anlaşılırsa biri silinip diğeri kırılır.
- **`tempfile` ve `base64` `mkvi_bridge` için de `dev-dependencies` ve
  doğrudan.** `tempfile` yalnız geliştirme; `base64` üretimde.

### 1.2 Lisans özeti (yeniden okundu, değişmedi)

MKVI `Apache-2.0 OR MIT`; `cloudflare/` ayrı olarak `AGPL-3.0`. Üçüncü taraf
paketlerin hiçbiri MKVI'nin lisansını değiştirmiyor. Copyleft yükümlülüğü
doğuran tek giriş `cloudflare/AGPL-3.0`, ve o birinci taraf kod.

## 2. `THIRD-PARTY-NOTICES.md` ile karşılaştırma — bulunan farklar

Dosya iyi yazılmış; bulduğum dört maddenin üçü **eksik bilgi**, biri
**karara bağlanmamış bir konu**.

### 2.1 `webrtc_interface` lisansı — uyarı çözüldü

`THIRD-PARTY-NOTICES.md` §3, `webrtc_interface 1.5.1` için şunu yazıyor:
*"Lisansı beyan etmiyor... lisans belirsizliği ticari dağıtımda sorun
yaratabilir."* Bu, bugüne kadar doğru bir uyarıydı. **Bugün çözüldü:**

- Depo **`flutter-webrtc/webrtc-interface`** (tire ile; `_` değil). 23 yıldız,
  10 açık issue, son push 2026-03-16, arşivlenmemiş.
- Depo kökünde **`LICENSE` = MIT** (okundu: "MIT License / Copyright (c) 2021
  Flutter WebRTC").
- **Pubspec'te `license:` alanı hâlâ yok** (okundu) — yani uyarının *tam* ifadesi
  doğru, sadece sonucu bilinmiyordu.

**Karar:** lisans **MIT'tir**, kaynak deposundan. `THIRD-PARTY-NOTICES.md`'deki
"⚠️ beyan edilmemiş" satırı, **lisans bilinmiyor** diye değil **"lisans
pubspec'te beyan edilmemiş, depoda MIT"** diye düzeltilmeli. Ticari risk yok.

### 2.2 `flutter_webrtc` ve `dart_webrtc` de `license:` beyanı içermiyor

Aynı durum (`flutter_webrtc` pubspec'inde `license:` yok — okundu) ama her iki
deponun kökünde `LICENSE` = **MIT** (GitHub API `license.spdx_id` = MIT).
`THIRD-PARTY-NOTICES.md` bunları zaten MIT olarak listeliyor; **doğru**. Sadece
kaynak gösterimi pubspec yerine depo olmalı.

### 2.3 `minisign-verify 0.3.0` **bir gün önce** yayımlandı

crates.io sürüm listesi (okundu): `0.2.5` → 2026-03-03, **`0.3.0` → 2026-09-25**.
Yani MKVI'nin kilit dosyasındaki `minisign-verify 0.3.0`, **yazıldığı gün bir
gün önce** yayımlanmış bir sürüm. Toplam 14.7M indirme, `recent_downloads`
6.1M — yani *crate* olarak olgun, ama *bu sürüm* bir günlük.

**Karar:** bu bir red gerekçesi değil, bir **izleme** maddesi. Bir imza
doğrulayıcısının imza doğrulaması MKVI'nin tek güncelleme güvenliği
dayanağıdır; `ROADMAP.md` Faz 7'de yayın öncesi `0.3.0`'a karşı somut bir
test çalıştırılmalı. `THIRD-PARTY-NOTICES.md`'ye "yayımlandığı gün" notu
düşmeli, çünkü bu tür bir bağımlılıkta *tarih* bilgidir.

### 2.4 `mkvi_bridge` kilidinin "beklenmedik" listesi eksik

`THIRD-PARTY-NOTICES.md` §2, köprünün `Cargo.lock`'inde "beklenmedik bir şey"
olarak `tokio 1.53.1`, `dashmap`, `regex`, `wasm-bindgen` ve `web-sys`
sayıyor. Kilit dosyası tarandı; bu doğru **ama liste eksik:**

| Paket | Kiltteki sürüm | Bildirimde adı geçiyor mu? |
|---|---|---|
| `tracing` | 0.1.44 | **hayır** |
| `tracing-core` | 0.1.36 | **hayır** |
| `log` | 0.4.34 | **hayır** |
| `anyhow` | 1.0.104 | **hayır** |
| `dashmap` | 5.5.3 | evet (sürümsüz) |
| `tokio` | 1.53.1 | evet |

Hepsi `flutter_rust_bridge`'ın kendi çalışma zamanı bağımlılıklarıdır, yani
MKVI'nin seçimi değil — ama bildirimin kendi kuralı *"tablolar doğrudan
bağımlılıkları ve **lisansı dikkat çeken** dolaylı bağımlılıkları kapsar"*
diyor. `tracing` ve `log` bu eşiği aşıyor (lisansı ayrı `Apache-2.0` / `MIT OR
Apache-2.0`, ayrı kaynağa sahip). Küçük ama gerçek bir eksik.

### 2.5 Rus çekirdeğin sürüm boşluğu — bildirim dosyasında **yok**

`mkvi_core` beş Rust bağımlılığında geride kalmış durumda. crates.io
`max_stable_version` (okundu, 2026-09-26):

| Paket | Kilitteki | O günkü en güncel | Fark | Güncelleme tarihi |
|---|---|---|---|---|
| `rusqlite` | 0.32.1 | **0.40.2** | 8 minor | 2026-08-08 |
| `libsqlite3-sys` (dolaylı) | 0.30.1 | **0.38.2** | 8 minor | 2026-08-08 |
| `keyring` | 3.6.3 | **4.2.0** | **bir major** | 2026-08-29 |
| `ed25519-dalek` | 2.2.0 | **3.0.0** | **bir major** | 2026-07-06 |
| `curve25519-dalek` (dolaylı) | 4.1.3 | **5.0.0** | **bir major** | 2026-07-06 |
| `chacha20poly1305` | 0.10.1 | 0.11.0 | bir minor | 2026-08-05 |
| `rand_core` | 0.6.4 | 0.10.1 | 4 minor | 2026-09-02 |
| `base64` | 0.22.1 | 0.23.1 | bir minor | 2026-08-04 |
| `zeroize` | 1.9.0 | 1.9.0 | — güncel | — |
| `serde` / `serde_json` / `thiserror` / `tempfile` | — | — | güncel | — |
| `flutter_rust_bridge` | 2.13.0 | 2.13.0 (stable) | — güncel | 2026-08-23 |

**Karar:** bu bir *güvenlik aciliyeti* değil — hiçbiri terk edilmiş değil ve hepsi
yayımlanmaya devam ediyor. Ama `keyring` 3→4 ve `ed25519-dalek` 2→3 **iki büyük
sürüm** ve ikisi de güvenlik yolunda. `THIRD-PARTY-NOTICES.md` sürümleri
doğru yazıyor; eksik olan şey **"bu sürümler neden geride"** sorusunun cevabı.
§8'de alınmaması, §15'te lead'e devredilmesi gereken bir madde olarak duruyor.

## 3. Katman katman "bunu almalı mıyız?"

| # | Katman | Sorun | Aday | O günkü sürüm / tarih | Bakım kanıtı | Lisans | Zaten var mı? | Karar |
|---|---|---|---|---|---|---|---|---|
| 1 | **P2P taşıma** | WebRTC | `flutter_webrtc` | 1.6.2+hotfix.3 · 2026-09-15 | 4491★ · 718 açık issue · push 2026-09-22 | MIT | **Evet** | **Kal** (sürüm sabit) |
| 2 | " | arayüz ayrımı | `webrtc_interface` | 1.5.1 · 2026-03-16 | 23★ · 10 issue · push 2026-03-16 | MIT (depoda) | Dolaylı | **Kal** |
| 3 | " | arayüz uygulaması | `dart_webrtc` | 1.8.2 · 2026-09-04 | 35★ · 11 issue · push 2026-09-04 | MIT | Dolaylı | **Kal** |
| 4 | **Sinyalleşme istemcisi** | WebSocket | `dart:io` `WebSocket` (yazılı) | — | — | BSD-3 (Dart) | **Evet** | **Değiştir → `web_socket_channel`** |
| 5 | **Sinyalleşme sunucusu** | Worker | sıfır çalışma zamanı bağımlılığı | — | — | AGPL-3.0 (birinci taraf) | **Evet** | **Kal** |
| 6 | **Eşleştirme akışı** | kod üretimi/okuma | `barcode` 2.2.9 · 2025-01-25 · `mobile_scanner` 7.4.2 · 2026-09-14 | — | `qr_flutter` 4.1.0 **3 yıldır güncellenmedi** | MIT | Hayır | **Şimdi alma; lead'e seçenek** |
| 7 | **Mesaj çerçeveleme** | tel biçimi | `peer_protocol.dart` (kendi) | — | `vectors/wire-v1.json` ile sözleşmeli | birinci taraf | **Evet** | **Kal — bu bizim işimiz** |
| 8 | **Dosya aktarımı** | 512 MB, ilerleme, iptal | DataChannel + `mkvi_core::files` | `fileChunkBytes = 16 KB` → 512 MB'de **32.768 gönderim** | — | — | **Evet** | **Kal; chunk ölçümü lead'e** |
| 9 | " | dosya seçme | `file_picker` 13.1.0 · 2026-09-15 · `desktop_drop` 0.8.4 · 2026-09-01 | `file_picker` 242 sürüm / 26 son 1 yıl · `desktop_drop` 24 sürüm / 7 son 1 yıl | MIT | Hayır | **Al** (`file_picker`), **`desktop_drop` karara bağlı** |
| 10 | **Yerel şifreli depolama** | mesaj geçmişi | `rusqlite` 0.32.1 → 0.40.2 | `bundled-sqlcipher` **var** (0.40 `Cargo.toml`'unda okundu) | 4409★ · 170 issue · push 2026-09-25 | MIT | **Evet** | **Kal; SQLCipher özelliği lead kararı** |
| 11 | " | alternatif motor | `sqlx` 0.9.0 · 2026-05-21 · `libsql` 0.9.30 · 2026-03-19 | `sqlx` 152.5M · `libsql` 2.2M | MIT / MIT | Hayır | **Alma** |
| 12 | **Cihaz anahtarı / OS kasası** | Ed25519 tohumu, DB anahtarı | `keyring` 3.6.3 → **4.2.0** | **4.x'te `android-native-keyring-store` var** (okundu) | 768★ · push 2026-09-15 · **0 açık issue** | MIT OR Apache-2.0 | **Evet** | **4.x'e geç: lead kararı, Android'i çözer** |
| 13 | **Mesaj teslimi / yeniden bağlanma** | yeniden bağlanma döngüsü | `reconnect_driver.dart` (kendi) | — | 79 test | birinci taraf | **Evet** | **Kal** |
| 14 | **Sıkıştırma** | büyük dosya/mesaj | `zstd` 0.14.0 · 2026-09-04 | 399.8M indirme | **MIT** (depoda okundu) | Hayır | **Alma** — §12 gerekçesi |
| 15 | **Loglama / teşhis** | çökme raporu | `sentry_flutter` 9.30.1 · 2026-09-22 | 235 sürüm / 44 son 1 yıl | **Dışarıya veri gönderir** | Hayır | **Alma** (§14) |
| 16 | " | Rust tarafı | `tracing` 0.1.44 · 2025-12-18 | 875.8M indirme | MIT | Dolaylı (FRB) | **Alma; `log`/`eprintln!` yeterli** |
| 17 | **Durum yönetimi** | Flutter | `ChangeNotifier` (kendi) · `flutter_riverpod` 3.4.3 · 2026-09-03 | 7392★ · 160 issue · push 2026-09-22 | MIT | Hayır | **Alma** (§8) |
| 18 | " | alternatif | `flutter_bloc` 9.1.1 · 2025-05-02 (**1 yıldır sürüm yok**) · `provider` 6.1.5+1 · 2025-08-19 | — | MIT | Hayır | **Alma** |
| 19 | **Test yardımcıları** | fake clock | `fake_async` 1.3.3 · 2025-01-28 · `clock` 1.1.3 · 2026-08-28 · `mocktail` 1.0.5 · 2026-04-10 | Üçü de `dart.dev`/flutter.dev | BSD-3 / MIT | Hayır | **`clock` alınabilir; `mocktail` hayır** (§14) |
| 20 | **Async/stream** | stream birleştirme | `rxdart` 0.28.0 · 2024-06-14 (**27 aydır sürüm yok**) | 132 sürüm | BSD-3 | Hayır | **Alma** |

### 3.1 Ölçülmeyen popülerlik rakamları — dürüstlük notu

**pub.dev indirme sayısını veremedim.** Paket sayfasındaki "Haftalık
İndirmeler" grafiği JavaScript ile yükleniyor; HTML'de bir sayı yok. Bu
belgede Dart paketleri için **indirme rakamı uydurulmamıştır**; onun yerine
*doğrulanabilir* ölçütler kullanıldı:

- **crates.io**: `downloads` (toplam) ve `recent_downloads` alanları API'den
  doğrudan okundu. `recent_downloads` alanının **pencere tanımını kaynaktan
  doğrulamadım** — sayıyı veriyorum, "son 90 gün" gibi bir etiket **eklemiyorum.**
- **pub.dev**: sürüm, yayım tarihi, son 365 gündeki sürüm sayısı, toplam sürüm
  sayısı, geri çekilmiş sürüm sayısı, `isDiscontinued` ve `publisherId`.
- **GitHub**: yıldız, açık issue, son push, arşivlenme, lisans.

**"Doğrulanmış yayıncı" rozetini doğrulayamadım ve bu belgede kullanmıyorum.**
34 paketin sayfasını taradım; `material-icon-verified.svg` rozeti **34'ünde de**
var. Yani rozet ayırt edici değil — ayrım gücü sıfır. Bu, ADR 0001'in
`flutter_webrtc` için yazdığı *"doğrulanmış yayıncı"* ifadesinin **bugün
doğrulanamayacağı** anlamına gelir. 0001'e dokunmuyorum; burada kayda geçiriyorum.

## 4. Derin araştırma — aday 1: `flutter_webrtc` ailesi

### Ne yapıyor

Üç katmanlı bir yapı ve bu ayrım karar için önemli:

| Paket | Rolü | Yıldız | Son push | Açık issue |
|---|---|---|---|---|
| `flutter_webrtc` | **Platform eklentisi** (Android/iOS/macOS/Windows/Linux/Web) | 4491 | 2026-09-22 | 718 |
| `webrtc_interface` | **Saf Dart arayüz** (sınıf tanımları, uygulama yok) | 23 | 2026-03-16 | 10 |
| `dart_webrtc` | **Arayüzün web uygulaması** (tarayıcı JS'i) | 35 | 2026-09-04 | 11 |

**Yanıt: `dart_webrtc` doğrudan kullanılabilir mi? Hayır — ve bu iyi haber.**

`dart_webrtc` *arayüzün uygulamasıdır*, platform eklentisi değildir. Kodu
okundu: `lib/src/rtc_data_channel_impl.dart` baştan sona
`import 'dart:js_interop'` ve `package:web/web.dart` üzerine kurulu. Yani
**yalnız tarayıcıda** çalışır. Windows/macOS/Linux/Android'de `flutter_webrtc`
içindeki `lib/src/native/rtc_data_channel_impl.dart` kullanılır, o da
`WebRTC.invokeMethod(...)` ile platform kanalına gider.

Yani üçü birbirinin yerine geçmez: MKVI masaüstü/Android için **her zaman**
`flutter_webrtc`'in native yolunu kullanır. Arayüz ayrımı (`webrtc_interface`)
gerçek ve faydalıdır — testlerde sahte uygulama yazabiliriz — ama **MKVI'nin
bugünkü kod tabanında `webrtc_interface`'i doğrudan bağımlılık yapmak boş
iş:** zaten `flutter_webrtc` onu sürüklüyor.

**Serbest/özgür portlar mı? Evet, ikisi de.** Üçüncü taraf lisans
`MIT`; altındaki `libwebrtc` **BSD-3-Clause** (Chromium). Hiçbir kaplı ya da
pahlı katman yok. **"WebRTC pahalı/kapalı" ön varsayımı yanlıştır** ve bu ADR
onu düzeltiyor: gerçek maliyet **lisans değil, sarmalayıcının olgunluğu.**

### Bakım durumu (ölçüldü)

- **Son sürüm 1.6.2+hotfix.3, 2026-09-15.** Son 365 günde 15 sürüm, toplam 183
  sürüm. Proje **ölü değil**, aksine sık çıkarıyor.
- **718 açık issue** (tüm etiketler). Bu, ADR 0001'in yazdığı "116 açık Windows
  issue'ı" ile **farklı bir ölçüt**: depoda 15 etiket var ve **hiçbiri platform
  Windows değil** (etiketler: `🤖Android`, `🍎iOS`, `🐛bug`, `🚀enhancement`,
  `😭help wanted`, `🙃good first issue`, `❔question`, `🤔example`, `🖕duplicate`,
  `🖕wontfix`, `😡invalid`, `wontfix`, `work in progress`, `🦔rostopira`,
  `😭stuck`). Yani "116 Windows issue"ı **bugün etiketle yeniden üretemedim.**
- **Resmi demo ölü — bunu doğruladım.** `flutter-webrtc/flutter-webrtc-demo`
  (1247★) son push **2025-02-10**, yani ~19,5 ay. ADR 0001'in *"resmi demo 19
  aydır ölü"* tespiti **doğru çıktı.**

### MKVI'nin bilinen kusurları — bugünün durumu (ölçüldü, 2026-09-26)

| Issue | Başlık | Durum | Açıldı | Yorum |
|---|---|---|---|---|
| **#2137** | Windows: `getDisplayMedia()` returns a dead track when `RTCDesktopCapturer::Start()` fails | **açık** | 2026-08-04 | MKVI'nin ekran paylaşımı yolunu doğrudan vuruyor. **0 yorum.** |
| **#2205** | Windows: `getDisplayMedia` produces washed-out / gray image on HDR displays | **açık** | 2026-09-24 | 2 gün önce açıldı, **0 yorum.** |
| **#1521** | Android Screen Share: `getDisplayMedia` not build for SDKVersion 34 | **açık** | 2024-02-06 | ROADMAP Faz 9'un Android ekran paylaşımı engeli, 2.5 yıldır açık. |

**Üçü de hâlâ açık.** ADR 0001'in risk listesi **bugün de geçerli** ve üçüne
de henüz cevap yok. Bu, `flutter_webrtc`'i reddetmek için değil, **kabul
edilmiş risk** olarak kayda geçmeli.

### Verdict: `flutter_webrtc` kalır, sürüm sabit

Gerekçe dört sorudan geçiyor:

1. **İşi yapıyor mu?** Evet ve tek yapan bu: Windows'ta MF/WASAPI/DXGI, Android'de
   CameraX/…, ekran paylaşımı. Elle yazılacak bir ikamesi yok.
2. **Bakım?** Son sürüm 11 gün önce, son 12 ayda 15 sürüm, haftalık push. Aktif.
3. **Lisans?** MIT + BSD-3. Sorun yok.
4. **Doğru mu bildiğimiz?** **Kısmen.** "Doğrulanmış yayıncı" doğrulanamıyor;
   "116 Windows issue"ı etiketle yeniden üretilemiyor. İkisi de bu belgede
   düzeltildi.

**Daha küçük alternatif yok.** `dart_webrtc` web-only (§4'te kanıtlandı).

**Risk:** 718 açık issue tek bakımcı yükü demek değil ama **Windows tarafı
ikinci sınıf** — üç bilinen kusurun üçü de Windows. `ROADMAP.md` bunu zaten
"kabul edilen risk" olarak yazıyor; bu ADR o kaydı **sayılarla** destekler.

## 5. Derin araştırma — aday 2: `web_socket_channel` (sinyalleşme istemcisi)

### Şu an ne var

`app/lib/signaling/rendezvous_client.dart` `import 'dart:io' show WebSocket`
kullanıyor ve `SignalingSocket` adlı küçük bir arayüz arkasına sarmalıyor
(kodda okundu). Bu sarmalayıcı **zaten doğru bir dikiş** — sahte soket
takılabiliyor, test sunucu istemiyor.

### Sorun ne

`dart:io` **masaüstü ve Android'de vardır ama Flutter Web'de yoktur.** Bugün
MKVI'nin hedefi web olmadığı için bu bir *kırılma* değil, bir **kısıt**: bu
istemci ileride web'e taşınamaz. Daha somut bir maliyet: `dart:io`ya doğrudan
bağımlılık, testlerin de `dart:io` yüklemeye zorlaması demek.

### Aday ölçümü

| Ölçüt | Değer | Kaynak |
|---|---|---|
| Sürüm / tarih | **3.0.3 · 2025-04-17** | pub.dev API |
| Son 365 günde sürüm | **0** | pub.dev API (hesaplandı) |
| Toplam sürüm | 33 | pub.dev API |
| Geri çekilmiş sürüm | 1 | pub.dev API |
| `publisherId` | `tools.dart.dev` | pub.dev `pub-page-data` |
| Depo | `dart-lang/http` — 1110★, 375 açık issue, push 2026-09-21, BSD-3 | GitHub API |
| Lisans | BSD-3 | pub.dev |

### Dürüst değerlendirme

**Bakım sinyali karmaşık ve bunu gizlemiyorum:** *paketin kendisi* 17 aydır
sürüm çıkarmamış. Ama `dart-lang/http` tek bir depo ve MKVI **zaten `http`
1.6.0 kullanıyor** — yani bu bir **yeni bakımcı değil, zaten tanıdığımız bir
bakımcının kardeş paketi.** `web_socket_channel`, `http` ve `http_parser` aynı
depo, aynı lisans, aynı sürüm ritmi içinde yaşıyor. Bu, "17 aydır sürüm
yok" gözlemini büyük ölçüde açıklıyor: bağımsız bir yayın takvimi yok, çünkü
`http`'nin takvimi var.

**Risk:** paket ayrı yaşamaya devam ederse ve Dart SDK onu desteklemeyi
bırakırsa MKVI'de tek bir satır değişir (`SignalingSocket` arayüzü zaten
ayrıştırılmış durumda). **Bu, almanın maliyetini düşük, reddetmenin
kazancını sıfır yapan bir değişikliktir.**

### Verdict: **AL — `dart:io` `WebSocket` yerine**

- `app/lib/signaling/rendezvous_client.dart:28` — `import 'dart:io' show WebSocket`
  satırı gider, `IoSignalingSocket` `WebSocketChannel.connect` kullanır.
- **`SignalingSocket` arayüzü korunur.** Bu değişiklik dikişlerin hiçbirini
  kırmaz; `vectors/wire-v1.json` sözleşmesi de etkilenmez.
- **Bağımlılık sayısı +1** ama **yeni bakımcı sayısı +0** (aynı depo).

## 6. Derin araştırma — aday 3: `rusqlite` + SQLCipher (yerel depolama)

### Şu an ne var

`rusqlite 0.32.1`, `features = ["bundled"]`. `THIRD-PARTY-NOTICES.md` §1
**dürüstçe** şunu yazıyor: *"SQLCipher etkin DEĞİL... SQLite'ın WAL/journal
sayfaları bu şifrelemenin dışındadır. Bu, bilinen ve kabul edilmiş bir
sınırdır."* Doğru ve dürüst.

### `rusqlite`'i değiştirmeli miyiz?

`sqlx` ve `libsql` ölçüldü:

| Aday | Sürüm / tarih | Toplam indirme | Neden uygun değil |
|---|---|---|---|
| `rusqlite` 0.40.2 | 2026-08-08 | 112.3M | **Mevcut.** 4409★, 170 issue, push 2026-09-25, MIT. |
| `sqlx` 0.9.0 | 2026-05-21 | 152.5M | **async** Rust, `tokio` çalışma zamanı ister. `mkvi_core` bilerek **senkron ve runtime'sız** (`Cargo.toml` yorumu: "no network, no async"). Eklersek çekirdek `tokio`'ya bağımlı olur — ki `mkvi_bridge`'a zaten dolaylı geliyor (§3.1). |
| `libsql` 0.9.30 | 2026-03-19 | 2.2M | En yeni sürüm **hâlâ pre-release** (`0.10.0-pre.4`). Yerel dosya modu SQLite'ın uzantısı; MKVI'nin ihtiyacı olan şey değil. |

**Karar: `rusqlite` kalır, `sqlx`'e ve `libsql`'e geçilmez.** Dört sorudan
biri bile "iyi bir şey yapıyor mu" diye geçmiyor: `sqlx`'in async olması
MKVI'nin mimari kararına *doğrudan* aykırı.

### SQLCipher'a geçmeli miyiz?

**`bundled-sqlcipher` özelliği hâlâ var — bu doğrulandı.** `rusqlite` deposunun
`master` `Cargo.toml`'u okundu; özellikler tam olarak:

```toml
bundled-sqlcipher = ["libsqlite3-sys?/bundled-sqlcipher", "bundled"]
bundled-sqlcipher-vendored-openssl = [
    "libsqlite3-sys?/bundled-sqlcipher-vendored-openssl",
    "bundled-sqlcipher",
]
```

Yani iki yol var: **sistem OpenSSL'ine bağlan** ya da **OpenSSL'i kaynaktan
derle.**

**Bunun bedeli dürüstçe:**

1. **Lisans değişir.** SQLite kamu malıdır; **SQLCipher değildir.** SQLCipher
   BSD-3-Clause'tır — ticari kullanım sorunu yok, ama `THIRD-PARTY-NOTICES.md`'nin
   "SQLite kamu malıdır, ayrı lisans bildirimi gerekmez" satırı (§6) artık
   **doğru olmaz** ve `libsqlite3-sys` artık SQLCipher kodu taşır.
2. **OpenSSL yükü.** `bundled-sqlcipher-vendored-openssl` OpenSSL'i `cc` ile
   kaynaktan derler. Windows'ta bu, `mkvi_core` derlemesine **dakikalar**
   ekler ve dağıtıma `libcrypto`/`libssl` ya da statik bağlama kararı getirir.
3. **Platform riski en yüksek olan yer burası.** Android'de OpenSSL taşımak
   ayrı bir iş. MKVI'nin Android'i ikinci hedef (`ROADMAP.md` Faz 9).
4. **Faydası ölçülebilir ve sınırlı.** Şu anki model: dosya **tamamen**
   XChaCha20-Poly1305 ile şifreleniyor, anahtar OS kasasında. Açık olan tek
   şey WAL/journal sayfaları. Yani kazanım "eşzamanlı yazma sırasında diskte
   görünen şema başlıkları", kayıp ise **derleme süresi + lisans karmaşıklığı +
   Android'de taşıma riski.**

**Verdict: SQLCipher özelliği `0.2.0`'a eklenmez.** Gerekçe üç ölçülebilir
şeye dayanıyor: derleme maliyeti, Android taşıma riski, lisans bildirimi
 karmaşıklığı. `SECURITY.md` §2'deki kabul edilmiş sınır **dokunulmadan
kalır.** Bu bir lead kararıdır (§15) çünkü güvenlik sınırıdır, tercih değil.

**Ek not (sürüm boşluğu):** `master` `Cargo.toml`'u sürüm `0.40.1` diyor,
crates.io `max_stable_version` ise `0.40.2`. Yani master bir yamadan geride.
Küçük ama kayda değer: bu deponun `master`'ı yayın çizgisi değil.

## 7. Derin araştırma — aday 4: `keyring` 4.x (cihaz anahtarı / OS kasası)

Bu, bu turda **en somut ve en gürültü-getirici** aday oldu.

### Şu an ne var

`keyring 3.6.3`, hedef-koşullu üç arka uç: `windows-native`, `apple-native`,
`sync-secret-service` + `crypto-rust`. **Android ve iOS'ta yok.**
`ROADMAP.md` Faz 9: *"keyring Android'de yok → flutter_secure_storage beslemeli
SecretStore."* `ADR 0001` bunu bir **risk** olarak kaydetmişti.

### `keyring` 4.2.0'da ne var (kaynaktan okundu)

`keyring-rs` deposunun `master` `Cargo.toml`'u okundu. İki bulgu:

**Bulgu 1 — Android arka ucu eklendi:**

```toml
[target.'cfg(target_os = "android")'.dependencies]
android-native-keyring-store = { version="1", optional = true }
```

ve `package.metadata.docs.rs.targets` listesinde `x86_64-linux-android` var.
Yani `keyring` 4.x **Android'de bir arka uca sahip.**

**Bulgu 2 — özellik adları tamamen değişti:**

```toml
[features]
default = ["v1"]
v1 = [
    "apple-native-keyring-store/keychain",
    "windows-native-keyring-store",
    "zbus-secret-service-keyring-store",
]
cli = [ ..., "android-native-keyring-store", ... ]
```

Yani:

- MKVI'nin kullandığı `windows-native` / `apple-native` / `sync-secret-service`
  özellik adları **4.x'te yok.** Yeni model: her arka uç **ayrı bir crate**,
  `keyring-core` çatısı altında; ana crate `default = ["v1"]` ile hepsini birden
  açar.
- **Android arka ucu `v1`'in parçası DEĞİL** — yalnız `cli` özelliğinde.
  Yani Android'de kullanmak için hedef-koşullu olarak açıkça eklenmesi gerekir.
- Lisans `MIT OR Apache-2.0` (3.x ile aynı). `edition = "2024"`,
  `rust-version = "1.88.0"` (3.x'ten farklı; `mkvi_core` şu an `edition 2021`).

### Android arka ucu ne kadar olgun? (ölçüldü)

| Depo | Yıldız | Açık issue | Son push |
|---|---|---|---|
| `open-source-cooperative/keyring-rs` | 768 | **0** | 2026-09-15 |
| `open-source-cooperative/android-native-keyring-store` | **14** | 1 | **2026-04-21** |
| `open-source-cooperative/keyring-core` | 39 | 1 | 2026-04-21 |

**Dürüst okuma:** Android arka ucu **mevcut ama olgun değil.** 14 yıldız, 5 aydır
push yok. `keyring-rs`'in 0 açık issue'ı da "kusur yok" demek değil —
`has_issues: true` olduğu doğrulandı, yani sorun yok; ama bu kadar küçük bir
projede 0 açık issue da pek çok şey anlatmıyor.

### Verdict: **4.x'e geçiş lead kararı — ama yönü "geç"**

Gerekçe:

1. **İşi yapıyor mu?** 3.x hayır (Android yok); 4.x **evet, ama olgunlaşmamış.**
2. **Bakım?** `keyring-rs` aktif (768★, haftalık push). Yeni API çatısı
   (`keyring-core` + ayrı store crate'ler) daha iyi bir tasarım.
3. **Lisans?** `MIT OR Apache-2.0`. Sorun yok.
4. **Doğru mu bildiğimiz?** **Hayır — ve bu önemli.** "`keyring` Android'de yok"
   ifadesi bugün **yanlış.** `ROADMAP.md` Faz 9'un gerekçesi değişti.

**Ama 3→4 bir ana sürüm sıçraması ve `mkvi_core`'un güvenlik yolunda.** İki
seçenek var ve bu **lead'in kararı:**

- **(a) 3.6.3'te kal, `flutter_secure_storage`'ı Android `SecretStore`'a besle.**
  `ROADMAP.md`'nin mevcut yolu. Rust tarafında değişiklik yok.
  `android-native-keyring-store`'un 14 yıldız/5 ay olgunluğu **bu seçeneği
  daha da cazip kılıyor.**
- **(b) 4.2.0'a geç, `SecretStore` trait'ini her iki platformda Rust'ta tut.**
  Daha temiz; ama `security.rs`'in OS kasası dikişi yeniden yazılır ve Android
  arka ucu genç.

**Tavsiyem (a).** Gerekçe: 14 yıldızlı bir arka ucu güvenlik kritik bir yola
koymak, 5 aydır push almamış bir depoya bel bağlamaktır. `ADR 0001`'in
`SecretStore` dikişi **zaten doğru tasarım**; değiştirmeye gerek yok.

## 8. Derin araştırma — aday 5: `flutter_riverpod` (durum yönetimi)

### Karar hâlâ geçerli mi?

`ROADMAP.md` "Verilmiş kararlar" diyor: *"UI kütüphanesi, i18n, durum yönetimi
alınmaz. El yazması tema + `ChangeNotifier`."* Kullanıcı bunu
*"ekranlar büyüdükçe değişmeli mi?"* diye soruyor. Ölçelim.

### Aday ölçümü

| Ölçüt | `flutter_riverpod` | `flutter_bloc` | `provider` |
|---|---|---|---|
| Sürüm / tarih | 3.4.3 · 2026-09-03 | 9.1.1 · 2025-05-02 | 6.1.5+1 · 2025-08-19 |
| Son 365 günde sürüm | **14** | **0** | **0** |
| Toplam sürüm | 130 | 121 | 70 |
| Depo | 7392★ · 160 issue · push 2026-09-22 · MIT | — | — |

Riverpod **sağlıklı**: 3.x çıkışını geçmiş (3.4.3), 3 haftada bir sürüm. Bu bir
"ölü" aday değil.

### Peki neden almıyoruz?

Ölçüm değil, **mimari gerekçe**:

1. **MKVI'nin test stratejisi `ChangeNotifier`'a dayanıyor ve işe yarıyor.**
   `AGENTS.md`: *"Yalnız kendi işimiz olan katmanda el yaz... arayüz durumu —
   bunlar bizim."* `app/lib/session/session_controller.dart` saf Dart, 79 test,
   donanımsız. Riverpod'ın `ProviderScope` + `ref.watch` dünyası bu testleri
   `ProviderContainer` ile yeniden yazmayı gerektirirdi — **ölçülebilir bir
   kazanç yok, kesin bir yazma maliyeti var.**
2. **Bağımlılık zinciri.** `flutter_riverpod` → `riverpod` → `meta`, `stack_trace`,
   `state_notifier`(artık değil) vb. `app/pubspec.lock` 76 pakette. Bunu
   kaldırmak 3-4 yeni dolaylı paket demek; dört sorudan üçünü boş yere
   doldurur.
3. **Migrasyon maliyeti ölçülebilir değil, ama geri dönüşü de yok.** 10 katman
   `ChangeNotifier` ile yazıldı. Ekrana girip "bu seçim beni yeniden
   derliyor" dediğinde Riverpod'ın alacağı avantaj **o an ölçülebilir** olur —
   o güne kadar taşınan maliyet ise kesindir.

### Verdict: **ALMA — karar hâlâ geçerli, ama gerekçesi güncellendi**

`ROADMAP.md`'nin gerekçesi *"UI kütüphanesi alınmaz"* diye eksik. Doğru olan:
**şu an alınmaz, ve alınması için ölçülebilir bir eşik gerekir.** Önerilen
eşik (§15'te lead'e): **bir ekranın `build` method'unda düzeltilemeyen bir
yeniden derleme sayımı ölçülürse.** Bu ölçüm yapılana kadar karar kendiliğinden
kalkmaz.

## 9. Derin araştırma — aday 6: `str0m` ve `webrtc-rs` (WebRTC dışı yol)

Kullanıcının sorusu: *"WebRTC dışı alternatif: WebRTC'nin pahlı/kapalı tarafı
varsa, doğrudan QUIC/Holepunch/relay kütüphaneleri var mı?"*

### Önce bir düzeltme

**WebRTC'nin pahlı/kapalı bir tarafı yok.** `libwebrtc` **BSD-3-Clause**
(Chromium), `flutter_webrtc` **MIT**. İkisi de ticari kullanıma açık ve
copyleft yok. Maliyet **lisans değil**; maliyet **Flutter sarmalayıcısının
olgunluğu** (§4'te ölçüldü: 718 açık issue, üçü de Windows).

### İki Rust WebRTC adayı

| | `str0m` 0.24.0 | `webrtc` (webrtc-rs) 0.21.0 |
|---|---|---|
| Yayım | 2026-09-25 (**dün**) | 2026-09-19 |
| Toplam indirme | 2.3M | 7.0M |
| Depo | 627★ · 36 issue · push 2026-09-25 | 5153★ · **9 issue** · push 2026-09-20 |
| Lisans | MIT | Apache-2.0 (MIT/Apache diyor, depoda Apache-2.0) |
| Tarz | Sans-I/O, thread'siz, async'siz | Async, Pion yeniden yazımı |
| Android derleniyor mu? | **derleniyor, test edilmiyor** | dokümanlamadım |

**`str0m`'un kendi README'si kararı kendisi veriyor** (okundu). Özellik
karşılaştırma tablosu:

| Özellik | str0m | libWebRTC |
|---|---|---|
| Video/audio **capture** | ❌ | ✅ |
| Video/audio **encode/decode** | ❌ | ✅ |
| Audio **render** | ❌ | ✅ |
| Turn | ❌ | ✅ |
| Ağ arayüzü sayımı | ❌ | ✅ |
| Data Channels | ✅ | ✅ |

Ve **proje durumu** bölümü: *"Str0m was originally developed... by Lookback. We
use str0m for a specific use case: str0m as a **server SFU** (as opposed to
peer-2-peer)... **Str0m is intended to be an all-purpose WebRTC library, which
means it also works for peer-2-peer, though that aspect has received less
testing.**"*

**Ve platform tablosu:** `aarch64-linux-android` → derleniyor ✅, **test edildi
❌.**

### Verdict: **İKİSİ DE ALMA — gerekçe ölçülebilir**

MKVI'nin **arayüze ihtiyacı var**: kamera, mikrofon, **ekran paylaşımı**. Her iki
Rust kütüphane de capture/encode/render **yok**. Bu, "daha küçük bir alternatif
var mı" sorusunun cevabıdır: **yoktur, çünkü onların işi medya yığını değil,
protokol yığını.**

Bunun yerine Rust WebRTC almak, MKVI'yi iki medya yığını (libwebrtc + kendi
kendi codec zincirin) yöneten bir uygulamaya çevirirdi. `AGENTS.md` bunu açıkça
yasaklıyor: *"DTLS'yi, ICE'yi, DTLS-SRTP'yi... kendi başımıza yazmayız."*
`str0m`/`webrtc-rs` bu katmanı **verirler** — ama medya katmanını vermedikleri
için elde net bir kazanç yok, ortada iki yığın olur.

## 10. Derin araştırma — aday 7: `quinn` + Rust STUN/TURN (NAT geçişi)

| Aday | Sürüm / tarih | Toplam indirme | Depo durumu |
|---|---|---|---|
| `quinn` | 0.11.12 · 2026-09-14 | 321.3M | — |
| `s2n-quic` | 1.89.0 · 2026-09-22 | 742.7k | — |
| `stun_rs` | 0.1.11 · **2025-03-31** | 860k | — |
| `stun-client` | 0.1.4 · **2023-07-17** | 9.8k | — |
| `turn-rs` | 1.2.2 · 2023-12-24 | 5.6k | — |
| `turn_server` | 4.1.5 · 2026-08-11 | 12.5k | sunucu, istemci değil |

### Neden "WebRTC dışı" yol MKVI için kapalı

QUIC bir taşımdır; **NAT geçişi bir çözüm değildir.** İnternet üzerinden iki
kişinin doğrudan bağlanabilmesi için gereken şey ICE'dir: aday toplama, STUN,
eşleşme, TURN. crates.io araması (`q=sqlcipher`, `q=libdatachannel`,
`q=webrtc+android` ile birlikte) şunu gösteriyor:

- `stun-client` **ölü** (3 yıl), `stun_rs` **18 aydır** sürüm çıkarmamış.
- TURN **istemci** tarafında crates.io'da ciddi bir Rust kütüphanesi **yok**;
  bulunanlar sunucu tarafı (`turn_server`) veya test oyuncakları
  (`turn-rs` 5.6k indirme, 2023).

Yani bu yol, `AGENTS.md`'nin yasakladığı şeyin tam kendisi olurdu: **STUN'ı,
ICE'ı ve TURN'ü kendi başımıza yazmak.** Kimseye faydası yok.

**Tersine, `webrtc-rs`'in ICE'i (`webrtc-ice` 0.17.2, 6.5M indirme,
2026-07-20) ayrı bir Rust projesi olarak sağlıklı** — ama libwebrtc zaten
kendi ICE'ını içeriyor ve ikisini birbirine bağlamak ek iş.

### Verdict: **ALMA**

## 11. Derin araştırma — aday 8: `file_picker` + `desktop_drop` (dosya seçme)

MKVI'nin dosya gönderme akışı bugün `OutgoingFileSource` arayüzüyle soyut
(kodda okundu) ama **onu dolduran hiçbir şey yok** — kullanıcı bir dosya
seçemiyor. Bu, `chat` katmanındaki en belirgin boşluk.

| | `file_picker` 13.1.0 | `desktop_drop` 0.8.4 |
|---|---|---|
| Yayım | 2026-09-15 | 2026-09-01 |
| Son 365 günde sürüm | **26** | 7 |
| Toplam sürüm | **242** | **24** |
| Geri çekilmiş sürüm | 1 | 0 |
| `publisherId` | `victorcanrare.dev` | `mixin.net` |
| Lisans | MIT | MIT |
| Platform | Win/macOS/Linux/Android/iOS/Web | masaüstü + web |

### `desktop_drop` için iki uyarı (ölçüldü)

1. **Menşe:** `mixin.net` = **Mixin Messenger**, bir kripto cüzdan uygulaması.
   24 sürüm, 7 son 1 yıl — küçük ve tek bağlamlı bir ekip. Bir cüzdan
   uygulamasının sürükle-bırak eklentisi P2P kişisel iletişim için doğal bir
   sahiplik değil.
2. **Bağımlılık:** `desktop_drop` `dbus: ^0.7.10` çekiyor — masaüstü sürükle-bırak
   için Linux'a **D-Bus bağımlılığı.** MKVI'nin Linux derlemesine yeni bir sistem
   bağımlılığı demek, Linux'u zaten ikinci sınıf tutan bir projede (Faz 9'da
   Android, ilk hedef masaüstü) orantısız.

### Verdict

- **`file_picker`: AL.** Dört sorunun dördünü de geçiyor: 242 sürüm ve son 1
  yılda 26 sürüm (fluttercommunity'nin en sık çıkan paketlerinden biri), MIT,
  `isDiscontinued: false`. MKVI'nin `OutgoingFileSource` arayüzünü doğrudan
  besileyen tek yol bu. İki paketin aynı dosya soyutlamasını (`XFile`) paylaştığı
  iddiasını **kaynaktan doğrulamadım** — ikisi birden alınacaksa bu lead'in
  denemesi gereken bir ayrıntı.
- **`desktop_drop`: KARAR GEREKTİREN (lead).** İki kişi birbirine dosya
  gönderirken sürükle-bırak güzel, ama zorunlu değil; `file_picker` işini bitirir.

## 12. Sıkıştırma: karar ve gerekçe

Bu, "oran mı hız mı" sorusunu bir ölçüme çevirmek isteyen bir katmandı. Cevap:
**MKVI'de sıkıştırma gerekmiyor.** Dört ayrı gerekçe:

1. **Dosyalar zaten sıkıştırılmış.** JPEG, MP4, ZIP, PDF — kullanıcının
   gönderdiği şeylerin çoğu. `zstd` bunlarda CPU harcar ve boyut kazandırmaz.
   MKVI'nin 512 MB sınırı bir **video dosyası** sınırıdır.
2. **Sıkıştırılmamış dosyalar (düz metin, .log, .json) zaten küçüktür.** 512 MB'a
   yaklaşmayan bir dosyayı sıkıştırmak, `PeerProtocol.maxFileBytes`'ı bir
   sınırsızlık gibi göstermekten başka işe yaramaz.
3. **Taban zaten şifreli.** DTLS-SRTP/SRTP her baytı şifreler; IP başlığı
   sıkıştırması zaten işe yaramaz. Sıkıştırma **kaldıracak** bir şey yok.
4. **Ölçüm gerektirir, tahmin değil.** "Oran mı hız mı" sorusunu
   cevaplamak için iki cihazlı bir hız ölçümü gerekir. `docs/manual-test.md`
   soru 4'ü (dosya aktarımı) zaten ölçüyor; **o ölçüm yapılmadan** sıkıştırma
   kararı verilemez. Benim tahminim değil, ölçümün kendisi karar vermeli.

**Aday ölçümü (yine de ölçtüm):**

| | `zstd` 0.14.0 | `brotli` 9.0.0 | Dart `archive` 4.3.0 |
|---|---|---|---|
| Yayım | 2026-09-04 | 2026-09-02 | 2026-09-13 |
| Toplam indirme | 399.8M | 270.6M | — (Dart) |
| Lisans | **MIT** (depo `Cargo.toml`'unda okundu) | MIT | MIT |
| Derleme | `zstd-sys` → C kaynaktan, `cc` gerekir | saf Rust (`std`'den kaçınır) | saf Dart |

**Verdict: ALMA — hepsi.** Gerekçe yukarıdaki dört madde. Bir gün
`docs/manual-test.md` soru 4 hızı gösterirse ve CPU'nun darboğaz olduğu
**ölçülürse**, `zstd` (MIT, saf C bağımlılığı kabul edilerek) ilk adım olur —
çünkü `brotli`'den hızlı ve `zstd`'nin **lisansı BSD değil MIT**, yani
`THIRD-PARTY-NOTICES.md`'ye yükümlülük eklemiyor.

## 13. Dosya aktarımı: DataChannel 512 MB için yeterli mi?

Bu, ADR 0002'nin kütüphane boyutu. Kod okunarak ölçülebilir bir gerçek çıktı.

### Tespit

`app/lib/core/protocol/peer_protocol.dart`:

- `maxFileBytes = 512 * 1024 * 1024` (satır 49)
- `fileChunkBytes = 16 * 1024` (satır 79)

Yani 512 MB = **32.768 parça.**

`flutter_webrtc`'in **native** DataChannel yolu, Dart'tan native'e **her parça
için ayrı bir platform kanalı çağrısı** yapıyor. `lib/src/native/rtc_data_channel_impl.dart`
okundu:

```dart
Future<void> send(RTCDataChannelMessage message) async {
  await WebRTC.invokeMethod('dataChannelSend', <String, dynamic>{
    'peerConnectionId': _peerConnectionId,
    'dataChannelId': _flutterId,
    'type': message.isBinary ? 'binary' : 'text',
    'data': message.isBinary ? message.binary : message.text,
  });
}
```

**Her parça = bir `MethodChannel` gidiş-dönüşü, veri platform kanalının standart
kodlayıcısıyla serileştirilerek.** Alıcı taraf da aynı şekilde bir `EventChannel`
(`receiveBroadcastStream`) üzerinden alıyor.

**Sayı:** 512 MB'lik bir dosya = **32.768 gidiş-dönüş + 32.768 serileştirme
kopyası.** Bu, "512 MB güvenilir mi" sorusunun cevabını belirliyor: **güvenilir
mi evet, hızlı mı bilmiyoruz** — ve bu bir *tahmin* değil, **ölçülmesi gereken
bir sayı.**

### İyi haber: back-pressure API mevcut

Aynı dosyada `bufferedAmount`, `getBufferedAmount()`,
`bufferedAmountLowThreshold` ve `onBufferedAmountLow` **var** — yani
`docs/manual-test.md` soru 4'ün ölçebileceği "göndermeyi yavaşlat" kancası
kütüphanede hazır. Bu, elle yazılacak bir kuyruk yöneticisine gerek kalmadığı
anlamına gelir: **kütüphane işi veriyor.**

### Verdict

- **Alınmıyor, ölçülüyor.** `fileChunkBytes`'ı 16 KB'tan 64 KB'a çıkarmak
  gidiş-dönüş sayısını 4'te bir düşürür; SCTP'nin müzakere edilen azami mesaj
  boyutu bunu kaldırır mı kaldırmaz — **ölçülmeli.**
- Bu madde **ADR 0002'ye girdidir:** dosya aktarımı bir DataChannel mesajı
  başına tek yol mu olacak, yoksa akış mu? Yanıt ADR 0002'de verilmeli; bu
  belge yalnız **sayıyı** veriyor (32.768).
- `docs/manual-test.md` soru 4'üne ek ölçüm maddesi öneriyorum:
  **"512 MB dosyanın `onBufferedAmountLow` sayacı hiç sıfırlanmadan bitti mi?"**

## 14. KULLANMA ÖNERİSİ

### Alınacaklar

| Ne | Katman | Neden | Mevcut yerine geçiyor mu? |
|---|---|---|---|
| **`web_socket_channel` 3.0.3** | Sinyalleşme istemcisi | `dart:io` Web WebSocket'i yok → web'e taşınamıyor. `SignalingSocket` arayüzü zaten ayrıştırdığı için değişiklik tek dosyada. Yeni bakımcı **yok** (aynı `dart-lang/http` deposu, `http` zaten var). | `rendezvous_client.dart:28` |
| **`file_picker` 13.1.0** | Dosya seçme | 242 sürüm / son 1 yılda 26, MIT, `isDiscontinued: false`. `OutgoingFileSource` arayüzünü besileyen tek yol. | Yok — boşluk |
| **`clock` 1.1.3** (dart.dev) | Test yardımcısı | `call_timers.dart` / `reconnect_schedule.dart` gibi zamana duyarlı kod artık gerçek saate bağlı olmaktan çıkar. `clock` doğrudan `DateTime.now`'i enjekte eder. `fake_async`'den daha dar ve daha az bağımlı. | `dart:core`'un `DateTime.now` çağrıları |

### Alınmayacaklar

| Ne | Gerekçe |
|---|---|
| `sqlx` | async; `mkvi_core` bilerek runtime'sız. Mimari karara aykırı. |
| `libsql` | En yeni sürüm hâlâ pre-release; yerel dosya modu MKVI'nin ihtiyacı değil. |
| SQLCipher (`bundled-sqlcipher`) | OpenSSL taşıma maliyeti + Android riski + lisans bildirimi karmaşıklığı; kazanımı WAL sayfalarıyla sınırlı. Ölçülmemiş bir kazanç, ölçülmüş bir derleme maliyeti. |
| `str0m` | capture/encode/render yok → medya yığını eksik. README kendisi P2P'yi "less testing" diye işaretliyor. |
| `webrtc-rs` | Aynı. Üstelik ikinci medya yığını demek. |
| `quinn` / `s2n-quic` | NAT geçişi çözmüyor; Rust STUN/TURN istemci ekosistemi yok (`stun_rs` 18 aydır sürüm çıkarmamış) → ICE'ı elle yazmak anlamına gelir. |
| `flutter_riverpod` | `ROADMAP.md` kararı geçerli; `ChangeNotifier` + 79 donanımsız test çalışıyor. Alınması için **ölçülebilir** bir eşik gerekir (§8). |
| `flutter_bloc` / `provider` | İkisi de son 1 yılda **hiç** sürüm çıkarmamış. |
| `rxdart` | 27 aydır sürüm yok; `dart:async` yeterli. |
| `zstd` / `brotli` / `archive` | §12 — ölçüm gerekli, henüz yok. |
| `sentry_flutter` | 235 sürüm, son 1 yılda 44, MIT — **bakımı çok iyi.** Ama **dışarıya veri gönderir** ve MKVI'nin tezi *hesapsız* ve sunucusuz. `ROADMAP.md` Faz 7 "public'a çıkış" öncesi `SECURITY.md` var; bir çökme raporlama servisi bu tezle çelişir. |
| `tracing` (Rust) | `tracing` 0.1.44 **2025-12-18**'de çıkmış — 9 aydır sürüm yok (master'da 0.2.0 geliştiriliyor). MKVI çekirdeğinin ihtiyacı `log`/`eprintln!` düzeyinde. |
| `pointycastle` / `cryptography` (Dart) | MKVI'de **ikinci bir kripto yığını** olurdu. `AGENTS.md`: kripto Rust'ta, denetimli crate'lerle. |
| `sqflite` / `drift` / `sembast` / `isar` / `hive` / `objectbox` / `realm` | Veritabanı Rust çekirdekte. `isar` 2023'ten beri güncellenmiyor; `sqlite3_flutter_libs` `0.6.0+eol` ("Not used anymore"); `objectbox`/`realm` ticari lisans riski taşıyor. |
| `mocktail` | MKVI'nin test stili **elle yazılan sahte** (`SignalingSocket`, `FileSink`, `SecretStore`, `MediaBackend` — hepsi kodda okundu ve arayüzlerle ayrılmış). `mocktail` bu alışkanlığı bozmak için ek bağımlılık. |

## 15. KARAR GEREKTİREN (lead)

Bunlar benim değil lead'in kararları. Her biri gerekçesiyle birlikte:

1. **`rusqlite` 0.32.1 → 0.40.2 yükseltmesi.** 8 minor sürüm, `edition 2024` ve
   `MSRV 1.88`. `mkvi_core` şu an `edition 2021` ve `bundled` özelliğinin
   `default`'taki `ffi-sqlite-wasm-rs` ile etkileşimi değişmiş olabilir.
   **Benim önerim ayrı bir PR, ayrı commit, kendi test koşusuyla.** 170 açık
   issue'lu aktif bir depoda 8 sürüm atlamak "küçük yükseltme" değildir.
2. **`ed25519-dalek` 2.2.0 → 3.0.0.** Bir major. Kimlik imzası ve SAS ifadesi
   buna dayanıyor. Aynı şekilde ayrı PR.
3. **`keyring` 3.6.3 → 4.2.0 mu, kalınsın mı?** Özellik adları tamamen
   değişti; özellikle Android arka ucu geldi ama 14 yıldız/5 aylık. Benim
   önerim **kal** (§7).
4. **SQLCipher.** §6'daki gerekçeyle önerim **0.2.0'a alma**; ama bu bir güvenlik
   sınırı (`SECURITY.md` §2) ve lead'in çağrısı.
5. **`fileChunkBytes` 16 KB → 64 KB.** §13'teki 32.768 gidiş-dönüş sayısına
   dayanarak. Ama bu **ADR 0002'ye** bağlı: akış tabanlı bir taşıma seçilirse
   soru kendiliğinden kapanır.
6. **`desktop_drop`: alınsın mı?** §11'de ölçtüm, iki uyarı var (menşe, D-Bus).
   `file_picker` tek başına işi bitiriyor.
7. **QR ile eşleştirme.** `barcode` 2.2.9 (2025-01-25) + `mobile_scanner` 7.4.2
   (2026-09-14, son 1 yılda 7 sürüm) ikilisi bu işi yapar. `qr_flutter` 4.1.0
   **üç yıldır** (2023-05-14) güncellenmedi — seçilmemeli. Kısa kod yeterliyse
   **hiçbirine gerek yok.** `barcode`'ın uygulama biçimini (saf Dart mı, canvas
   mı) doğrulamadım; lead denemeden karar vermemeli.
8. **`THIRD-PARTY-NOTICES.md` düzeltmeleri** (ben dokunmadım — dosya sahibi
   değilim): §3'teki `webrtc_interface` lisans notu (§2.1), §2'ye `tracing` /
   `tracing-core` / `log` / `anyhow` satırları (§2.4), `minisign-verify 0.3.0`
   yayım tarihi (§2.3), §1'e §2.5'teki sürüm boşluğu notu, SQLCipher'e
   geçilirse §6'daki "kamu malı" satırının düzeltilmesi.
9. **Durum yönetimi eşiği.** §8'de önerilen ölçüm eşiği resmî bir eşik olarak
   `ROADMAP.md`'ye girsin mi? Girerse karar kendiliğinden kalkmaz, **ölçümle**
   kalkar.

## 16. Bu ADR'nin tersine çevirme koşulu

Bu karar bir kez yazıldı ve **kanıt değişmeden değiştirilmemeli.** Aşağıdakilerden
biri ölçülürse karar gözden geçirilir:

- `docs/manual-test.md` soru 4 (dosya aktarımı hızı) DataChannel yolunun
  **yetersiz** olduğunu gösterirse → §13'teki 32.768 sayısı kararı bozar;
  akış tabanlı bir taşıma ADR 0002'ye döner.
- `docs/manual-test.md` soru 3 (ekran paylaşımı) `flutter-webrtc` kararını
  **vendor fork** eşiğine taşırsa → §4'ün tamamı düşer (zaten ADR 0001'de
  yazılı).
- `keyring-rs` Android arka ucu **yaygınlık** kazanırsa (ör. 1 yıl boyunca
  düzenli push + başka bir büyük üretici bağımlılığı) → §7'nin "kal" önerisi
  gözden geçirilir.
- MKVI'ye bir **üçüncü kullanıcı** gelirse (iki kişi varsayımı bozulursa) →
  `sentry_flutter` ve `tracing` kararları §14'te gözden geçirilir.

## 17. Doğrulayamadıklarım

Bu bölüm bilinçlidir ve silinmemelidir. **Bu belgede "kurup denedim" diyen hiçbir
madde yoktur.**

1. **Hiçbir şey derlenmedi, kurulmadı, koşulmadı.** `cargo build`, `cargo test`,
   `pub get`, `flutter test`, `wrangler` — hiçbiri çalıştırılmadı.
2. **Kurulum/derleme testi yapılmadı.** Özellikle `keyring` 4.2.0'ın Android
   arka ucu, `rusqlite`'in `bundled-sqlcipher` özelliği ve `web_socket_channel`
   **yalnız kaynaktan okundu**, denenmedi. "Derlenir" demiyorum.
3. **pub.dev indirme sayıları alınamadı.** Sayfa grafiği JavaScript ile
   yüklendiği için HTML'de sayı yok. Dart paketleri için indirme rakamı
   **uydurulmadı**; `crates.io` `downloads` alanı kullanıldı.
4. **`recent_downloads` penceresinin tanımını doğrulamadım.** crates.io bu alanı
   veriyor ama "son 90 gün" gibi bir etiket **kaynağından doğrulamadım**, bu
   yüzden etiket eklemedim.
5. **"Doğrulanmış yayıncı" durumu doğrulanamadı.** 34 paketin sayfasında da
   `material-icon-verified.svg` rozeti bulundu → rozet ayırt edici değil.
   ADR 0001'in bu ifadesi **bugün doğrulanamıyor.**
6. **ADR 0001'in "116 açık Windows issue"ı yeniden üretilemedi.** Depoda
   platform etiketi yok; 718 rakamı tüm issue'ları kapsıyor, farklı bir
   ölçüt.
7. **ADR 0001'in "resmi demo 19 aydır ölü" tespiti** `flutter-webrtc-demo`
   son push 2025-02-10 ile **doğrulandı.**
8. **DataChannel hızı ölçülmedi.** 32.768 gönderim sayısı **koddan hesaplandı**
   (512 MB ÷ 16 KB); bunun ne kadar süreceği **bilinmiyor** ve
   `docs/manual-test.md` soru 4'ün işidir.
9. **`webrtc-rs`/`str0m` Android derlemesini ben doğrulamadım.** `str0m` için
   README'nin kendi tablosunu aktardım (derleniyor, test edilmiyor). `webrtc-rs`
   için platform listesini hiç okumadım — o yüzden tabloda "dokümanlamadım"
   yazıyor.
10. **`sqlite3mc` Rust için araştırıldı ve elendi:** crates.io'da
    `walletkit-sqlite` 229 indirme, `sqlite3mc-src` 133 indirme. Ciddi bir Rust
    ekosistemine sahip değil. `libsqlcipher-sys` ise 2018'den beri güncellenmiyor
    (36.6k indirme).
11. **pub.dev puanı (`pub points`) ve `likes` sayısı alınamadı.** Sayfa
    düzeninde eşleşen bir alan bulunamadı; uydurulmadı.
12. **GitHub REST API anonim** çağrıldı (saatlik 60 istek sınırı). Çok sık
    yıldızlanan bir depoda "açık issue" sayısı PR'ları da içerir; burada
    `open_issues_count` kullandım ve bunun PR'ları da saydığını not düşmüyorum
    çünkü hangi türü saydığını ayırt edemedim.
13. **`docs/adr/README.md`'ye satır eklemedim.** Başka bir ajan da (0002) o
    tabloyu düzenleyecek; dosya sahipliği çakışması olmasın diye lead
    ekleyecek.
