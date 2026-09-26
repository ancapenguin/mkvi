# Üçüncü taraf bildirimleri

MKVI, aşağıdaki üçüncü taraf yazılımları kullanır. Bu dosya, bağımlılıkların hangi
lisansla geldiğini ve projede **neden** bulunduğunu kayda geçirir.

**Kapsam ve doğrulama**

- Depo **üç ayrı bağımlılık yüzeyi** taşıyor. Sürümler şu kilit dosyalarından
  okunmuştur:
  - Rust çekirdek: `crates/mkvi_core/Cargo.lock`
  - Rust Tauri adaptörü: `src-tauri/Cargo.lock`
  - JavaScript (kök): `package-lock.json`
  - JavaScript (sinyalleşme): `cloudflare/package-lock.json`
  - Dart/Flutter: `app/pubspec.lock`
- SPDX kimlikleri, kilit dosyalarındaki her paketin **o sürümü** için crates.io,
  npm veya pub.dev kayıt defterinden alınmıştır. Sürüm değişirse bu tablo da
  değişmelidir; `dependabot` güncellemelerinden sonra gözden geçirin.
- Bu tablo **doğrudan** bağımlılıkları ve lisansı dikkat çeken dolaylı
  bağımlılıkları kapsar. Kilit dosyalarının kendileri kapsamın tamamıdır.
- **Rust tarafında iki ayrı paket vardır ve bunlar tek bir Cargo workspace'i
  değildir** (`crates/mkvi_core/Cargo.toml` başındaki nota bakın). Dolayısıyla
  iki ayrı `Cargo.lock` ve iki ayrı bağımlılık listesi vardır; ikisi de
  aşağıdadır.

**Lisans özeti:** MKVI'nin kendi kodu `Apache-2.0 OR MIT` (ikili lisans).
`cloudflare/` dizini ayrı olarak `AGPL-3.0`. Aşağıdaki üçüncü taraf paketlerin
hiçbiri MKVI'nin kendi lisansını değiştirmez.

---

## 1. Rust çekirdek — `crates/mkvi_core`

Kaynak: `crates/mkvi_core/Cargo.toml` + `crates/mkvi_core/Cargo.lock`
Bu paket Tauri'ye bağlı **değildir**; güvenlik, kimlik, şifreli geçmiş, dosya
alımı ve güncelleme imza doğrulamasını barındırır.

| Paket | Sürüm | SPDX | Projedeki rolü |
|---|---|---|---|
| `keyring` | 3.6.3 | `MIT OR Apache-2.0` | Cihaz Ed25519 anahtarı ve veritabanı anahtarını işletim sistemi kasasında tutar |
| `rusqlite` | 0.32.1 | `MIT` | Yerel şifreli mesaj geçmişi veritabanı |
| `ed25519-dalek` | 2.2.0 | `BSD-3-Clause` | Cihaz kimliği: anahtar çifti ve zarfların imzalanması/doğrulanması |
| `chacha20poly1305` | 0.10.1 | `Apache-2.0 OR MIT` | XChaCha20-Poly1305 ile mesaj geçmişi ve dosya aktarımı şifrelemesi |
| `minisign-verify` | 0.3.0 | `MIT` | Gelecek kendi kendini güncelleyen akışta güncelleme imzasının saf doğrulaması (ağ yok, asenkron yok) |
| `zeroize` | 1.9.0 | `Apache-2.0 OR MIT` | Çözülmüş cihaz tohumu ve veritabanı anahtarının yığından silinmesi |
| `rand_core` | 0.6.4 | `MIT OR Apache-2.0` | `getrandom` tabanlı rastgelelik (nonce, cihaz kimliği) |
| `serde` | 1.0.229 | `MIT OR Apache-2.0` | Serileştirme (`derive`) |
| `serde_json` | 1.0.151 | `MIT OR Apache-2.0` | Saklanan kayıtların ve zarfların JSON biçimi |
| `base64` | 0.22.1 | `MIT OR Apache-2.0` | Anahtar ve imza baytlarının tel üzerindeki gösterimi |
| `thiserror` | 2.0.21 | `MIT OR Apache-2.0` | Hata türleri için `derive(Error)` |
| `tempfile` | 3.27.0 | `MIT OR Apache-2.0` | Yalnızca testlerde geçici dosya |

Öne çıkan dolaylı bağımlılıklar:

