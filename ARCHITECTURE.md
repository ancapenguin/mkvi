# MKVI mimarisi

Bu dosya **yol haritası değildir** — plan `ROADMAP.md`'dedir, kararlar
`docs/adr/`'dededir. Burada yalnızca sistem nasıl kuruluyor ve hangi sınır neden
var.

## Karar

Uygulama **Flutter** ile yazılıyor; taşıma `flutter_webrtc` üzerinden
platform-native WebRTC'dir (Windows'ta MF/WASAPI/DXGI). Rust çekirdek korunur ve
arayüz kabuğundan tamamen ayrılmıştır. Kararın gerekçesi, kanıtı ve riskleri:
`docs/adr/0001-flutter-migration.md`.

Sinyalleşme sunucusu değişmedi: `cloudflare/` içindeki Worker iki Durable Object'tir
ve MKVI'nin yalnızca eşler arasında konuşma yolunu taşır.

## Katmanlar

```text
app/                        Flutter uygulaması
  lib/core/protocol/          tel protokolü: kontrol mesajları, dosya çerçevesi, temizleyiciler
  lib/signaling/              rendezvous istemcisi, payload beyaz listesi, eşleştirme kodu
  lib/session/                kurulum durumu, geri bağlanma döngüsü, kimlik, isimler
  lib/call/                   çağrı durum makinesi (WebRTC'siz, donanımsız test edilebilir)
  lib/chat/                   mesaj zaman çizelgesi, dosya aktarımı koordinasyonu
  lib/media/                  üç transceiver, replaceTrack, cihaz hatalarının Türkçeleştirilmesi
  lib/settings/               görünüm ve bağlantı ayarları, token çözümleme
  lib/update/                 güncelleme: feed oku, indir, doğrula, kur
  lib/ui/                     ekranlar (pairing, workspace, call, settings), widget'lar, bildirim
crates/mkvi_core/            Flutter bilmez: Ed25519, keyring, şifreli SQLite, dosya yazımı
crates/mkvi_bridge/          flutter_rust_bridge yüzeyi — Dart'ın Rust'a giden tek kapısı
cloudflare/                  sinyal sunucusu (AGPL-3.0)
design/                      tasarımın tek kaynağı: tokens.json + generator + kontrast testi
vectors/                     ortak tel sözleşmesi (wire-v1.json) — Dart ve TypeScript bunu okur
docs/adr/                    mimari kararlar
```

**Katman kuralı:** Dart, Rust'a **yalnızca** `mkvi_bridge` üzerinden dokunur.
`mkvi_core` Flutter'ı bilmez. `cloudflare/` hiçbir şeyi bilmez.

`app/lib/` altındaki her katman bir **barrel** dosyasıyla kapanır
(`signaling.dart`, `session.dart`, `call.dart`, `chat.dart`, `media.dart`,
`settings.dart`, `update.dart`, `core/protocol/protocol.dart`, `ui/notice/notice.dart`).
Bir katmanı tek satırda içe aktarmak için o barrel'i kullanın; alt dosyalar tek
tek de içe aktarılabilir durumda bırakılır.

### İki Rust paketi, neden workspace değil

`mkvi_core` ve `mkvi_bridge` bilinçli olarak **iki ayrı pakettir.** Çekirdek
tek başına derlenebilmelidir; Flutter kabuğu onu yalnızca köprü üzerinden çağırır.
Bedeli: iki ayrı `Cargo.lock` ve iki ayrı bağımlılık grafiği — ikisi de
`THIRD-PARTY-NOTICES.md`'de ayrı ayrı listelenmiştir. Kapı her ikisinin testini
de koşar.

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
  macOS Keychain, Linux Secret Service). **Özel kripto yazılmaz** — yalnız denetimli
  crate'ler.
- **Sessiz sır üretimi yasaktır.** Keyring'de kayıt yoksa ama diskte bir şey varsa
  yeni anahtar üretilmez; `KeyringEntryMissing` hatası verilir. Yazma sonrası okuma
  doğrulanır, çünkü `keyring` 3 arka ucuz kaldığında bellek içi mock'a düşüyor.
  **Android'de `keyring` yoktur**; Android'de platform kasasından beslenen bir
  `SecretStore` uygulaması gerekir. Bu yüzden `mkvi_core` bugün Android hedefi
  derlenmez.
