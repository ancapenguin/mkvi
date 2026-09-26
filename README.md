# MKVI

**MKVI, hesapsız, iki kişi arasında doğrudan (P2P) kişisel iletişim için tasarlanmış
bir masaüstü uygulamasıdır.** Hesap yoktur, telefon numarası yoktur, kullanıcı adı
yoktur. Mesajlar, dosyalar, ses, video ve ekran görüntüsü **bir sunucudan geçmez**;
iki cihaz doğrudan birbirine bağlanır. Sunucu tarafında yalnızca iki cihazın
*birbirini bulması* için gereken küçük paketler iletilir — ve o sunucuyu **siz**
işletirsiniz.

Aşağıdaki bölümler: [durum](#durum) · [mimari](#mimari) ·
[kurulum](#kurulum) · [kendi sinyal sunucunu kur](#kendi-sinyal-sunucunu-kur) ·
[geliştirme](#geliştirme) · [doğrulama](#doğrulama) ·
[0.1.x'in durumu](#01x-in-durumu) · [bilinen sınırlar](#bilinen-sınırlar)

---

## Durum

Bu depo **geliştirme aşamasındadır.** Bugün (2026-09-26) durum şudur:

| Ne | Durum |
|---|---|
| Yayımlanmış bir sürüm | **Yok.** GitHub Releases boş; indirilebilir bir kurulum dosyası yok. |
| Depodaki sürüm | `VERSION` = **0.2.0** — henüz yayımlanmamış, çalışan bir ürün değil. |
| Çalışan son sürüm | **0.1.x** (Tauri hattı). Bu hat **emekliye ayrıldı** ve kodu depodan silindi. |
| Uygulama kabuğu | `app/lib/main.dart` hâlâ `flutter create` şablonudur. Gerçek ekranlar (`app/lib/ui/`) tek tek var ve testli, ama henüz bir uygulamaya bağlanmamıştır. `flutter run` şu an Flutter'ın örnek sayaç uygulamasını açar. |
| Rust çekirdek | `crates/mkvi_core` **tamam ve testli.** |
| Rust köprüsü | `crates/mkvi_bridge` **tamam ve testli**; gerçek bir gidiş-dönüş kanıtı var. Ama uygulama köprüyü henüz çağırmıyor. |
| Otomatik güncelleme | **Çalışmıyor.** Sürüm geçişinde iki cihaza da elle kurulum gerekir. |

Bu, "işin başında olan bir proje" değil; çekirdek ve katmanlar bitti, **montaj ve
dağıtım** sırada. Neyin bittiği, neyin bitmediği ve neden öyle olduğu
[0.1.x'in durumu](#01x-in-durumu) bölümünde ve `ROADMAP.md`'de yazılıdır.

**Yanlış bir izlenim bırakmamak için:** bu depoyu okuyan biri "çalışan bir ürün"
sanabilir. Sanmasın. Kimse iki cihazla arama yapamaz henüz.

---

## Mimari

Üç parça, birbirinden bilinçli olarak ayrılmış:

```text
app/                Flutter arayüz (Windows → macOS/Linux → Android)
  lib/core/protocol/   tel protokolü: kontrol mesajları, dosya çerçevesi
  lib/signaling/       rendezvous istemcisi, payload beyaz listesi, eşleştirme kodu
  lib/session/         kurulum durumu, geri bağlanma döngüsü, kimlik, isimler
  lib/call/            çağrı durum makinesi (donanımsız test edilir)
  lib/chat/            mesaj zaman çizelgesi, dosya aktarımı koordinasyonu
  lib/media/           üç transceiver, replaceTrack, cihaz hatalarının Türkçeleştirilmesi
  lib/settings/        görünüm ve bağlantı ayarları
  lib/update/          güncelleme: feed oku, indir, doğrula, kur
  lib/ui/              ekranlar, widget'lar, bildirim katmanı
crates/mkvi_core/    Rust çekirdek: arayüz kabuğunu bilmez
                      Ed25519, keyring, şifreli SQLite, dosya yazımı, imza doğrulama
crates/mkvi_bridge/  flutter_rust_bridge yüzeyi — Dart'ın Rust'a giden tek kapısı
cloudflare/          sinyal sunucusu (Worker + 2 Durable Object) — AGPL-3.0
design/              tasarımın tek kaynağı: tokens.json + kontrast testi
vectors/             sinyalleşme katmanının tek yazılı biçim sözleşmesi (wire-v1.json)
```

**Katman kuralı:** Dart, Rust'a **yalnızca** `mkvi_bridge` üzerinden dokunur.
`mkvi_core` Flutter'ı bilmez. `cloudflare/` hiçbir şeyi bilmez.

Tam katman haritası, güvenlik sınırları ve "bu ayrım neden var" sorusunun
cevabı: **[`ARCHITECTURE.md`](ARCHITECTURE.md)**. Arayüz ve kabuk neden Flutter'a
taşındı: [`docs/adr/0001-flutter-migration.md`](docs/adr/0001-flutter-migration.md).

### Ne nereye gidiyor

```text
MKVI cihaz A  -- DTLS/SRTP + DataChannel -->  MKVI cihaz B
     |                                                  |
     +---- WSS: yalnızca identity / offer / answer / ICE --+
                       Cloudflare Worker + Durable Object
```

Sunucunun taşıdığı tek şey dört zarf türüdür. `isSignalPayload` anahtar bazında
beyaz listedir; şemaya uymayan her zarf `1008` ile reddedilir. Yani Worker
"ne taşındığını doğrulayan" bir katmandır, keyfî bir içerik taşıyıcısı olamaz.

---

## Kurulum

### Gereksinimler

| Gereksinim | Sürüm | Neden |
|---|---|---|
| [Flutter](https://docs.flutter.dev/get-started/install) | 3.44 veya üzeri (Dart SDK `^3.12.2`) | Arayüz. `app/pubspec.yaml` |
| [Rust](https://rustup.rs) | stable | `mkvi_core` ve `mkvi_bridge` |
| [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/) | **"C++ geliştirme iş yükü" şart** | `rusqlite` SQLite'i `bundled` özelliğiyle **kaynaktan derler**; MSVC olmadan `cargo test` derlenmez |
| [Node.js](https://nodejs.org) | 22 | Yalnızca `cloudflare/` Worker'ı için |

Adım adım, sıfırdan bir Windows makinesinde kurulum:
**[`docs/getting-started.md`](docs/getting-started.md)**.

### Uygulamayı derle ve çalıştır

```powershell
cd app
flutter pub get
flutter run -d windows
```

> **Bugün ne açılacağı:** `app/lib/main.dart` henüz `flutter create` şablonu
> olduğu için **Flutter'ın örnek sayaç uygulaması** açılır. Bu bir hata değil,
> montajın yapılmadığı anlamına gelir. Katmanların hepsi ayrı ayrı test ediliyor
> (`flutter test`), birleştirme sırada. Bkz. `ROADMAP.md` Faz 2.

---

## Kendi sinyal sunucunu kur

**MKVI hiçbir sunucuyu gömmez ve kimseye ücretsiz hizmet vermez.** Uygulamada
varsayılan sinyal adresi **boştur** — `app/lib/settings/connection_settings.dart`
bunu bilinçli olarak reddeden bir girdi olarak tanımlar. Kullanılabilir bir adres
yazmadan uygulama eşleşme ekranından ötesine geçmez.

Sen ve karşındaki kişi, ikinizin de bildiği bir Worker kurarsınız. Adımlar:
**[`cloudflare/README.md`](cloudflare/README.md)**.

```powershell
cd cloudflare
npm install
npx wrangler login
npx wrangler deploy
```

`wrangler deploy` çıktısındaki `https://<ad>.workers.dev` adresini uygulamanın
**Ayarlar → Bağlantı → Sinyal sunucusu** alanına yazın.

### Neden gömülü sunucu yok?

Kısa cevap: **ücretsiz katmanda dayanacak bir sunucu yok.**

Cloudflare'ın ücretsiz planında Durable Object süre kotası **13.000 GB-s / gündür**.
`PairingRoom`, hibernasyon desteklemeyen WebSocket API'sini kullandığı için **her
açık oda süre ücreti yazdırır**. 15 dakikalık bir eşleşme kabaca 115 GB-s
durum maliyetine denk gelir:

```text
13.000 GB-s / gün  ÷  115 GB-s / eşleşme  ≈  110 eşleşme / gün
```

Bu bir **ölçüm değil, kotadan türetilmiş tahmindir** (`cloudflare/README.md` §4).
Sayı ne olursa olsun sonuç kesindir: **ücretsiz bir hesap, günde yaklaşık 110
eşleşmeden sonra tükenir** ve aşan istekler reddedilir. Yani MKVI bir gün
"çalışıyor" görünüp ertesi gün herkes için ölü olurdu — ve bu, kullanıcıya en kötü
şekilde anlatılır.

Bunun yerine: herkes kendi hesabına kurar, verisi kendi hesabında kalır, kimseye
bağımlı olmaz. Ölçeğe ihtiyacı olan biri Workers Paid planı kullanır.

> `cloudflare/` dizini **AGPL-3.0** altındadır. Bu, Worker'ı barındırma hizmeti
> olarak yeniden satmayı engeller. Kendi hesabınızda kendiniz kullanmak sorun
> değildir.

---

## Geliştirme

### Doğrulama — tek kapı

```powershell
.\tool.ps1 gate
```

Sırasıyla şunları çalıştırır ve tek özet verir:

| # | Adım | Komut |
|---|---|---|
| 0 | Sistem kaynakları | RAM / CPU / disk ölçümü — yetersizse uyarır, çünkü "kaynak yetersiz" ile "kod bozuk" karışmasın |
| 1 | Sürüm kaynakları | `VERSION`, `app/pubspec.yaml`, `crates/mkvi_core/Cargo.toml`, `crates/mkvi_bridge/Cargo.toml` eşleşmeli |
| 2 | Rust | `cargo test --locked` (`crates/mkvi_core`) · `cargo test` (`crates/mkvi_bridge`) |
| 3 | Sinyalleşme | `wrangler deploy --dry-run` · `vitest run` (Worker, `cloudflare/`) |
| 4 | Tasarım | `dart analyze` · `dart test` (kontrast testleri) |
| 5 | Flutter | `flutter analyze` · `flutter test` (`app/`) |
| 6 | Kodlama | BOM, bozuk Türkçe metin, ham NUL baytı |

Ağır derlemeden önce sadece kaynakları görmek için: `.\tool.ps1 resources`.
Yalnız hızlı adımlar: `.\tool.ps1 gate-quick`. Release derlemesi:
`.\tool.ps1 build` (`flutter build windows --release`).

**Köprü artık kapının bir parçası.** `crates/mkvi_bridge` 15 testini daha önce hiçbir
yer koşmuyordu; "yeşil" olmak "test edildi" demek değildi.

### Tek tek komutlar

```powershell
# Flutter uygulaması
cd app;  flutter pub get;  flutter test;  flutter analyze

# Rust çekirdek ve köprü
cd crates/mkvi_core;   cargo test
cd crates/mkvi_bridge; cargo test

# Tasarım kontrast testi (Flutter'suz)
cd design; dart test

# Sinyalleşme sunucusu
cd cloudflare; npm install; npm run check; npm test
```

Köprünün gerçek gidiş-dönüş kanıtı (Dart → FFI → Rust → FFI → Dart):

```powershell
cd crates/mkvi_bridge;  cargo build --release
cd crates\mkvi_bridge\dart;  dart pub get;  dart run bin/round_trip.dart
```

> ⚠️ Bu betik **gerçek bir cihaz kimliği üretir** ve Windows Credential Manager'a
> `device-signing-key-v1` ve `history-key-v1` kayıtlarını yazar. Silmeyin: silmek
> kayıtlı bir eşi öksüz bırakmaktır.

> **`dart test` `app/` içinde çalışmaz.** `app` bir Flutter paketidir ve
> `package:test` bağımlılık grafiğinde yoktur; orada `flutter test` kullanılır.
> `dart test` yalnız `design/` için geçerlidir.

---

## 0.1.x'in durumu

**0.1.x yayımlanmış ve gerçek Windows cihazlarda iki kişi arasında denendi. 2026-09-26'da
emekliye ayrıldı ve kodu depodan silindi.** Bunu saklamıyoruz, çünkü sürüm geçişiyle
ilgili bir tuzak var.

**Geçişte iki cihazın da yeni sürümü elle kurmanız gerekiyor. Otomatik güncelleme
çalışmıyor.** Sebebi ölçülmüştür:

- 0.1.x'in güncelleme adresi (`ancapenguin/mkvi-updates`) **404** dönüyor. Bu adres
  2026-09-26'da canlı olarak doğrulandı: indirilebilir bir 0.1.4 kurulum dosyası
  **yoktur**, GitHub Releases boştur. 0.1.x'i durduran şey anahtar değil, ölü feed'dir.
- Yayın anahtarı minisign'in emekli `Ed` biçimindedir. 0.1.x'i bu engellemiyordu
  (`tauri-plugin-updater` `allow_legacy = true` ile çağırıyor), ama 0.2.0'ın çekirdeği
  bilinçli olarak katıdır (`allow_legacy` sabit `false`), yani aynı anahtar
  **0.2.0'ın bütün imzalarını sessizce reddeder.** Kök çözüm: ilk Flutter
  sürümünden önce prehashed bir yayın anahtarı üretmek.

Yani: 0.1.x'i kullanıyorsanız, 0.2.0'a geçerken **iki tarafta da** elle kurulum
yapacaksınız. Feed GitHub Releases'e taşınana kadar başka bir yol yok.

0.1.x hattı neden emekliye ayrıldı: 0.1.4 gerçek cihazlarda denendi ve **on kök
neden** çıktı. İkisi ürünü kullanılamaz hale getiriyordu — kamera ve ekran
paylaşımı **hiç** çalışmıyordu (sebep kod değil platformdu: Tauri'ın WebView2 izin
handler'ı yok) ve yeniden bağlanma çalışmıyordu (dört ayrı hata).

**O hattın ne olduğu, neyi kanıtladığı ve o kanıtın nereye taşındığı** tek bir miras
kaydında duruyor: **[`docs/legacy-tauri-line.md`](docs/legacy-tauri-line.md)**. Bu bir
kullanım kılavuzu değil, bir kayıttır; oradaki hiçbir şeyi çalıştırmaya çalışmayın.

---

## Bilinen sınırlar

Bu liste bilerek yayımlanıyor. Sessizce eksik bırakmak daha kötü olurdu.

### Bilinen güvenlik açığı — SAS, DTLS parmak izine **bağlanmadı**

0.1.x'te kullanıcıya gösterilen karşılaştırma ifadesi (SAS) **yalnızca eşleştirme
kodu ve sıralanmış cihaz açık anahtarlarından** türetiliyordu.
**DTLS sertifika parmak izlerini içermiyordu.**

**Somut sonuç:** Sinyalleşme sunucusunu kontrol eden (sunucuyu işleten veya ağ
üzerinde onun yerine geçen) bir saldırgan, araya girip **her iki tarafa da aynı
ifadeyi** gösterebilir. Kullanıcılar ifadelerin eşleştiğini görüp onayladığında,
saldırgan iki tarafın da trafiğini okuyup değiştirebiliyor olabilir.

0.2.0'da bu ifade **henüz hiç bağlanmadı** — Rust çekirdekte de, Dart tarafında da
`dtls`/parmak izi kodu yoktur. Bu, `ROADMAP.md`'de *"Faz 1 güvenlik açığı"*
diye adlandırılan ve **Faz 4**'te açık madde olarak izlenen iş kalemidir.

**Kapsam:** Mimari gereği sunucu içerik taşımaz; bu açık **gizliliği değil kimlik
doğruluğunu** etkiler. Anahtar değişimi, şifreleme ve yerel anahtar kasası
etkilenmez. Ama bu açık kapanana kadar **ciddi bir karşı taraf (MITM) saldırısına
karşı uygulama güvenli sayılmaz.** Kısa kodun tahmin edilemez olmasına ve
cihaz imzalarının yerel doğrulanmasına güvenerek karar vermeyin.

Ayrıntılı güvenlik modeli ve bildirim kanalı: [`SECURITY.md`](SECURITY.md).

### Diğer sınırlar

- **Yalnız Windows'ta test edildi.** Diğer platformlar yol haritasında.
- **Kurulum dosyası imzasız** (yayımlanmış bir kurulum dosyası henüz yok).
- **HDR ekranda renk bozuk** — `flutter_webrtc` WGC arka ucu taşımıyor (#2205).
- **Sessiz ekran paylaşımı başarısızlığı mümkün** — `getDisplayMedia` başarılı
  dönüp kare üretmeyebilir (#2137). Uygulama bunu bir "ilk kare" izleyicisiyle
  kovalamaya çalışıyor; kanıtlanmış değil.
- **Veritabanı sayfaları şifreli değil.** Mesaj gövdesi XChaCha20-Poly1305 ile
  şifrelenir ama SQLite'ın WAL/journal sayfaları bu şifrelemenin dışındadır
  (SQLCipher yok). `ROADMAP.md` Faz 4'te izleniyor.
- **Sinyal sunucusu isteğe bağlı değil ama ücretsiz değil.** Bkz.
  [Kendi sinyal sunucunu kur](#kendi-sinyal-sunucunu-kur).

---

## Depo düzeni

| Yol | Ne |
|---|---|
| `app/` | Flutter uygulaması |
| `crates/mkvi_core/` | Arayüz kabuğundan bağımsız Rust çekirdek |
| `crates/mkvi_bridge/` | `flutter_rust_bridge` yüzeyi — Dart'ın Rust'a giden tek kapısı |
| `cloudflare/` | sinyal sunucusu (AGPL-3.0) |
| `design/` | tasarımın tek kaynağı ve kontrast testi |
| `vectors/` | sinyalleşmenin tek yazılı biçim sözleşmesi (0.1.x'te Dart ve TypeScript bu dosyayı birlikte okuyordu) |
| `docs/adr/` | mimari kararlar |
| `docs/getting-started.md` | sıfırdan kurulum |
| `docs/manual-test.md` | iki cihazla elle test protokolü |
| `docs/legacy-tauri-line.md` | 0.1.x hattının **miras kaydı** (emekli) |
| `tool.ps1` | tek kapı: `.\tool.ps1 gate` |

Mimari: [`ARCHITECTURE.md`](ARCHITECTURE.md) · Plan: `ROADMAP.md` ·
Kararlar: [`docs/adr/`](docs/adr/) · İlk kurulum:
[`docs/getting-started.md`](docs/getting-started.md)

---

## Lisans

- **Uygulama** (`app/`, `crates/`, `design/`, `vectors/`): **Apache-2.0 OR MIT** —
  ikili lisans, siz şubesini seçersiniz. Metinler: [`LICENSE-APACHE`](LICENSE-APACHE),
  [`LICENSE-MIT`](LICENSE-MIT), bildirim: [`NOTICE`](NOTICE).
- **Sinyal sunucusu** (`cloudflare/`): **AGPL-3.0** — metin:
  [`cloudflare/LICENSE`](cloudflare/LICENSE).

Sinyal sunucusunun ayrı ve daha güçlü lisanslı olması bilinçlidir: MKVI'nin
başkasının cebinden bedava kamu hizmeti olarak çalıştırılıp satılmasını engeller.
Kendi sunucunu kurup kendi kaynaklarını kullanmak serbesttir.

Üçüncü taraf bağımlılıkların tamamı, gerekçeleriyle:
**[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)**.

---

## Güvenlik

**Güvenlik açığını herkese açık bir issue'da yazmayın.**
GitHub'ın özel güvenlik bildirim kanalını kullanın (doğrudan bağlantı ve yedek
yol `SECURITY.md`'de).

Desteklenen sürümler, güvenlik modeli, yanıt süreleri ve **bilinen açıklar**:
**[`SECURITY.md`](SECURITY.md)**.

## Katkı

Katkıda bulunmak istiyorsanız: **[`CONTRIBUTING.md`](CONTRIBUTING.md)**.
Değerler: [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

Bu proje **tek bakımcılıdır.** Katkılarınız için teşekkür ederiz; yanıt süreleri
bir taahhüt değil, makul bir beklenti olarak seçilmiştir.

---

MKVI contributors · 2026