| Paket | Sürüm | SPDX | Not |
|---|---|---|---|
| `libsqlite3-sys` | 0.30.1 | `MIT` | `rusqlite` bağımlılığı; SQLite'i **derlenmiş** (bundled) olarak getirir |
| `curve25519-dalek` | 4.1.3 | `BSD-3-Clause` | `ed25519-dalek` ve `chacha20poly1305` altında ed25519 aritmetiği |
| `ed25519` | 2.2.3 | `Apache-2.0 OR MIT` | `ed25519-dalek` uygulama detayları |
| `r-efi` | 6.0.0 | `MIT OR Apache-2.0 OR LGPL-2.1-or-later` | UEFI/çıplak metal hedefleri; **isteğe bağlı** LGPL. MKVI `MIT`/`Apache-2.0` şubesini seçer, LGPL yükümlülüğü doğmaz |

### 1a. Rust Tauri adaptörü — `src-tauri`

Kaynak: `src-tauri/Cargo.toml` + `src-tauri/Cargo.lock`
Bu paket yalnızca pencere/IPC/güncelleme eklentisidir; çekirdek mantık
`mkvi_core` içindedir.

| Paket | Sürüm | SPDX | Projedeki rolü |
|---|---|---|---|
| `tauri` | 2.11.5 | `Apache-2.0 OR MIT` | Masaüstü kabuk: pencere, IPC, sistem menüsü |
| `tauri-plugin-updater` | 2.10.1 | `Apache-2.0 OR MIT` | İmzalı güncelleme akışı |
| `tauri-build` | 2.6.3 | `Apache-2.0 OR MIT` | `build.rs`; `tauri.conf.json` şemasını doğrular |
| `mkvi_core` | 0.1.4 | — | **Birinci taraf.** Yol bağımlılığı (`../crates/mkvi_core`); AGPL değil, aynı `Apache-2.0 OR MIT` |
| `wry` | 0.55.1 | `Apache-2.0 OR MIT` | WebView2'ye gömülü WebView taşıması |
| `tao` | 0.35.3 | `Apache-2.0` | Pencere olay döngüsü |
| `base64` | 0.22.1 | `MIT OR Apache-2.0` | Bu paketin kendi kullanımı için de doğrudan bağımlılık |
| `serde` | 1.0.229 | `MIT OR Apache-2.0` | `tauri::generate_context!` bunları isimlendirdiği için burada da gerekli |
| `serde_json` | 1.0.151 | `MIT OR Apache-2.0` | Aynı nedenle |

> `base64`, `serde` ve `serde_json` bu pakette **kullanılmayan** doğrudan
> bağımlılıklardır; `tauri::generate_context!` ürettiği kod bunları isimlendirir.
> `Cargo.toml` içindeki yorum da bunu açıklar.

### 1b. Güncelleme imzasının doğrulama zinciri

`tauri-plugin-updater` güncelleme imzasını `minisign-verify` ile doğrular;
`mkvi_core::update` aynı doğrulamayı saf hâlde yapar. İki farklı
`minisign-verify` sürümü çözümlemesinde bir arada bulunur
(`src-tauri/Cargo.lock`: 0.2.5 ve 0.3.0).

| Paket | Sürüm | SPDX | Not |
|---|---|---|---|
| `minisign-verify` | 0.2.5 | `MIT` | `tauri-plugin-updater` zincirinden |
| `minisign-verify` | 0.3.0 | `MIT` | `mkvi_core` doğrudan bağımlılığı |
| `ring` | 0.17.14 | `Apache-2.0 AND ISC` | Hash ve imza çekirdeği |
| `rustls` | 0.23.42 | `Apache-2.0 OR ISC OR MIT` | Güncelleme feed'inin indirilmesinde TLS |
| `rustls-webpki` | 0.103.13 | `ISC` | X.509 ve sertifika doğrulama |
| `webpki-root-certs` | 1.0.9 | `CDLA-Permissive-2.0` | Kök sertifika deposu (yalnızca okuma, değiştirilmedi) |

> **`minisign` hakkında bir düzeltme:** `minisign-verify` 0.2.5 `Cargo.lock`
> içinde **hiçbir bağımlılık listelemeden** geliyor; yani ayrı bir `minisign`
> paketi çekilmiyor. Hiçbir `Cargo.lock` içinde `minisign` adlı bir paket
> bulunmadığı doğrulandı. (Bu satır, yanlış bir bağımlılık listelememek için
> konuldu; sürüm yükseltirken yeniden kontrol edin.)

### 1c. Windows ve WebView2 bağımlılıkları

| Paket | Sürüm | SPDX | Projedeki rolü |
|---|---|---|---|
| `windows` | 0.61.3 | `MIT OR Apache-2.0` | Windows API bağlantıları |
| `windows-core` | 0.61.2 | `MIT OR Apache-2.0` | `windows` altyapısı |
| `webview2-com` | 0.38.2 | `MIT` | WebView2 COM arayüzü (kurulu değilse hata yönetimi) |

