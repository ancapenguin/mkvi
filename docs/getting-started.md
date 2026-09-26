# Sıfırdan kurulum (Windows)

Bu belge, **temiz bir Windows makinesinde** MKVI'yi çalıştırmak için gereken
her adımı, her adımda **ne yazılacağını**, **ne beklendiğini** ve **ne çıkarsa
hatanın ne olduğunu** içerir.

Sıfırdan kurmak zorunda değilseniz: [README](../README.md) yeterlidir. Buraya
yalnız "ilk kez kuruyorum" diyorsanız gelin.

> **Sürüm notu (2026-09-26):** Bu belge 0.2.0 (Flutter) hattı içindir. 0.1.x
> (Tauri) hattı **emekliye ayrıldı ve depodan silindi**; o hattın kurulum talimatları
> artık geçerli değildir. 0.1.x'in ne olduğu: `docs/legacy-tauri-line.md`.

---

## 0. Kurulumdan sonra ne olacak, ne olmayacak

Bunu baştan söyleyelim, sonra kısa gider:

| | Durum |
|---|---|
| `.\tool.ps1 gate` yeşil olacak | **Evet.** Tüm kapı koşar. |
| `flutter test` yeşil olacak | **Evet.** Katmanların testleri var. |
| `cargo test` yeşil olacak | **Evet.** Çekirdek ve köprü testli. |
| `flutter run -d windows` **MKVI'yi** açacak | **Hayır.** `app/lib/main.dart` hâlâ `flutter create` şablonudur; Flutter'ın örnek sayaç uygulaması açılır. |
| Uygulama Rust çekirdeği çağıracak | **Hayır.** Köprü `crates/mkvi_bridge` altında çalışıyor ve testli, ama uygulama onu henüz içe aktarmıyor. |
| İki kişi eşleşip arama yapabilecek | **Hayır.** Uygulama kabuğu bağlanmadan bu mümkün değil. |

Bunlar eksiklik değil, **durumun dürüst bir listesi**. Ne yapıldığı:
`ROADMAP.md`, ne ölçülecek: `docs/manual-test.md`.

> Yine de kurulumu tam yapın: katmanlar hazır, birleştirme sırada ve siz de
> odayı biliyorsanız katkı vermek için idealdir. Katkı rehberi:
> [`CONTRIBUTING.md`](../CONTRIBUTING.md).

---

## 1. Flutter SDK

### Kurulum

1. <https://docs.flutter.dev/get-started/install> adresinden Windows için
   **stable** SDK'yı indirin. (Yol haritasındaki sürüm: Flutter 3.44 veya üzeri;
   `app/pubspec.yaml` Dart SDK `^3.12.2` istiyor.)
2. ZIP'i açın — örneğin `C:\src\flutter`. **Sürücü köküne (`C:\flutter`)
   açmayın**; yol boşluk ve Türkçe karakter içermemelidir.
3. `Settings → Environment Variables → Path` altına `C:\src\flutter\bin` ekleyin.
4. PowerShell'i **yeniden açın** (açık olanlarda PATH eski kalır).

### Doğrulama

```powershell
flutter --version
dart --version
flutter doctor
```

`flutter --version` en az **3.44** göstermeli. `flutter doctor`'da
**`[√] Flutter`** ve **`[√] Windows toolchain`** yeşil olmalı.

### Eğer `flutter` tanınmıyorsa

`flutter` bir komut değil, PATH'teki bir toplu işlev dosyasıdır. PowerShell
**çalışma politikası** yüzünden tanıyabilir ama CMD tanımayabilir ya da tersi.
Tam yol çalıştırın: `& "C:\src\flutter\bin\flutter.bat" --version`.

### Eğer `flutter doctor` "Android toolchain" kırmızıysa

