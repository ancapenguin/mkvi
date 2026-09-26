# Üçüncü taraf bildirimleri

MKVI aşağıdaki üçüncü taraf yazılımları kullanır. Bu dosya iki şeyi kayda geçirir:
**hangi lisansla geliyorlar** ve **projede neden var**. Gerekçesiz bağımlılık
eklememe kuralı bu dosyadan gelir; bir bağımlılığı buraya yazamıyorsanız, o
bağımlılığı eklemeyin.

**Kapsam ve doğrulama**

- Depo **dört ayrı bağımlılık yüzeyi** taşıyor. Sürümler şu kilit dosyalarından
  okunmuştur:

  | Yüzey | Kilit dosyası | Doğrudan bağımlılık listesi |
  |---|---|---|
  | Rust çekirdek | `crates/mkvi_core/Cargo.lock` (189 paket) | `crates/mkvi_core/Cargo.toml` |
  | Rust köprüsü | `crates/mkvi_bridge/Cargo.lock` (238 paket) | `crates/mkvi_bridge/Cargo.toml` |
  | Dart/Flutter uygulaması | `app/pubspec.lock` (76 paket) | `app/pubspec.yaml` |
  | Worker | `cloudflare/package-lock.json` (163 paket) | `cloudflare/package.json` |

  Kısmen doğrulanan iki yüzey daha var: `design/pubspec.lock` (47 paket) ve
  `crates/mkvi_bridge/dart/pubspec.lock` (50 paket).

- Sürümler **kilit dosyalarındaki çözümlenmiş sürümlerdir**; `Cargo.toml` /
  `pubspec.yaml` içindeki aralıklar değil. Bir bağımlılık yükseltildiğinde bu
  dosyadaki sürüm de değişmelidir.
- Tablolar **doğrudan** bağımlılıkları ve lisansı dikkat çeken dolaylı
  bağımlılıkları kapsar. Kilit dosyalarının kendileri kapsamın tamamıdır.
- **Rust tarafında iki ayrı paket vardır ve bunlar tek bir Cargo workspace'i
  değildir** (`crates/mkvi_core/Cargo.toml` başındaki nota bakın). Dolayısıyla iki
  ayrı `Cargo.lock` ve iki ayrı bağımlılık grafiği vardır; ikisi de aşağıdadır.

**Lisans özeti:** MKVI'nin kendi kodu `Apache-2.0 OR MIT` (ikili lisans).
`cloudflare/` dizini ayrı olarak `AGPL-3.0`. Aşağıdaki üçüncü taraf paketlerin
hiçbiri MKVI'nin kendi lisansını değiştirmez.

---

## 1. Rust çekirdek — `crates/mkvi_core`

Kaynak: `crates/mkvi_core/Cargo.toml` + `Cargo.lock`.
Bu paket Flutter'ı (ve emekli Tauri hattını) **bilmez**; cihaz kimliği, şifreli
geçmiş, dosya alımı ve güncelleme imza doğrulamasını barındırır.

| Paket | Sürüm | SPDX | Neden var |
|---|---|---|---|
| `ed25519-dalek` | 2.2.0 | `BSD-3-Clause` | Cihaz kimliği: anahtar çifti, zarfların imzalanması ve doğrulanması. `rand_core` özelliğiyle birlikte. **Özel kripto yazmıyoruz**; bu, denetimli tek kütüphane. |
| `chacha20poly1305` | 0.10.1 | `Apache-2.0 OR MIT` | XChaCha20-Poly1305 ile mesaj geçmişi ve dosya aktarımı şifrelemesi. |
| `keyring` | 3.6.3 | `MIT OR Apache-2.0` | Cihaz Ed25519 tohumu ve veritabanı anahtarını işletim sistemi kasasında tutar. **Platform başına arka ucu açıkça seçilir** (`windows-native`, `apple-native`, `sync-secret-service` + `crypto-rust`); varsayılan özellik yoktur ve hiçbiri açılmadığında kütüphane bellek içi bir sahte depoya düşer. |
| `rusqlite` | 0.32.1 | `MIT` | Yerel şifreli mesaj geçmişi veritabanı. `bundled` özelliğiyle: SQLite kaynaktan derlenir, bu yüzden C++ build araçları şarttır. |
| `minisign-verify` | 0.3.0 | `MIT` | Güncelleme imzasının **saf** doğrulaması: ağ yok, asenkron yok, dosya indirmek çağıranın işi. |
| `zeroize` | 1.9.0 | `Apache-2.0 OR MIT` | Çözülmüş cihaz tohumu ve veritabanı anahtarının yığından silinmesi. |
| `rand_core` | 0.6.4 | `MIT OR Apache-2.0` | `getrandom` tabanlı rastgelelik: nonce üretimi ve cihaz tohumu. |
| `serde` | 1.0.229 | `MIT OR Apache-2.0` | Serileştirme (`derive`). Kayıt ve zarfların JSON biçimi için. |
| `serde_json` | 1.0.151 | `MIT OR Apache-2.0` | JSON okuma/yazma. |
| `base64` | 0.22.1 | `MIT OR Apache-2.0` | Anahtar ve imza baytlarının tel üzerindeki gösterimi: **dolgusuz standart base64** (RFC 4648 §5). |
| `thiserror` | 2.0.21 | `MIT OR Apache-2.0` | Hata türleri için `derive(Error)`. |
| `tempfile` | 3.27.0 | `MIT OR Apache-2.0` | **Yalnızca `dev-dependencies`:** testlerde geçici dosya. Üretim koduna girmez. |