`windows` ailesinin tamamı `MIT OR Apache-2.0`'dir ve bağımlılık grafiğinde
yüzlerce `windows_*` alt paketi bulunur; hepsi aynı aileden lisanslıdır ve
tabloya tek satırla özetlenmiştir.

### 1d. Grafik arayüzü erişilebilirlik (üçüncü taraf, lisansı kendi içinde)

Bu dört paket `cssparser` → `selectors` zinciri üzerinden **tauri → dom_query**
ile gelir. `option-ext` ise `dirs` üzerinden gelir. Dördü de **`MPL-2.0`**, yani
**dosya düzeyinde** copyleft'tir.

| Paket | Sürüm | SPDX | Not |
|---|---|---|---|
| `cssparser` | 0.36.0 | `MPL-2.0` | **Dosya düzeyinde** copyleft |
| `cssparser-macros` | 0.6.1 | `MPL-2.0` | `cssparser` ile birlikte gelir |
| `selectors` | 0.36.1 | `MPL-2.0` | **Dosya düzeyinde** copyleft |
| `dtoa-short` | 0.3.5 | `MPL-2.0` | **Dosya düzeyinde** copyleft |
| `option-ext` | 0.2.0 | `MPL-2.0` | **Dosya düzeyinde** copyleft; `dirs` bağımlılığı |
| `dom_query` | 0.27.0 | `MIT` | `tauri` → `dom_query` → `cssparser`/`selectors` zincirinin kendisi |
| `dirs` | 6.0.0 | `MIT OR Apache-2.0` | Yapılandırma dizini; `option-ext` zincirini başlatır |

**Bu MKVI'yi etkilemez — neden:** MPL-2.0 bir **dosya düzeyinde** copyleft
lisansıdır. Yükümlülük yalnızca paketin **kendi dosyaları** değiştirilirse
doğar ve bu durumda yalnızca o dosyalar MPL altında dağıtılır. MKVI bu paketlerin
tek bir satırını değiştirmediği için kendi kodunu `Apache-2.0 OR MIT` altında
dağıtmaya devam eder. MPL-2.0 ayrıca zayıf copyleft'tir: bir "genel kullanım"
istisnası (LPG) aracılığıyla ticari kullanımı da yasaklamaz. Yine de bu
bağımlılık zinciri bir **lisans denetimi gerektirir**: ileride `dom_query` veya
`dirs` yolu değişirse veya bir `MPL-2.0` paketi doğrudan bağımlılık haline
gelirse bu not güncellenmelidir.

### 1e. Rust tarafında dikkat gerektiren diğer lisanslar

| Paket | Sürüm | SPDX | Not |
|---|---|---|---|
| `r-efi` | 5.3.0 | `MIT OR Apache-2.0 OR LGPL-2.1-or-later` | `src-tauri` zincirinden. **İsteğe bağlı** LGPL; MKVI `MIT`/`Apache-2.0` şubesini seçer, LGPL yükümlülüğü doğmaz |
| `icu_normalizer` | 2.2.0 | `Unicode-3.0` | Unicode konsorsiyumunun ayrı, izinli lisansı; `url`/`idna` zinciri |
| `icu_properties` | 2.2.0 | `Unicode-3.0` | Aynı aile |
| `icu_locale_core` | 2.2.0 | `Unicode-3.0` | Aynı aile |
| `url` | 2.5.8 | `MIT OR Apache-2.0` | URL ayrıştırma (`tauri-utils` üzerinden) |
| `idna` | 1.1.0 | `MIT OR Apache-2.0` | Uluslararası alan adı normalleştirme |
| `miniz_oxide` | 0.8.9 | `MIT OR Zlib OR Apache-2.0` | Arşiv/bundle sıkıştırması; `MIT` şubesi kullanılır |

`Unicode-3.0` ve `CDLA-Permissive-2.0` izinli (permissive) lisanslardır; kaynak
koşulları **dağıtımda lisans metninin belirtilmesini** gerektirir, kod
türevlerine copyleft yükümlülüğü getirmez.

---

## 2. JavaScript / TypeScript — uygulama (kök `package.json`)

Sürümler `package-lock.json`'dan okunmuştur.