**Sorun değil.** MKVI'nin Android fazı yol haritasında ve henüz derlenmiyor
(`keyring` 3'ün Android arka ucu yok). Bu adımı atlayın.

---

## 2. Rust

```powershell
winget install Rustlang.Rustup
```

Kurulumdan sonra PowerShell'i yeniden açın, sonra:

```powershell
rustc --version
cargo --version
```

Beklenen: `stable` kanalında bir sürüm. `crates/mkvi_core` ve
`crates/mkvi_bridge` `edition = "2021"` kullanır; çok eski bir araç zinciri
sorun çıkarır.

---

## 3. Visual Studio Build Tools — **atlamayın**

Bu adım en çok atlatan ve en çok hata ayıklatan adımdır.

1. <https://visualstudio.microsoft.com/downloads/> adresinden
   **Visual Studio Build Tools**'ı indirin (IDE değil, Build Tools yeterli).
2. Kurulumda **"Desktop development with C++"** iş yükünü seçin. İçinde şu üç
   bileşen bulunmalıdır:

   | Bileşen | Neden |
   |---|---|
   | MSVC v143 x64/x86 derleyici araç seti | Rust'un `x86_64-pc-windows-msvc` hedefi |
   | Windows 10/11 SDK | Bağlantı kütüphaneleri |
   | C++ CMake tools for Windows | `flutter_webrtc`'in `libwebrtc`'i indirip derlemesi |

### Neden zorunlu — belirti değil, sebep

`crates/mkvi_core/Cargo.toml` içinde `rusqlite = { features = ["bundled"] }`.
`bundled`, SQLite'i sistem kütüphanesi olarak değil **kaynaktan derler**;
yani C++ derleyici olmadan `cargo test` derlenmez. Hata genellikle
`link.exe not found` ya da `cl.exe` bulunamadı şeklindedir.

Eğer C++ iş yükü kurulu ama hâlâ `cl` bulunamıyorsa: terminali kapatıp
**"Developer PowerShell for VS"** yerine normal PowerShell açın (araç zinciri
kendi hâlinde `cl`'i PATH'e eklemez, ama CMake `cl`'i Visual Studio kurulum
klasöründen bulur) ve `.\tool.ps1 gate`'i tekrar koşturun.

---

## 4. Node.js — yalnız Worker için

```powershell
winget install OpenJS.NodeJS.LTS
```

Bunu **yalnız** `cloudflare/` Worker'ını çalıştırmak istiyorsanız kurmanız
gerekir. Uygulamayı derlemek ve test etmek için gerekmez.

```powershell
node --version
```

Beklenen: **22 veya üzeri.** Depo 22'yi belgeler (`cloudflare/README.md`) ama
`package.json` bir `engines` alanı tanımlamaz, yani sürüm zorlanmaz;
`winget`'in verdiği güncel LTS de sorunsuzdur.

---

## 5. Depoyu al ve bağımlılıkları kur

```powershell
cd $env:USERPROFILE\Documents
git clone https://github.com/ancapenguin/mkvi.git
cd mkvi

# Rust
cd crates\mkvi_core;   cargo build;  cd ..\..
cd crates\mkvi_bridge; cargo build;  cd ..\..
cd app;                flutter pub get;  cd ..
cd design;             dart pub get;  cd ..
cd cloudflare;         npm install;  cd ..
```

Not: `cd ..\..` Windows CMD'de iki seviye atlar, PowerShell'de de aynı. Ama
`cd` zincirlemesi yerine **her komutu kendi `workdir`'inde** çalıştırmak daha
az hata verir.

### Beklenen çıktı ve olası hatalar

| Belirti | Sebep | Çözüm |
|---|---|---|
| `flutter pub get` sonunda `mkvi_design` için hata | `design/` paketinin `pubspec.yaml`'ı okunamıyor | `cd design; dart pub get` önce çalıştırın; `mkvi_design` **yol bağımlılığıdır** |
| `cargo build` sırasında `error: linking with 'link.exe' failed` | C++ araç zinciri yok (bkz. §3) | Build Tools'u C++ iş yüküyle kurun |
| `cargo build` çok uzun sürüyor (dakikalar) | `libsqlite3-sys` SQLite'i kaynaktan derliyor | Normal. İlk derlemeden sonra önbelleğe girer |
| `npm install` uyarı basıyor | Denetim uyarısı | **Engelleyici değildir.** `npm audit` kapının parçası değildir |

---

## 6. Kapıyı koştur — en önemli adım

```powershell
.\tool.ps1 gate
```

Bu, "doğru kurdum mu" sorusunun tek cevabıdır. Kapı sırasıyla koşar:
sürüm kaynakları · `mkvi_core` · `mkvi_bridge` · Worker dry-run + `vitest` ·
`design` analyze + kontrast · `flutter analyze` + `flutter test` · kodlama
denetimi.

### Çıktıyı nasıl okumalı

Sonunda tek bir özet satırı gelir:

```text
============================================================
KAPI YESIL: <geçen adım> gecti, <atlanan adım> atlandi
============================================================
```

- **`KAPI YESIL`** → kurulumun tamam. Devam edebilirsiniz.
- **`KAPI KIRMIZI`** → kırmızı satırların hangi adım olduğu yazıyordur. Tek tek
  koşmak isterseniz §7'deki tablo.
- **`ATLANDI` (sarı)** → o bileşen depoda yok ya da kurulmamış. **`ATLANDI`,
  `GECTI` değildir.** Hangi adımın atlandığını okuyun.

> İlk koşuda Rust tarafı uzun sürecek ve RAM yoğundur. Ağır derlemeden önce
> `.\tool.ps1 resources` ile sisteminizi ölçebilirsiniz; yetersizse uyarır.
> "Kaynak yetersiz" ile "kod bozuk" kapıda karışmasın diye bu ölçüm başta yapılır.

---

## 7. Tek tek adımları koşturmak

```powershell
cd app;                   flutter analyze;  flutter test
cd crates\mkvi_core;      cargo test
cd crates\mkvi_bridge;    cargo test
cd design;                dart analyze;  dart test
cd cloudflare;            npm run check;  npx vitest run
```

> **`dart test` `app/` içinde çalışmaz.** `app` bir Flutter paketidir ve
> `package:test` bağımlılık grafiğinde yoktur; orada `flutter test` kullanılır.
> `design/` Flutter'a bağımlı olmadığı için `dart test` ile kontrast testlerini
> koşar — araç zinciri gereksinimi bu yüzden düşüktür.

Release derlemesi:

```powershell
.\tool.ps1 build          # flutter build windows --release
```

---

## 8. Rust köprüsünün gerçek gidiş-dönüşü

`crates/mkvi_bridge` Dart'tan FFI üzerinden Rust'a gider. Bunu tek başına
doğrulayan bir betik var:

```powershell
cd crates\mkvi_bridge
cargo build --release
cd dart
dart pub get
dart run bin/round_trip.dart
```

Beklenen: betik Rust çekirdeği açar, bir cihaz kimliği üretir ve bir değer
bastırır.

> ⚠️ **Bu betik gerçek bir cihaz kimliği üretir.** Windows Credential Manager'a
> `app.mkvi.desktop` altında `device-signing-key-v1` ve `history-key-v1`
> kayıtlarını yazar. Silmeyin: silmek kayıtlı bir eşi öksüz bırakmanın ta kendisi.

---

## 9. Kendi sinyal sunucunu kur

Uygulamanın **Ayarlar → Bağlantı → Sinyal sunucusu** değeri **varsayılan olarak
boştur** ve MKVI hiçbir sunucuyu gömmez. Gerekçe: `README.md` →
"Kendi sinyal sunucunu kur" (ücretsiz katmanda ~115 GB-s / eşleşme, ~110
eşleşme/gün).

Tam talimat: [`cloudflare/README.md`](../cloudflare/README.md). Özet:

```powershell
cd cloudflare
npm install
npx wrangler login
npx wrangler deploy
```

### Doğrulama

```powershell
curl.exe https://<deploy-çıktısındaki-adres>/health
```

Beklenen yanıt:

```json
{"ok":true,"service":"mkvi-signal"}
```

Bu uç nokta kimlik doğrulaması istemez ve WebSocket gerektirmez; yani
çalışıyor mu sorusunu bir tarayıcı açmadan cevaplar.

### Olmayan bir Worker'la ne olur

Sunucu adresi boşsa ya da yanlışsa uygulama Türkçe bir sebeple bağlanmayı
reddeder (`Bağlantı` bölümündeki `Sinyal sunucusu` alanının altında yazar).
Ham bir ağ hatası görmezsiniz; reddedilen her adresin kendi Türkçe gerekçesi
vardır. Bu bilinçli bir tasarımdır: "neden bağlanmıyor" sorusunun cevabı alanın
hemen altında durmalıdır.

### Yerel Worker ile çalışmak

```powershell
cd cloudflare; npm run dev     # ws://localhost:8787
```

Uygulamaya `ws://localhost:8787` yazabilirsiniz.

---

## 10. Uygulamayı çalıştır

```powershell
cd app
flutter run -d windows
```

**Şu anda açılacak olan şey:** Flutter'ın örnek **sayaç** uygulaması. Çünkü
`app/lib/main.dart` (122 satır) `flutter create` şablonudur ve
`title: 'Flutter Demo'` yazar. Bu bir hata değil, `ROADMAP.md`'deki
**"hiçbir ekran yok"** maddesinin ta kendisidir: on katman yazılı ama
birbirine bağlanmamış.

Yine de derleme zincirinin tamamı burada çalışır — Flutter, `flutter_webrtc`
plugin'i, Windows runner'ı, CMake. Bu adım başarısız olursa sorun
`flutter_webrtc` ya da Windows araç zincirindedir; §3'e dönün.

### Yayın modunda çalıştırmak

```powershell
cd app; flutter run -d windows --release
```

---

## 11. Sık karşılaşılan sorunlar

| Belirti | Sebep | Çözüm |
|---|---|---|
| `flutter: not recognized` | PATH yeni kuruldu, terminal eski | PowerShell'i kapatıp yeniden açın |
| `flutter doctor` → "Android toolchain" kırmızı | Android fazı henüz yok | **Yoksayın.** MKVI şu anda Android'de derlenmiyor |
| `link.exe not found` | C++ build araçları yok | §3 |
| `cargo test` çok uzun sürüyor | `bundled` SQLite kaynaktan derleniyor | Normal; ilk derlemeden sonra hızlanır |
| `dart test` "No test file was found" / `package:test` yok | `app/` içinde çalıştırdınız | `app/` için `flutter test` kullanın |
| `design/` kontrast testi kırmızı | `tokens.json` ile `tokens.g.dart` ayrışmış | `cd design; dart run tool/generate_tokens.dart` sonra testi tekrar koşturun |
| Kodlama denetimi "BOM" kırmızı | Bir dosyaya BOM yazıldı | §Kural 2 (`CONTRIBUTING.md`); BOM'u kaldırın |
| Kodlama denetimi "bozuk metin" kırmızı | Türkçe bir kez bozuk kodlamadan geçmiş | Dosyayı UTF-8 (BOM'suz) olarak yeniden kaydedin |
| Kimlik hatası: `KeyringEntryMissing` | Güvenli depoda kayıt yok ama diskte veri var | **Yeni anahtar üretmeyin.** Bu kasıtlı bir hatadır; ayrıntı `SECURITY.md` |
| `curl` yok | Windows'ta `curl` PowerShell takma adı olabilir | `curl.exe` kullanın |
| Kapı "ATLANDI" diyor | `cloudflare/node_modules` yok | `cd cloudflare; npm install` |

---

## 12. Sonra ne?

| Ne | Nerede |
|---|---|
| Uygulamayı kullanma (bir gün) | [`docs/manual-test.md`](manual-test.md) |
| Katkı vermeye hazırlanmak | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |
| Güvenlik açığı bildirmek | [`SECURITY.md`](../SECURITY.md) |
| Mimariyi anlamak | [`ARCHITECTURE.md`](../ARCHITECTURE.md) |
| Sıradaki iş | `ROADMAP.md` → işaretlenmemiş ilk kutu |

Kurulumda takıldığınız bir yer varsa **issue açın** — hatayı değil, denediğiniz
komutu ve çıktısını yazın. Topluluk kuralları: `CODE_OF_CONDUCT.md`.
