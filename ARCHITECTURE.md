# MKVI mimarisi

Bu dosya **yol haritası değildir** — plan `ROADMAP.md`'dedir, kararlar `docs/adr/`'dededir.
Burada yalnızca sistem nasıl kuruluyor ve hangi sınır neden var.

## Karar

Uygulama **Flutter** ile yazılıyor; taşıma `flutter_webrtc` üzerinden platform-native
WebRTC'dir (Windows'ta MF/WASAPI/DXGI). Rust çekirdek korunur ve Tauri'den tamamen
ayrılmıştır. Kararın gerekçesi, kanıtı ve riskleri: `docs/adr/0001-flutter-migration.md`.

Sinyalleşme sunucusu değişmedi: `cloudflare/` içindeki Worker iki Durable Object'tir ve
MKVI'nin sadece eşler arasında konuşma yolunu taşır.

## Katmanlar

```text
app/                        Flutter uygulaması
  lib/core/protocol/          tel protokolü: kontrol mesajları, dosya çerçevesi, temizleyiciler
  lib/signaling/              rendezvous istemcisi, payload beyaz listesi, eşleştirme kodu
  lib/session/                kurulum durumu, geri bağlanma döngüsü, isimler
  lib/call/                   çağrı durum makinesi (WebRTC'siz, donanımsız test edilebilir)
  lib/chat/                   mesaj zaman çizelgesi, dosya aktarımı koordinasyonu
  lib/media/                  üç transceiver, replaceTrack, cihaz hatalarının Türkçeleştirilmesi
  lib/settings/               görünüm ve bağlantı ayarları
  lib/update/                 güncelleme: feed oku, indir, doğrula, kur
crates/mkvi_core/            Tauri bilmez: Ed25519, keyring, şifreli SQLite, dosya yazımı
crates/mkvi_bridge/          flutter_rust_bridge yüzeyi — Dart'ın Rust'a giden tek kapısı
cloudflare/                  sinyal sunucusu (AGPL-3.0, dokunulmaz)
design/                      tasarımın tek kaynağı: tokens.json + kontrast testi
vectors/                     TypeScript ve Dart'ın ortak sözleşmesi (wire-v1.json)
spike/                       Hafta 0 go/no-go probu — yalnız README.md
```

**Katman kuralı:** Dart, Rust'a yalnızca `mkvi_bridge` üzerinden dokunur. `mkvi_core`
Flutter'ı ve Tauri'yi bilmez. `cloudflare/` hiçbir şeyi bilmez.

`src/`, `src-tauri/` ve kökteki `package.json`/`vite.config.ts` 0.1.x **donmuş** Tauri
hattıdır. Dart portunun spesifikasyon kaynağıdır; Flutter 0.2.0 yayınlandıktan sonra
tek commit'te silinir.

## Güvenlik sınırları

```text
MKVI cihaz A  -- DTLS/SRTP + DataChannel -->  MKVI cihaz B
     |                                                  |
     +------ WSS: yalnızca identity / offer / answer / ICE ---+
                       Cloudflare Worker + Durable Object
```

- **Sunucu içerik taşımaz.** `isSignalPayload` anahtar bazında beyaz listedir; içerik
  alanı eklemek Worker'ı içerik tüneline çevirir. Protokolü daraltmak kırıcıdır: alanı
  çıkarmak, o alanı hâlâ gönderen eski istemcileri düşürür.
- **Cihaz kimliği Ed25519**; özel anahtar işletim sistemi kasasında (Windows DPAPI,
  macOS Keychain). **Özel kripto yazılmaz** — yalnız denetimli crate'ler.
- **Sessiz sır üretimi yasaktır.** Keyring'de kayıt yoksa ama diskte bir şey varsa
  yeni anahtar üretilmez; `KeyringEntryMissing` hatası verilir. Yazma sonrası okuma
  doğrulanır, çünkü `keyring` 3 arka ucsuz kaldığında bellek içi mock'a düşüyor.
  Android'de `keyring` **yoktur**; Android'de platform kasasından beslenen bir
  `SecretStore` uygulaması gerekir.
- **Yerel geçmiş** XChaCha20-Poly1305 ile şifrelenir; anahtar kasada durur. Satır
  sırası ve zaman damgaları düz metindir (SQLCipher Faz 4'e bırakıldı).
- **Dart ham anahtarı asla görmez**; imzalama ve çözme çekirdektedir.
- **Bilinen açık (kapatılıyor):** SAS ifadesi şu an yalnız eşleştirme kodu + anahtarların
  özetidir. Sinyal sunucusunu kontrol eden biri iki tarafa da aynı ifadeyi gösterebilir.
  DTLS parmak izi eklenerek kapatılacak (`ROADMAP.md` Faz 4).
- **Bilinen açık (kapatıldı):** yayın anahtarı minisign'in eski `Ed` biçiminde;
  katı doğrulayıcı her imzayı reddederdi. Artık bu durum `LegacyKey` hatası olarak
  **adıyla** bildiriliyor; kök çözüm ilk Flutter sürümünden önce prehashed anahtar
  üretmek.

## Neden bu ayrımlar

| Sınır | Kötüye kullanıldığında |
|---|---|
| Worker beyaz listesi | Sunucu içerik taşıyıcısına dönüşür |
| Anahtar kasada | Cihaz çalınırsa geçmiş okunur |
| Doğrulama Rust'ta | Kötüye güncellenmiş bir build imza kontrolünden geçer |
| Tasarım kontrast testi | Okunmayan arayüz geri gelir (0.1.x'te 17 ihlal vardı) |
| `vectors/wire-v1.json` | İki uygulama sessizce ayrışır (0.1.x'te base64 ve UUID hatası böyle çıktı) |

## Çalıştırma

```powershell
.\tool.ps1 gate      # tüm doğrulamalar: tsc, vitest, cargo, wrangler, flutter, kontrast, kodlama
.\tool.ps1 resources # sadece kaynak ölçümü (ağır derlemeden önce)
```

Uygulama: `cd app; flutter run -d windows`. Worker: `cd cloudflare; npm install;
npx wrangler deploy` — dağıtılan adresi uygulamanın ayarlarına yazarsın; MKVI hiçbir
sunucuyu gömmez.