| Paket | Sürüm | SPDX | Projedeki rolü |
|---|---|---|---|
| `react` | 19.2.8 | `MIT` | Arayüz |
| `react-dom` | 19.2.8 | `MIT` | React DOM render katmanı |
| `@types/react` | 19.2.17 | `MIT` | Tip tanımları (yalnızca derleme) |
| `@types/react-dom` | 19.2.3 | `MIT` | Tip tanımları (yalnızca derleme) |
| `@tauri-apps/api` | 2.11.1 | `Apache-2.0 OR MIT` | Frontend → Rust komut çağrıları, olay dinleme |
| `@tauri-apps/plugin-updater` | 2.10.1 | `MIT OR Apache-2.0` | Güncelleme kontrolü ve indirme arayüzü |
| `vite` | 7.3.6 | `MIT` | Geliştirme sunucusu ve üretim derlemesi |
| `@vitejs/plugin-react` | 4.7.0 | `MIT` | JSX dönüşümü ve Fast Refresh |
| `vitest` | 4.1.10 | `MIT` | Birim test koşucusu (`npm test`) |
| `typescript` | 5.8.3 | `Apache-2.0` | Tip denetimi (`npx tsc --noEmit`) |
| `@tauri-apps/cli` | 2.11.4 | `Apache-2.0 OR MIT` | `tauri dev` / `tauri build` komutları |

---

## 4. Dart / Flutter istemcisi (`app/`)

Kaynak: `app/pubspec.yaml` (doğrudan bağımlılıklar) + `app/pubspec.lock`
(çözümlenmiş sürümler). Flutter istemcisi Tauri/React istemcisinin yerine
geçiriliyor; Rust tarafını `flutter_rust_bridge` üzerinden çağırır.

| Paket | Sürüm | Lisans | Projedeki rolü |
|---|---|---|---|
| `flutter_webrtc` | 1.6.2+hotfix.3 | `MIT` | P2P taşıma (`webrtc_interface` 1.5.1 ile gelir) |
| `flutter_secure_storage` | 11.2.0 | `BSD-3-Clause` | Android'de platform kasası; masaüstünde kasayı Rust çekirdek yapar |
| `path_provider` | 2.1.6 | `BSD-3-Clause` | Uygulama veri dizini ve indirme klasörü |
| `http` | 1.6.0 | `BSD-3-Clause` | Güncelleme bildirimi ve indirme; **imza doğrulaması Rust'ta** |
| `cupertino_icons` | 1.0.9 | `MIT` | Simgeler |
| `flutter_lints` | 6.0.0 | `BSD-3-Clause` | Yalnızca geliştirme (`dev_dependencies`) |
| `flutter`, `flutter_test`, `flutter_web_plugins`, `flutter_driver`, `integration_test`, `sky_engine` | SDK ile gelir | `BSD-3-Clause` (Flutter) | Flutter SDK'sının kendi paketleri; `sdk: flutter` ile çözümlenir |

### ⚠️ Denetlenmemiş iki nokta — dürüstlük notu

1. **`webrtc_interface` 1.5.1 lisansını beyan etmiyor.** Bu paket
   `flutter_webrtc`'in dolaylı bağımlılığıdır ve `pubspec`'inde **hiçbir
   `license` alanı yoktur** (pub.dev kayıt defterinden doğrulandı). Lisansı
   upstream'de tanımsız bırakılmış bir pakettir. Yeniden dağıtım öncesi
   kaynağı inceleyin; lisans belirsizliği ticari dağıtımda sorun yaratabilir.
2. **Dart tarafının tam transitif listesi denetlenmedi.** `app/pubspec.lock`
   yaklaşık 70 paket içerir; çoğu Dart SDK'sı ve Flutter SDK'sıyla gelen
   pakettir. Bu dosya yalnızca **doğrudan** bağımlılıkları doğrulanmış olarak
   listeler. `path_provider_*`, `flutter_secure_storage_*` ve `jni*` gibi
   platform eklentilerinin transitif kümesi ayrı bir denetim ister.

---

## 5. Sinyalleşme sunucusu (`cloudflare/`)

**Worker'ın kendi kaynağında (`cloudflare/src/index.ts`) üçüncü taraf içe
aktarımı yoktur.** Bu doğrulandı: dosyada hiç `import`/`require` yok, yalnızca
Cloudflare Workers çalışma zamanının global tipleri (`Request`, `Response`,
`WebSocket`, `DurableObject`, `DurableObjectNamespace`, `DurableObjectState`,
`WebSocketPair`) kullanılıyor. Bu yüzden AGPL-3.0 altındaki sunucunun **çalışma
zamanında** başka bir paket lisansı devreye girmez.

Yalnızca geliştirme araçları bağımlıdır; sürümler `cloudflare/package-lock.json`dan
okunmuştur.