### Dikkat çeken dolaylı bağımlılıklar

| Paket | Sürüm | SPDX | Not |
|---|---|---|---|
| `libsqlite3-sys` | 0.30.1 | `MIT` | `rusqlite` bağımlılığı; SQLite'i **derlenmiş** (`bundled`) olarak getirir. |
| `curve25519-dalek` | 4.1.3 | `BSD-3-Clause` | `ed25519-dalek` ve `chacha20poly1305` altında ed25519 aritmetiği. |
| `ed25519` | 2.2.3 | `Apache-2.0 OR MIT` | `ed25519-dalek` uygulama detayları. |
| `r-efi` | 6.0.0 | `MIT OR Apache-2.0 OR LGPL-2.1-or-later` | UEFI/çıplak metal hedefleri. **İsteğe bağlı** LGPL şubesi; MKVI `MIT`/`Apache-2.0` şubesini seçer, LGPL yükümlülüğü doğmaz. |
| `dbus-secret-service` / `secret-service` / `zbus` | 4.x | `MIT` / `Apache-2.0` | `keyring`'in **Linux** arka ucu. Yalnız Linux'ta derlenir. |
| `security-framework` | 2.11.1 / 3.7.0 | `MIT OR Apache-2.0` | `keyring`'in **macOS** arka ucu. İki sürüm çakışmaz, ikisi de kilitte. |

> **SQLCipher etkin DEĞİL.** `rusqlite` `bundled` özelliğiyle derlenen **düz**
> SQLite'i getiriyor; `bundled-sqlcipher` özelliği kullanılmıyor. Veritabanı
> dosyasının kendisi uygulama katmanında XChaCha20-Poly1305 ile şifrelenir (anahtar
> işletim sistemi kasasında), ancak SQLite'ın WAL/journal sayfaları bu
> şifrelemenin dışındadır. Bu, bilinen ve kabul edilmiş bir sınırdır
> (`SECURITY.md` §2, `ROADMAP.md` Faz 4). Geçiş yapılırsa bu tabloya
> `SQLite (SQLCipher varyantı)` satırı eklenmelidir.

---

## 2. Rust köprüsü — `crates/mkvi_bridge`

Kaynak: `crates/mkvi_bridge/Cargo.toml` + `Cargo.lock`.
Bu paket **hiçbir davranış içermez**; yalnız `mkvi_core`'ü Dart'a açar.

| Paket | Sürüm | SPDX | Neden var |
|---|---|---|---|
| `mkvi_core` | 0.2.0 | — | **Birinci taraf.** Yol bağımlılığı (`../mkvi_core`); AGPL değil, aynı `Apache-2.0 OR MIT`. |
| `flutter_rust_bridge` | 2.13.0 | MIT | FFI yüzeyi. **Tam sabitlendi** (`=2.13.0`), caret aralığı değil: üretilen glue çalışma anında sürümü karşılaştırır ve uyuşmazlıkta başlamayı reddeder, yani bir aralık bağımlılık yükseltmesini derleme hatasına değil **çalışma anı paniğine** çevirirdi. |
| `base64` | 0.22.1 | `MIT OR Apache-2.0` | İmza tel biçimi. Çekirdeğin `STANDARD_NO_PAD` ile **birebir aynı** olmalı: eş protokoli Flutter taşımasıyla değiştirilemez. |
| `tempfile` | 3.27.0 | `MIT OR Apache-2.0` | **Yalnızca `dev-dependencies`:** testlerde geçici dizin. |

