# MKVI

Hesapsız, iki kişi arasında doğrudan (P2P) iletişim uygulaması. İçerik bir sunucudan
geçmez; sunucu yalnızca iki cihazın birbirini bulmasına yardım eder.

## Durum

**Bu dal Flutter portasıdır ve tamamlanmamıştır.** Yayımlanmış, çalışan sürüm
**0.1.x**'tir ve donmuş bir Tauri hattı olarak `src/` ile `src-tauri/` altında durur;
0.2.0 yayınlandıktan sonra silinecektir. Bu dalda Rust çekirdek, tel protokolü,
sinyalleşme, tasarım sistemi ve tüm iş mantığı hazır; geriye arayüz ve derleme
paketingi var. Aşağıdaki özellik listesi **0.1.x sürümünü** anlatır.

## 0.1.x özellikleri

- Süreli kısa kodla eşleştirme, karşılıklı doğrulama ifadesi onayı ve sonrasında
  otomatik yeniden bağlanma.
- Cloudflare Worker + Durable Object ile yalnızca signaling/rendezvous.
- WebRTC DataChannel ile P2P mesajlaşma ve kabul-onaylı dosya aktarımı.
- Cihaz kimliği: Ed25519 anahtarı işletim sistemi güvenli deposunda.
- Yerel geçmiş: XChaCha20-Poly1305 ile şifrelenmiş SQLite.
- Türkçe arayüz; sesli/görüntülü arama ve ekran paylaşımı girişimi.

## Güvenlik modeli

- **Sunucu içerik taşımaz.** Worker yalnızca kısa eşleştirme kanalını, online durumunu
  ve SDP/ICE/kimlik zarflarını iletir. Zarf içeriği anahtar bazında beyaz listeyle
  sınırlıdır. Mesaj, dosya ve medya doğrudan P2P bağlantısından akar.
- **Cihaz kimliği** Ed25519 ile; özel anahtar cihazın güvenli deposunda durur ve uygulama
  arayüzüne çıkmaz.
- **Yerel geçmiş** uygulama katmanında şifrelenir; anahtar kasada tutulur.
- **Özel kripto yazılmaz**; yalnız denetimli kütüphaneler kullanılır.

### Bilinen sınırlar

- **İfadenin kapsamı dar.** Karşılaştırma ifadesi şu an eşleştirme kodu ile cihaz
  anahtarlarının özetinden türetiliyor; DTLS parmak izine bağlanmadığı için sinyal
  sunucusunu kontrol eden biri iki tarafa da aynı ifadeyi gösterebilir. Bu, kapatılmak
  üzere olan bir açıktır ve `ROADMAP.md` Faz 4'te izleniyor.
- **Windows kurulum dosyası imzasızdır**, bu yüzden SmartScreen uyarısı çıkar.
- **Yalnız Windows.** Diğer platformlar yol haritasında, henüz yayımlanmış değil.
- Eşleştirme kodu tek kullanımlık değildir: bir oda en çok 8 kabul alır ve 15 dakika
  kayan pencere olarak işler. Bu, kısa kodun tahmin edilemez olmasını sağlar, tek
  kullanımlılığı değil.

## Gereksinimler

- [Node.js](https://nodejs.org) 22
- [Rust](https://rustup.rs) (stable)
- [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/) —
  **C++ iş yükü şart**, çünkü `rusqlite` SQLite'i kaynaktan derler
- [Flutter](https://docs.flutter.dev/get-started/install) 3.44 veya üzeri

## Çalıştırma

Uygulama:

```powershell
cd app
flutter pub get
flutter run -d windows
```

Sinyal sunucusu — **MKVI hiçbir sunucuyu gömmez**, kendi sunucunu kurarsın:

```powershell
cd cloudflare
npm install
npx wrangler login
npx wrangler deploy
```

Dağıtılan `*.workers.dev` adresini uygulamanın **Ayarlar → Gelişmiş bağlantı
ayarları** ekranına yaz. Ayrıntılar: `cloudflare/README.md`.

## Doğrulama

Tüm kontroller tek komutta:

```powershell
.\tool.ps1 gate
```

Bu sırasıyla `tsc`, `vitest`, iki ayrı `cargo test`, `wrangler deploy --dry-run`,
`flutter analyze`, `flutter test`, tasarım kontrast testi ve bir kodlama denetimi
(BOM, bozuk Türkçe metin, ham NUL baytı) çalıştırır; ayrıca sistem kaynaklarını ölçer.
Ağır derleme öncesi sadece kaynakları görmek için `.\tool.ps1 resources`.

## Depo düzeni

| Yol | Ne |
|---|---|
| `app/` | Flutter uygulaması |
| `crates/mkvi_core/` | Tauri'den bağımsız Rust çekirdek |
| `crates/mkvi_bridge/` | Dart'ın Rust'a giden tek kapısı |
| `cloudflare/` | sinyal sunucusu |
| `design/` | tasarımın tek kaynağı ve kontrast testi |
| `vectors/` | TypeScript ve Dart'ın ortak sözleşmesi |
| `src/`, `src-tauri/` | donmuş 0.1.x hattı |
| `docs/adr/` | mimari kararlar |

Mimari: `ARCHITECTURE.md` · Plan: `ROADMAP.md` · Kararlar: `docs/adr/`

## Lisans

- Uygulama (`app/`, `crates/`): **Apache-2.0 OR MIT** — bkz. `LICENSE-APACHE`, `LICENSE-MIT`
- Sinyal sunucusu (`cloudflare/`): **AGPL-3.0** — bkz. `cloudflare/LICENSE`

Sinyal sunucusunun ayrı ve daha güçlü lisanslı olması bilinçlidir: MKVI'nin bedava bir
kamu hizmeti olarak çalıştırılıp satılmasını engeller; kendi sunucunu kurup
kaynaklarını kullanmak serbesttir.