| Paket | Sürüm | SPDX | Projedeki rolü |
|---|---|---|---|
| `wrangler` | 4.114.0 | `MIT OR Apache-2.0` | Yerel geliştirme, `deploy`, `deploy --dry-run` (gate komutu) |
| `typescript` | 5.9.3 | `Apache-2.0` | `wrangler` içindeki tip denetimi |
| `vitest` | 4.1.10 | `MIT` | Zarf doğrulayıcı birim testleri |

---

## 6. Gömülü / derlenen yerel bileşen

| Bileşen | Sürüm | Lisans | Not |
|---|---|---|---|
| SQLite | `libsqlite3-sys 0.30.1` ile derlenir | **Public domain** (kamu malı) | SQLite kamusal maldır ve telif hakkı tarafından korunmaz; ayrı bir lisans bildirimi gerekmez |

> **SQLCipher etkin DEĞİL.** `rusqlite` (`crates/mkvi_core` içinde) şu anda
> `bundled` özelliğiyle derlenen
> **düz** SQLite'i getiriyor; `bundled-sqlcipher` özelliği kullanılmıyor.
> Veritabanı dosyasının kendisi **uygulama katmanında**
> XChaCha20-Poly1305 ile şifrelenir (anahtar işletim sistemi kasasında), ancak
> SQLite'ın WAL/journal sayfaları bu şifrelemenin dışındadır. Bu, bilinen ve
> kabul edilmiş bir sınırdır; SQLCipher'a geçiş `ROADMAP.md` içinde izlenen
> açık bir iş kalemidir. Geçiş yapılırsa bu tabloya `SQLite (SQLCipher varyantı)`
> satırı ve `SQLite` kamu malı notunun güncellenmesi gerekir.

---

## 7. Bu değişiklikle birlikte **aynen** dağıtılan lisans metinleri

Aşağıdaki metinler bu depoda tam ve değiştirilmeden bulunur. Kopyalanan tek
lisans dosyaları bunlardır:

| Lisans metni | Dosya | Nerede geçerli |
|---|---|---|
| MIT | `LICENSE-MIT` | Uygulamanın `MIT` şubesini seçen dağıtımlar |
| Apache-2.0 | `LICENSE-APACHE` | Uygulamanın `Apache-2.0` şubesini seçen dağıtımlar (ayrıca `NOTICE` dosyası da zorunludur ve dağıtılmalıdır) |
| AGPL-3.0 | `cloudflare/LICENSE` | **Yalnızca** `cloudflare/` dizini |
| Contributor Covenant 2.1 | `CODE_OF_CONDUCT.md` | Topluluk davranışı; lisans değildir |

Upstream kaynaklar (doğrulama için):

- MIT: <https://spdx.org/licenses/MIT.html>
- Apache-2.0: <https://www.apache.org/licenses/LICENSE-2.0>
- AGPL-3.0: <https://www.gnu.org/licenses/agpl-3.0.html>
- Contributor Covenant 2.1: <https://www.contributor-covenant.org/version/2/1/code_of_conduct/>

**Bu depoda kopyalanmayanlar:** Yukarıdaki tabloya giren her üçüncü taraf paketin
kendi lisans metni, paketin kendi deposundan gelir. MKVI bu metinleri
`LICENSE-*` dosyalarına gömmez; çoğu Rust paketi lisansını kaynak
`Cargo.toml`/dağıtım üst verisinde taşır ve npm paketleri `LICENSE` dosyasıyla
birlikte gelir. `Apache-2.0` lisansı gerektiren bir paketi yeniden dağıtırsanız,
paketin kendi `NOTICE`/lisans dosyalarını **ayrıca** dağıtmanız gerekir.

---

## 8. Değiştirilmiş üçüncü taraf kod var mı?

**Hayır.** Depoda `vendor/`, `third_party/`, `patches/` veya benzeri bir dizin
yoktur ve hiçbir bağımlılık kaynağı fork edilerek içeri alınmamıştır. Dolayısıyla
"değiştirilmiş üçüncü taraf kod" için bir lisans bildirimi gerekmez.

**MKVI'nin kendi `cloudflare/` dizini AGPL-3.0 altındadır** ve bu, bir
üçüncü taraf değil birinci taraf koddur; `cloudflare/LICENSE` bunu açıklar.

`crates/mkvi_core` de birinci taraf koddur: uygulamanın kendi `Apache-2.0 OR MIT`
lisansı altındadır, `cloudflare/` dışındadır ve dolayısıyla AGPL'ye tabi değildir.