Köprü 15 test içerir ve bu testler gerçek Credential Manager'a dokunmaz —
`open_core_with_store` ile bellek içi bir `SecretStore` kurarlar.

**Köprünün `Cargo.lock`'inde beklenmedik bir şey var:** `tokio` 1.53.1,
`dashmap`, `regex`, `wasm-bindgen` ve `web-sys` dolaylı olarak gelir. Bunlar
`flutter_rust_bridge`'in kendi çalışma zamanı bağımlılıklarıdır (iş parçacığı
havuzu, platform eşlemesi, web hedefleri); MKVI'nin seçtiği `default_dart_async:
true` yapılandırmasında yalnız iş parçacığı havuzu kullanılır.

### Dart tarafı — `crates/mkvi_bridge/dart`

Kaynak: `crates/mkvi_bridge/dart/pubspec.yaml` + `pubspec.lock`.

| Paket | Sürüm | SPDX | Neden var |
|---|---|---|---|
| `flutter_rust_bridge` | 2.13.0 | MIT | Üretilen FFI bağlantıları. Rust tarafıyla **birebir aynı sürümde** olmak zorunda. |
| `freezed_annotation` | 3.1.0 | MIT | Üretilen kod `@freezed` birleşimleri ilan ediyor; bu yüzden **çalışma zamanı** bağımlılığıdır. |
| `build_runner` | 2.15.1 | BSD-3-Clause | **Yalnızca `dev-dependencies`:** `freezed` kod üretimi. Uygulamaya girmez. |
| `freezed` | 3.2.5 | MIT | **Yalnızca `dev-dependencies`:** üretici. |

> **Paket adı dekoratif değildir:** `flutter_rust_bridge` native kütüphaneyi
> `package:<ad>/mkvi_bridge` olarak çözer, gövde Rust `lib.name` ile eşleşmek
> zorundadır. Adı değiştirirseniz cargokit derlenmiş kütüphaneyi bulamaz.

---

## 3. Dart / Flutter uygulaması — `app/`

Kaynak: `app/pubspec.yaml` (doğrudan bağımlılıklar) + `app/pubspec.lock`
(çözümlenmiş sürümler).

### Çalışma zamanı

| Paket | Sürüm | Lisans | Neden var |
|---|---|---|---|
| `flutter_webrtc` | 1.6.2+hotfix.3 | `MIT` | P2P taşıma. Platform-native WebRTC (Windows'ta MF/WASAPI/DXGI). 0.1.x'te Tauri'ın WebView2 izin katmanının yarattığı tüm sorunları taşımanın kendiliğinden siler. |
| `flutter_secure_storage` | 11.2.0 | `BSD-3-Clause` | Android'de platform kasası. Masaüstünde kasayı Rust çekirdek yapar; bu paket ileride `SecretStore`'u besleyecek. |
| `path_provider` | 2.1.6 | `BSD-3-Clause` | Uygulama veri dizini ve indirme klasörü: Rust çekirdek dosya yazımını sürücüden önce buradan bulur. |
| `http` | 1.6.0 | `BSD-3-Clause` | Güncelleme bildirimi ve indirme. **İmza doğrulaması Rust'ta** (`mkvi_core::update`); burada yalnızca taşıma. |
| `cupertino_icons` | 1.0.9 | `MIT` | Simgeler. |
| `mkvi_design` | 1.0.0 | — | **Birinci taraf, yol bağımlılığı** (`../design`). Tasarımın tek kaynağı. |

### Geliştirme

| Paket | Sürüm | Lisans | Neden var |
|---|---|---|---|
| `flutter_lints` | 6.0.0 | `BSD-3-Clause` | `flutter analyze` kural kümesi. |
| `flutter_test`, `integration_test`, `flutter`, `flutter_web_plugins`, `flutter_driver`, `sky_engine` | SDK ile gelir | `BSD-3-Clause` (Flutter) | Flutter SDK'sının kendi paketleri; `sdk: flutter` ile çözümlenir. |

### Öne çıkan dolaylı bağımlılıklar

| Paket | Sürüm | Lisans | Not |
|---|---|---|---|
| `dart_webrtc` | 1.8.2 | `MIT` | `flutter_webrtc`'in platform eklentisi. |
| `webrtc_interface` | 1.5.1 | ⚠️ **beyan edilmemiş** | Bkz. aşağıdaki uyarı. |
| `jni`, `jni_flutter`, `jni_util` | 1.0.3 | `Apache-2.0` | `flutter_secure_storage`'ın Android eklentileri. |
| `win32` | 6.4.0 | `MIT` | Windows platform eklentileri. |
| `objective_c` | 9.5.0 | `MIT` | macOS/iOS platform eklentileri. |

> ### ⚠️ Denetlenmemiş iki nokta — dürüstlük notu
>
> 1. **`webrtc_interface` 1.5.1 lisansını beyan etmiyor.** Bu paket
>    `flutter_webrtc`'in dolaylı bağımlılığıdır ve `pubspec`'inde **hiçbir
>    `license` alanı yoktur** (pub.dev kayıt defterinden doğrulandı). Lisansı
>    upstream'de tanımsız bırakılmış bir pakettir. Yeniden dağıtım öncesi kaynağı
>    inceleyin; lisans belirsizliği ticari dağıtımda sorun yaratabilir.
> 2. **Dart tarafının tam transitif listesi denetlenmedi.** `app/pubspec.lock`
>    76 paket içerir; çoğu Dart SDK'sı ve Flutter SDK'sıyla gelen pakettir. Bu
>    dosya yalnızca **doğrudan** bağımlılıkları ve lisansı dikkat çeken birkaç
>    dolaylı bağımlılığı listeler. `path_provider_*`, `flutter_secure_storage_*`
>    ve `jni*` gibi platform eklentilerinin tam kümesi ayrı bir denetim ister.

---

## 4. Tasarım sistemi — `design/`

Kaynak: `design/pubspec.yaml` + `design/pubspec.lock` (47 paket).

| Paket | Sürüm | Lisans | Neden var |
|---|---|---|---|
| `test` | 1.32.0 | `BSD-3-Clause` | **Tek bağımlılık.** Kontrast testi (`design/test/contrast_test.dart`) ve üretilen dosyanın bayt düzeyinde denetimi için. |

Bu paketin **tek bağımlılığının `test` olması bilinçlidir:** üretici ve kapı
Flutter'suz kalsın diye tasarlanmıştır, böylece `dart test` token sözleşmesini
Flutter araç zinciri olmadan doğrular.

> `design/lib/generated/tokens.g.dart` `package:flutter/material.dart` içe
> aktarır, çünkü bir `ThemeExtension` onsuz var olamaz — bu yüzden **yalnız o tek
> dosya** Flutter'dan gelen bir tüketicide analiz edilebilir. Kapı onu asla
> derlemez: kontrast testi dosyayı **bayt** olarak denetler, ki bu daha güçlü bir
> kontroldür. Bu paket de Flutter'a bağımlı değildir ve `pubspec.yaml`'sında
> `flutter` bağımlılığı yoktur.

---

## 5. Sinyalleşme sunucusu — `cloudflare/`

**Worker'ın kendi kaynağında (`cloudflare/src/index.ts`) üçüncü taraf içe aktarımı
yoktur.** Bu doğrulandı: dosyada hiç `import`/`require` yoktur, yalnızca Cloudflare
Workers çalışma zamanının global tipleri (`Request`, `Response`, `WebSocket`,
`DurableObject`, `DurableObjectNamespace`, `DurableObjectState`, `WebSocketPair`)
kullanılır. Bu yüzden AGPL-3.0 altındaki sunucunun **çalışma zamanında** başka bir
paket lisansı devreye girmez.

Kaynak: `cloudflare/package.json` + `package-lock.json` (163 paket). Üçü de
`devDependencies`'tir; **dağıtılan Worker'ın içine hiçbiri girmez.**

| Paket | Sürüm | SPDX | Neden var |
|---|---|---|---|
| `wrangler` | 4.114.0 | `MIT OR Apache-2.0` | Yerel geliştirme (`wrangler dev`), `deploy` ve `deploy --dry-run` — kapının dördüncü adımı. |
| `typescript` | 5.9.3 | `Apache-2.0` | İç tip denetimi. |
| `vitest` | 4.1.10 | `MIT` | Zarf doğrulayıcı (`isSignalPayload`) birim testleri. |

---

## 6. Gömülü / derlenen yerel bileşen

| Bileşen | Sürüm | Lisans | Not |
|---|---|---|---|
| SQLite | `libsqlite3-sys 0.30.1` ile derlenir | **Public domain** (kamu malı) | SQLite kamu malıdır ve telif hakkı tarafından korunmaz; ayrı bir lisans bildirimi gerekmez. Derlenen varyantın kaynak dosyaları paketin içinde gelir ve `LICENSE` metnini taşır. |

---

## 7. Depoda **kopyalanan** lisans metinleri

Aşağıdaki metinler bu depoda tam ve değiştirilmeden bulunur. Bunlar MKVI'nin
**kendi** lisanslarıdır, üçüncü taraf paketlerin lisansları değildir:

| Lisans metni | Dosya | Nerede geçerli |
|---|---|---|
| MIT | [`LICENSE-MIT`](LICENSE-MIT) | Uygulamanın `MIT` şubesini seçen dağıtımlar |
| Apache-2.0 | [`LICENSE-APACHE`](LICENSE-APACHE) | Uygulamanın `Apache-2.0` şubesini seçen dağıtımlar (ayrıca `NOTICE` dosyası da zorunludur ve dağıtılmalıdır) |
| AGPL-3.0 | [`cloudflare/LICENSE`](cloudflare/LICENSE) | **Yalnızca** `cloudflare/` dizini |

Upstream kaynaklar (doğrulama için):

- MIT: <https://spdx.org/licenses/MIT.html>
- Apache-2.0: <https://www.apache.org/licenses/LICENSE-2.0>
- AGPL-3.0: <https://www.gnu.org/licenses/agpl-3.0.html>
- Contributor Covenant 2.1: <https://www.contributor-covenant.org/version/2/1/code_of_conduct/>

**Bu depoda kopyalanmayanlar:** Yukarıdaki tablolardaki her üçüncü taraf paketin
kendi lisans metni, paketin kendi deposundan gelir. MKVI bu metinleri
`LICENSE-*` dosyalarına **gömmez** ve burada da kopyalamaz — bağlantı verilir.
Çoğu Rust paketi lisansını kaynak `Cargo.toml`/dağıtım üst verisinde taşır, npm
paketleri `LICENSE` dosyasıyla birlikte gelir, pub paketleri pub.dev sayfasında
yayımlar. `Apache-2.0` lisansı gerektiren bir paketi **yeniden dağıtırsanız**
(örneğin ikili dosyanın içine gömdüyseniz), paketin kendi `NOTICE`/lisans
dosyalarını **ayrıca** dağıtmanız gerekir.

---

## 8. Değiştirilmiş üçüncü taraf kod var mı?

**Hayır.** Depoda `vendor/`, `third_party/`, `patches/` veya benzeri bir dizin
yoktur ve hiçbir bağımlılık kaynağı fork edilerek içeri alınmamıştır. Dolayısıyla
"değiştirilmiş üçüncü taraf kod" için bir lisans bildirimi gerekmez.

`mkvi_core` ve `mkvi_bridge` **birinci taraf** koddur: uygulamanın kendi
`Apache-2.0 OR MIT` lisansı altındadır, `cloudflare/` dışındadır ve dolayısıyla
AGPL'ye tabi değildir. `cloudflare/` de birinci taraftır ve `cloudflare/LICENSE`
onu açıklar.

## 9. Yeni bağımlılık eklerken

1. Önce **gerekçeyi** buraya yazın. Gerekçe yazılamıyorsa bağımlılık eklemeyin.
2. Lisansı kilit dosyasındaki **o sürüm** için doğrulayın; kopyalamak yerine
   bağlantı verin.
3. Copyleft bir lisans geliyorsa (MPL, GPL, AGPL) hangi yükümlülüğü doğurduğunu
   yazın ve neden kabul edildiğini açıklayın.
4. `THIRD-PARTY-NOTICES.md`'yi güncelleyin. Bu dosya bir yazım işi değil, kapının
   parçasıdır: yanlış veya eksik bir bildirim, doğru bir bildirimden daha kötüdür.