- **Yerel geçmiş** XChaCha20-Poly1305 ile şifrelenir; anahtar kasada durur. Satır
  sırası ve zaman damgaları düz metindir, ve SQLite'ın WAL/journal sayfaları bu
  şifrelemenin dışındadır (SQLCipher Faz 4'e bırakıldı).
- **Dart ham anahtarı asla görmez**; imzalama ve çözme çekirdektedir.
- **Bilinen açık (kapatılıyor):** SAS ifadesi DTLS sertifika parmak izine
  **bağlanmadı** — 0.2.0'da henüz hiç bağlanmadı. Sinyal sunucusunu kontrol eden
  biri iki tarafa da aynı ifadeyi gösterebilir. `SECURITY.md` §"DTLS parmak izi
  doğrulaması" ve `ROADMAP.md` Faz 4.
- **Bilinen açık (kapatıldı):** yayın anahtarı minisign'in eski `Ed` biçiminde;
  katı doğrulayıcı her imzayı reddederdi. Artık bu durum `LegacyKey` hatası olarak
  **adıyla** bildiriliyor; kök çözüm ilk Flutter sürümünden önce prehashed anahtar
  üretmek.
- **Gömülü sunucu yok.** `ConnectionSettings` varsayılan olarak boştur ve boş bir
  adresi bir kullanıcı girdisi olarak reddeder. Bkz. `cloudflare/README.md` §4.

## Neden bu ayrımlar

| Sınır | Kötüye kullanıldığında |
|---|---|
| Worker beyaz listesi | Sunucu içerik taşıyıcısına dönüşür |
| Anahtar kasada | Cihaz çalınırsa geçmiş okunur |
| Doğrulama Rust'ta | Kötüye güncellenmiş bir build imza kontrolünden geçer |
| Tasarım kontrast testi | Okunmayan arayüz geri gelir (0.1.x'te 17 ihlal vardı) |
| `vectors/wire-v1.json` | İki uygulama sessizce ayrışır (0.1.x'te base64 ve UUID hatası böyle çıktı) |
| Her katmanın saf olması | Donanımsız test yazılamaz; iki cihaz gerekmeden doğrulanamaz |

## Çalıştırma

```powershell
.\tool.ps1 gate      # tüm doğrulamalar: sürüm, cargo, wrangler, flutter, dart, kontrast, kodlama
.\tool.ps1 resources # sadece kaynak ölçümü (ağır derlemeden önce)
```

Uygulama: `cd app; flutter run -d windows`. Worker: `cd cloudflare; npm install;
npx wrangler deploy` — dağıtılan adresi uygulamanın **Ayarlar → Bağlantı → Sinyal
sunucusu** alanına yazarsın; MKVI hiçbir sunucuyu gömmez.

Sıfırdan kurulum: `docs/getting-started.md`. İki cihazla elle test:
`docs/manual-test.md`.

## Emekliye ayrılan hat

0.1.x Tauri hattı (`src/`, `src-tauri/`, kök `package.json`, `vite.config.ts`,
`tsconfig*.json`) **2026-09-26'da emekliye ayrıldı ve depodan silindi.** Bu
belgede o hat bir mimari katman olarak sayılmaz.

O hattın ne olduğu, neyi kanıtladığı ve o kanıtın nereye taşındığı tek bir kayıtta
duruyor: [`docs/legacy-tauri-line.md`](docs/legacy-tauri-line.md). Bu bir kullanım
kılavuzu değil, bir **miras kaydıdır** — oradaki hiçbir şeyi geri getirmeye,
taşımaya ya da 0.1.x'i çalıştırmaya çalışmayın.

Silinen hat **Rust çekirdeği vurmadı.** `mkvi_core` o zaman Tauri'ye bağımlı
değildi ve bugün `crates/mkvi_core` olarak duruyor; kaybedilen yalnızca kabuk ve
arayüzdü.
