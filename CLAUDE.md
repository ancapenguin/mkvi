<!-- GENERATED FILE - DO NOT EDIT. Source of truth: AGENTS.md -->
<!-- Regenerate with: .\tool.ps1 docs -->
# MKVI — proje kılavuzu

> **Bu dosya tek yazılı kaynaktır.** `CLAUDE.md` bu dosyadan **türetilir** ve
> elle düzenlenmemelidir; `.\tool.ps1 docs` her ikisini de üretir.
>
> Neden iki dosya değil: iki yazılı kaynak bir gün ayrışır, ve ayrışma sessiz
> olur. 0.1.x döneminde tam olarak bu oldu — `CLAUDE.md` git'e hiç girmiyordu
> (`.gitignore`'daydı), yani public depoda **kimse** güncel talimatları göremezdi.
> Ders kayda değer: bir kılavuz izlenmiyorsa yoktur.

Hesapsız, iki cihaz arasında doğrudan (P2P) kişisel iletişim uygulaması.
**Flutter + Rust.** Arayüz dili **Türkçe**, kod yorumları **İngilizce**.

> **0.1.x Tauri hattı 2026-09-26'da emekliye ayrıldı ve silindi.** `src/`,
> `src-tauri/`, `spike/` ve kök Vite/TypeScript yapılandırması artık yok. Bu
> dosyada kalan 0.1.x referansları **tarihsel kayıttır**, kullanım kılavuzu
> değildir. Kararın tamamı: `ROADMAP.md` → "0.1.x Tauri hattı emekliye ayrıldı".

## Komutlar

```powershell
.\tool.ps1 gate           # TAM KAPI — commit'ten önce bu yeşil olmalı
.\tool.ps1 gate-quick     # yalnız analiz (hızlı döngü)
.\tool.ps1 build          # uygulamanın release derlemesi
.\tool.ps1 version        # sürüm kaynaklarını karşılaştırır
.\tool.ps1 docs           # CLAUDE.md aynasını yeniden üretir

cd app; flutter test      # Dart tarafı (birim + widget)
cd app; flutter run       # geliştirme
cd crates\mkvi_core;  cargo test   # Rust çekirdek
cd crates\mkvi_bridge; cargo test  # Dart köprüsü
cd design; dart test      # kontrast kapısı (816 ölçülmüş oran)
cd cloudflare; npm run check      # wrangler deploy --dry-run
```

**Tam gate** — `.\tool.ps1 gate` şunları koşar ve **hepsi yeşil olmalı**:
sürüm tutarlılığı · `mkvi_core` · `mkvi_bridge` · Worker dry-run + vitest ·
`design` analyze + kontrast · `flutter analyze` + `flutter test` · kodlama denetimi.

## Mimari harita

| Katman | Yer | Sorumluluk |
|---|---|---|
| Arayüz | `app/lib/ui/` | Eşleştirme, çalışma alanı, arama, ayarlar; hepsi `AppearanceStyle`'tan boyar |
| Oturum | `app/lib/session/` | Açılış durumu, yeniden bağlanma döngüsü, eş adları |
| Sohbet | `app/lib/chat/` | Mesaj kuyruğu, şifreli geçmiş, dosya aktarımı |
| Arama | `app/lib/call/` | Çağrı durum makinesi (saf Dart, donanımsız testli) |
| Medya | `app/lib/media/` | Kamera/mikrofon/ekran, ilk kare watchdog'u |
| Sinyalleşme | `app/lib/signaling/` + `cloudflare/src/index.ts` | Rendezvous istemcisi + 2 Durable Object (`PairingRoom` 15 dk, `PeerRendezvous` 30 gün) |
| Protokol | `app/lib/core/protocol/` | Tel üstü çerçeveler, `vectors/wire-v1.json` ile sözleşmelenmiş |
| Güncelleme | `app/lib/update/` | Feed okuma, imza doğrulama (Rust'ta), kurulum |
| Tasarım | `design/` | `tokens.json` → generator → `tokens.g.dart`; **tek kaynak** |
| Rust çekirdek | `crates/mkvi_core/` | Ed25519 kimlik (keyring/DPAPI), XChaCha20-Poly1305'li SQLite, dosya yazma, imza doğrulama |
| Köprü | `crates/mkvi_bridge/` | `flutter_rust_bridge` yüzeyi — Dart'ın Rust'a **tek** yolu |

Detaylı mimari: `ARCHITECTURE.md`. **Bitirme planı, verilmiş kararlar ve çalışma
kuralları: `ROADMAP.md` — işaretlenmemiş ilk kutu sıradaki iştir.**
**İki cihazlı el testi prosedürü: `docs/manual-test.md`.**

## Değişmez kurallar

- **Özel kripto yazma.** Yalnız denetimli crate'ler (`ed25519-dalek`,
  `chacha20poly1305`). Yeni bir şifreleme şeması gerekiyorsa önce sor.

- **Tekerleği yeniden icat etme — yeterince iyi bir kütüphane varsa al.**
  Bu, kriptografi kuralının **genel halidir** ve ikisi birbirine ayrılmaz.
  DTLS'yi, ICE'yi, DTLS-SRTP'yi, bir dosya biçimini, bir sıkıştırma algoritmasını
  veya bir veritabanı motorunu **kendi başımıza yazmayız.** El yazımı bir şey
  ancak o şey gerçekten sıfırdan bizim işimizse ve dışarıda olgun bir karşılığı
  yoksa kabul edilir.

  **Her yeni bağımlılık dört sorudan geçer ve gerekçesi yazılır:**
  1. Bu işi yapıyor mu, yoksa sadece isim mi benzer?
  2. Bakımı kim yapıyor, son sürümü ne zaman, kaç indirme/gün?
  3. Denetim/lisans durumu ne? (Rust için `cargo deny`/`cargo audit` mantığı,
     Dart için `pub.dev` puanı)
  4. Doğru mu bildiğimiz? **Gerekçesiz bağımlılık ekleme.**

  Somut olarak: WebRTC için `flutter_webrtc`, Rust'ta kripto için `ed25519-dalek`
  / `chacha20poly1305` / `minisign-verify`, veritabanı için `rusqlite`, anahtar
  kasası için `keyring`. Bunlar **zaten** projede ve değiştirilmiyor.

- **Yalnız kendi işimiz olan katmanda el yaz.** Sinyalleşme protokolü, eşleştirme
  akışı, çağrı durum makinesi, arayüz durumu — bunlar bizim. Altında yatan
  taşıma/kripto/veri katmanları **değil.**
- **Worker içerik taşımaz.** `cloudflare/src/index.ts` içindeki `isSignalPayload`
  anahtar bazında beyaz liste kullanır. Buraya yeni alan eklemek Worker'ı içerik
  tüneline çevirme riskidir — gerekçesiz genişletme.
- **Protokol daraltmak kırıcıdır.** `isSignalPayload`'dan bir alan çıkarmak, o
  alanı hâlâ gönderen istemcileri `close(1008)` ile düşürür. Çıkarmadan önce repo
  genelinde o alanın gönderildiği yer olmadığını kanıtla.
- **Varsayılan sunucu gömülmez.** Herkes kendi Worker'ını kurar. Gerekçe:
  ücretsiz katmanda bir eşleşme ~115 GB-s DO süresi tüketiyor (~110 eşleşme/gün),
  sonrası herkes için ölü. MKVI kimseye hizmet vermez.
- **Türkçe stringler UTF-8, BOM'suz.** Bu dosyalar bir kez mojibake'e uğradı.
  Türkçe metin içeren bir dosyayı düzenledikten sonra BOM denetimini çalıştır;
  çıktı boş olmalı. `.\tool.ps1 gate` bunu zaten yapar.
- **Dosya içeriğini PowerShell ile ASLA yazma.** `Get-Content -Raw` Türkçeyi
  bozar, `Set-Content -Encoding utf8` BOM yazar. Edit/write aracını kullan.
- **Kod yorumları İngilizce**, kullanıcıya görünen her string Türkçe.
- **Her dosyanın tek sahibi olur.** Ajanlar commit/push atmaz; commit'i lead
  yapar. İki ajan aynı dosyaya yazarsa işi birbirine ezerler.

## Oturum Devir Akışı

1. **Oturum başında:** önce `git status` + `git log --oneline -10`, sonra
   `ROADMAP.md`'yi ve `docs/adr/`'yi oku, işaretlenmemiş ilk kutudan devam et.
   Kullanıcıya "ne yapıyorduk?" diye sorma. Bir kutu bitince `[x]` yap ve altına
   **tek satır kanıt** yaz.
2. **Yeşil checkpoint'te commit ET ve push ET.** `.\tool.ps1 gate` yeşile döndüğünde
   commit at ve `git push` çalıştır. Push için ayrıca izin gerekmez — kullanıcı
   bu kuralı 2026-09-26'da değiştirdi.

   *Sebep:* depo `PRIVATE` olduğu sürece GitHub Actions'ın aylık dakikaları
   tükenir ve CI sessizce koşmaz. Public olduğunda ücretsizdir, yani bu kural
   gerçekten işe yarar. **Kırmızı gate asla push edilmez.**

   *Sır denetimi:* hiçbir anahtar, token veya parola repoya girmiyor. `*.key`,
   `*.key.pub`, `.secrets/` `.gitignore`'dadır. Public öncesi `git log --all`
   üzerinde tarama yapıldı (2026-09-26) ve **temiz** çıktı.
3. **Biten adımın handoff'unu SİL — yeni bloğu üstüne EKLEME.** Handoff
   stack'lemek yasaktır; dosyada her zaman **tek** oturum bloğu bulunur.
4. **Oturum sonunda yeni handoff yaz.** İçinde somut olarak bulunmalı: sıralı
   adımlar · karar noktaları · açık işler · bilinen tuzaklar.
5. **Handoff KENDİNE-YETER olmalı.** Yeni bir oturum sıfır bağlamla açılıp sadece
   "kaldığın yerden devam et" yazdığında ne yapacağını bilmeli. Şunları içermek
   zorunlu: **İLK iş** (tek cümle, emir kipi) · **kusurun tam yeri** (`dosya:satır`) ·
   **hangi tuzağa düşülmemesi gerektiği** · **karar noktaları** (seçenekleriyle).
6. **Boyut sınırı ~250 satır.** Bu dosya her oturumda bağlama yükleniyor; şişerse
   detay ayrı bir plan dosyasına taşınır ve burada sadece pointer kalır.

## Faz özeti

- **0.1.x (0.1.0–0.1.4) yayında.** Tauri 2 + React + TypeScript + Rust. Gerçek
  cihazlarda denendi ve on canlı kusur bulundu; `ROADMAP.md` → "Öğrenilenler"
  tablosu bunları ve her birinin güncel durumunu tutuyor. **Bu hat 2026-09-26'da
  emekliye ayrıldı ve silindi.**
- **0.2.0 — Flutter portu.** On katman yazıldı ve testlendi
  (`app/lib/{core,signaling,session,chat,call,media,settings,update,ui}`), Rust
  çekirdek ve köprü ayrıldı, tasarım tokenları gerçek bir pakete (`design/` →
  `mkvi_design`) taşındı. **Hiçbir ekran yoktu:** `main.dart` Flutter şablonuydu.
  Bu, 0.2.0'un asıl boşluğuydu — on katman yazılı ama hiçbiri birbirine bağlı değil.
- **0.1.x'ten taşınan ve Dart tarafında düzeltilen kusurlar** (tam listesi ve kanıtı
  `ROADMAP.md`'de): `wss:` sessizce `ws:`'ye düşüyordu; geçersiz endpoint
  `connect()`'i senkron `TypeError` ile kaçırıyordu; beyaz ekran yapısal olarak
  imkânsızdı; takma ad gerçek adı ezıyordu; bildirim yazarın üstüne biniyordu;
  kamerasız `getUserMedia` **hatasız** boş `videoTracks` ile "başarılı" dönüyordu
  (sessiz başarısızlık); `stopCall` hiçbir çağrıya ait olmayan rastgele id gönderiyordu.
- **2026-09-26 — altyapı onarımı:** sürüm kapısı **eklendi** (5 kaynak 0.1.4'te
  kalmıştı, yayın yanlış sürümle başlardı); `mkvi_bridge`'ın 15 testi kapıya
  **eklendi** (hiçbir yerde koşmuyordu); `gercek_veri.rs`'e `#[ignore]` **niteliği**
  eklendi (belgelenen komut hiçbir testle eşleşmiyordu); legacy anahtar anlatısı
  **düzeltildi** (ölçüldü: Tauri updater `allow_legacy = true` kullanıyor, 0.1.x'i
  öldüren şey legacy anahtar değil **ölü feed**'di).
- **Faz 8 (ölü kod) 2026-09-26'da tamamlandı.** `src/`, `src-tauri/`, `spike/`, kök
  Vite/TypeScript yapılandırması, `public/`, `dist/` gitti. El testi prosedürü
  `docs/manual-test.md`'ye kurtarıldı, karar kuralı kelimesi kelimesine korundu.

---

## Sıradaki Oturum Planı (handoff — bittiğinde sil)

> ⚠️ **BU BÖLÜM TEK OTURUM BLOĞU İÇERİR. Yeni handoff yazarken eski tarihli bloğu SİL,
> ÜSTÜNE EKLEME. >1 tarihli blok görürsen fazlasını SİL.**

### 2026-09-29

**Bu blok kısadır çünkü plan `ROADMAP.md`'de.** Oturuma şöyle başla: `git status` +
`git log --oneline -10`, sonra **`ROADMAP.md`'yi aç ve işaretlenmemiş ilk kutudan devam et.**

**Depo public oldu (2026-09-29).** Temizlenmiş geçmiş force-push edildi (`243740e`), GitHub'daki
`MKVI 0.1.2` release'ı ve `v0.1.0`–`v0.1.4` tag'leri silindi, uzakta yalnız `main` var. Kapı
push'tan hemen önce yeşildi (14 geçti). `Documents\mkvi` eski geçmişi taşıyan dizin silinip
GitHub'dan temiz klonla değiştirildi; `.secrets/` ve `app/android/local.properties` taşındı.

**İLK İŞ:** `ROADMAP.md` Faz 0.5 → **P0.1 sahiplik tablosu.** `main.dart`'ı bağlamak (P0.9)
**önce yapılmaz**: taşıma ve depolama arayüzlerinin üretim implementasyonu sıfır, kabuk bağlansa
da iki cihaz arasında mesaj gitmez.

**Kullanıcının hedefi (2026-09-29):** GitHub Release'den Windows kurulumu + Android APK alıp
**Windows ↔ Android mesajlaşmayı** denemek; otomatik güncelleme de çalışsın. Bugün engel derleme
değil: mesaj taşıyan kod yok. Sıra: (1) Faz 0.5 (P0.1 → P0.9) · (2) paralel: `release.yml`'e
Android işi (APK, Rust NDK derlemesi, anahtar kasası; ROADMAP Faz 9) · (3) imzalama + `latest.json`
(`release.yml` TODO'ları) · (4) `v0.2.0` tag → iki kurulum dosyası. Tag atmak (4) bunlardan önce
sayaç uygulaması yayınlar, yapılmaz.

**Yedek:** `Documents\mkvi-private-backup-2026-09-26\` — 0.1.x dahil tam geçmiş `git bundle`
(salt-okunur, ASLA üzerine yazma). **Sınır:** GitHub eski commit'leri fork ağında bir süre
tutabilir; "tamamen silindi" denmez, birkaç hafta sonra yeniden ölçülür.

**Doğrulanmamış olanlar (iddia etme):** hiçbir test gerçek kamera/mikrofon/ekran/bağlantı
görmedi — donanım yoktu, testler dikişleri sürüyor. `docs/manual-test.md`'deki gün 3-7 elle
denemesi yapılmadı. Otomatik güncelleme **çalışmayacak**: iki kullanıcı da yeni sürümü
elle kuracak.

