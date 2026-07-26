# MKVI — proje kılavuzu

Hesapsız, iki cihaz arasında doğrudan (P2P) kişisel iletişim uygulaması.
Tauri 2 + React + TypeScript + Rust. Arayüz dili **Türkçe**, kod yorumları **İngilizce**.

## Komutlar

```powershell
npm install
npm run tauri dev          # geliştirme
npm run build              # tsc + vite build
npm test                   # vitest
cd src-tauri; cargo test   # Rust tarafı
cd cloudflare; npm run check   # wrangler deploy --dry-run
```

**Tam gate** (commit önerisinden önce dördü de yeşil olmalı):
`npx tsc --noEmit` · `npm test` · `cargo test` · `cloudflare && npm run check`

## Mimari harita

| Katman | Yer | Sorumluluk |
|---|---|---|
| Sinyalleşme | `cloudflare/src/index.ts` | 2 Durable Object: `PairingRoom` (15 dk, tek kullanımlık kod) + `PeerRendezvous` (30 gün, kalıcı eş) |
| P2P taşıma | `src/services/peer-transport.ts` | WebRTC perfect-negotiation, DataChannel üzerinde chat + kabul onaylı dosya + medya |
| Yerel güvenlik | `src-tauri/src/security.rs` | Ed25519 kimlik (keyring/DPAPI) + XChaCha20-Poly1305'li SQLite |
| Tauri komutları | `src-tauri/src/lib.rs` | Frontend'e açılan 8 komut; ham anahtar asla frontend'e geçmez |
| UI / orkestrasyon | `src/App.tsx` | Pairing, SAS onayı, otomatik yeniden keşif |
| Tipler | `src/domain/` | Platformdan bağımsız signaling + peer protokol tipleri |

Detaylı mimari karar ve yol haritası: `ARCHITECTURE.md`.

## Değişmez kurallar

- **Özel kripto yazma.** Sadece audited crate'ler (`ed25519-dalek`, `chacha20poly1305`). Yeni bir şifreleme şeması gerekiyorsa önce sor.
- **Worker içerik taşımaz.** `cloudflare/src/index.ts` içindeki `isSignalPayload` anahtar bazında beyaz liste kullanır. Buraya yeni alan eklemek Worker'ı içerik tüneline çevirme riskidir — gerekçesiz genişletme.
- **Protokol daraltmak kırıcıdır.** `isSignalPayload`'dan bir alan çıkarmak, o alanı hâlâ gönderen eski istemcileri `close(1008)` ile düşürür. Çıkarmadan önce repo genelinde o alanın gönderildiği yer olmadığını kanıtla.
- **Türkçe stringler UTF-8, BOM'suz.** Bu dosyalar bir kez mojibake'e uğradı (bkz. faz özeti). Türkçe metin içeren bir dosyayı düzenledikten sonra `grep -n 'Ã\|Å\|Ä' <dosya>` çalıştır; çıktı boş olmalı.
- **Kod yorumları İngilizce**, kullanıcıya görünen her string Türkçe.

## Oturum Devir Akışı

Bu proje oturumlar arası devri `CLAUDE.md`'nin en altındaki tek handoff bloğuyla yürütür.

1. **Oturum başında:** önce `git status` + `git log --oneline -10`, sonra en alttaki
   "Sıradaki Oturum Planı (handoff)" bloğunu oku ve oradan devam et. Kullanıcıya
   "ne yapıyorduk?" diye sorma — handoff bunu zaten söylüyor olmalı.
2. **Yeşil checkpoint'lerde commit öner, push etme.** Tam gate (yukarıdaki dört komut)
   yeşile döndüğünde commit önerisi yap. Push kullanıcının kararıdır; istenmeden push edilmez.
3. **Biten adımın handoff'unu SİL — yeni bloğu üstüne EKLEME.** Handoff stack'lemek
   yasaktır; dosyada her zaman **tek** oturum bloğu bulunur. Tamamlanan işi aşağıdaki
   faz özetine **tek satır** olarak işle.
4. **Oturum sonunda yeni handoff yaz.** İçinde şunlar somut olarak bulunmalı:
   sıralı adımlar · karar noktaları · açık işler · bilinen tuzaklar.
5. **Handoff KENDİNE-YETER olmalı.** Yeni bir oturum sıfır bağlamla açılıp sadece
   "kaldığın yerden devam et" yazdığında ne yapacağını bilmeli. Bunun için handoff
   muğlak bir "şuraya kadar geldik" özeti **olamaz**; şunları içermek zorundadır:
   - **Sıradaki oturumun İLK işi** — tek cümle, emir kipi, tartışmasız.
   - **Kusurun tam yeri** — `dosya:satır` biçiminde, "şu modülde sorun var" değil.
   - **Hangi tuzağa düşülmemesi gerektiği** — bu projede daha önce nereye düşüldüğü.
   - **Karar noktaları** — kullanıcıya sorulacak açık sorular, seçenekleriyle.
6. **Boyut sınırı ~250 satır.** `CLAUDE.md` her oturumda bağlama yükleniyor; şişerse
   detay ayrı bir plan dosyasına taşınır ve burada sadece pointer kalır.

## Faz özeti

- **Faz 1-5 tamam:** Tauri kabuğu, tipli signaling, TTL'li Durable Object Worker, OS güvenli depoda cihaz anahtarı, SAS onaylı eşleştirme, WebRTC DataChannel mesajlaşma, şifreli SQLite geçmiş, kabul onaylı dosya aktarımı, ses/video arama ve ekran paylaşımı.
- **0.1.1 sürüm yükseltmesi + pairing yarış düzeltmesi:** kodu oluşturan taraf artık kimliğini karşı taraf odaya girmeden önce yayınlamıyor (`beginCreatorHandshake`, `src/App.tsx`).
- **2026-07-26 — inceleme bulguları temizliği:** `peer-transport.ts`'teki 5 mojibake Türkçe string onarıldı; Worker'ın `identity` zarfından ölü `rendezvous` alanı kaldırıldı (`signaling.ts` tipiyle birlikte); `App.tsx`'te her render'da `RendezvousClient` üreten ref lazy hale getirildi; `parseControl`/`safeName`/`safeMime` export edilip 22 yeni birim testi eklendi (suite 4 → 26).
- **2026-07-26 — inceleme kapanışı:** dosya alımı akışlı hale getirildi (Rust `file_sink_*` komutları + `src/services/file-sink.ts`; WebView belleği 4 MB ile sınırlı, hedef yolu Rust seçiyor), güncelleme installer'ları GitHub Releases'e taşındı (feed reposuna artık sadece `latest.json` commit'leniyor), CSP daraltıldı (`https:` joker kaldırıldı, `object-src`/`frame-src`/`form-action` kapatıldı), `listPeers()` → `loadKnownPeer()` ile tek eşe daraltıldı ve `peerName` artık kayıttan geliyor. Suite 26 → 30 TS, 3 → 6 Rust.
- **2026-07-26 — ayarlanabilir ICE:** `src/domain/ice.ts` + ayarlar panelinde ICE sunucusu alanı. Koda hiçbir TURN sağlayıcısı gömülmedi; alan boşken davranış eskisiyle birebir aynı (yalnız STUN, saf P2P). Kullanıcı kendi TURN sunucusunu kurmama kararı aldı — alan, ileride gerek olursa yeni sürüm derlemeden çözüm yapıştırabilmek için var.
- **2026-07-26 gece — uygulama İLK KEZ gerçekten bağlandı.** Üç ayrı kusur çözüldü: `PairingRoom`'un `admitted` sayacı kapanışta azalmadığı için tek bir yeniden deneme kodu 15 dk ölü hale getiriyordu (`MAX_ADMISSIONS = 8`); Rust'ın `STANDARD_NO_PAD` base64'ü (`+`,`/`) Worker'ın base64url filtresine takıldığı için eşleşmelerin ~%93'ü kimlik alışverişinde sessizce ölüyordu (Worker iki alfabeyi de kabul ediyor); `sendChat` tireli `crypto.randomUUID()` üretip alıcıdaki `parseControl`'e reddettirdiği için hiçbir mesaj ulaşmıyordu (`randomTransferId`). Worker iki kez yayına alındı.
- **0.1.3 arayüz onarımı:** grid'e açık sütun tanımlandı (sohbet örtük ikinci sütuna sıkışıyordu), sayfa kaydırması kapatıldı, global `input` kuralının `hidden`'ı ezmesi engellendi, kişi adı düzenlenebilir yapıldı (yerelde saklanır, tel üzerinden gitmez), kayıtlı eşe yeniden bağlanma durumu görünür oldu. Suite 30 → 40 TS.
- **0.1.4 — kullanım kalitesi + yayın hattı onarımı:** yeniden bağlanma el sıkışması artık *varlık* üzerine tetikleniyor (oda posta kutusu tutmuyor; karşı taraf çevrimdışıyken atılan kimlik/teklif çöpe gidiyordu, eşleşmelerin yarısı sessizce ölüyordu), kimlik doğrulanmadan gelen sinyaller atılmak yerine kuyruğa alınıyor, dosya aktarımında ilerleme çubuğu, WebView otomatik-tamamlama her alanda kapatıldı, mikrofonsuz cihazda arama artık düşmüyor (yalnız-video'ya geriliyor), kullanıcı kendi adını belirliyor ve `profile` kontrol mesajıyla karşıya gönderiyor (takma ad yerelde kalıyor). v0.1.3 CI'ı `$env:VERSION` boş olduğu için kırılmıştı ve installer feed reposuna hiç kopyalanmıyordu — ikisi de düzeltildi. Suite 40 → 58 (worker paketine ilk 12 test).
- **Faz 8 (Android denemesi) ve Faz 9 (sertleştirme) başlamadı.** Faz 7 (profil fotoğrafı) onaylandı, sıradaki iş.

---

## Sıradaki Oturum Planı (handoff — bittiğinde sil)

> ⚠️ **BU BÖLÜM TEK OTURUM BLOĞU İÇERİR. Yeni handoff yazarken eski tarihli bloğu SİL,
> ÜSTÜNE EKLEME. >1 tarihli blok görürsen fazlasını SİL.**

### 2026-07-27

**Durum:** Sürüm **0.1.4**'e yükseltildi (4 yerde). Çalışma ağacı temiz; commit `150cc6e`
**yerelde duruyor, PUSH EDİLMEDİ** (kullanıcının kararı). Tam gate YEŞİL:
`tsc` temiz · `npm test` 58/58 (6 dosya, worker paketi dahil) · `cargo test` 6/6 · worker dry-run OK.

**İLK İŞ:** Kullanıcıya yayına hazır olduğunu hatırlat; onay verirse `git push` + `v0.1.4`
tag'ini push et, sonra `gh run list --repo ancapenguin/mkvi --limit 1` ile derlemeyi izle.
**v0.1.3 CI'ı BAŞARISIZDI** (`30220047653`) — yani kuzene gönderilecek 0.1.3 installer'ı
hiç var olmadı. Onay gelmeden push etme.

**v0.1.3 NEDEN KIRILDI (düzeltildi, ama doğrulanmadı):** `.github/workflows/publish-update.yml`
içinde `$env:VERSION` hiçbir yerde tanımlı değildi; dosya adı `MKVI__x64-setup.exe` olarak
üretilip `Get-Content` "path not found" ile patlıyordu. Ayrıca adım installer'ı feed reposuna
**hiç kopyalamıyordu**, sadece private repo'nun 404 veren Releases linkini `latest.json`'a
yazıyordu. Artık sürüm `src-tauri/tauri.conf.json`'dan okunuyor, `.exe` public
`mkvi-updates/windows-x86_64/` altına kopyalanıyor ve `latest.json` raw URL'yi gösteriyor.
**Bu düzeltme CI'da hiç çalışmadı — ilk yeşil derleme onu doğrulayacak.**

**DAĞITIM GERÇEĞİ — indirilebilir tek sürüm hâlâ 0.1.2 ve ONDA SOHBET ÇALIŞMIYOR.** Feed
deposunda yalnızca 0.1.0 / 0.1.1 / 0.1.2 installer'ları var; `latest.json` 0.1.2'yi gösteriyor.
Mesaj kimliği düzeltmesi (`randomTransferId`, `84e63ac`) v0.1.2'den *sonra* geldi ve hiç
yayınlanmadı — yani kuzenin elindeki yapı mesaj gönderemiyor. 0.1.4 yayınlanana kadar bu böyle.

**Kuzene gidecek link (derleme yeşile dönünce doğrula, 200 + `MZ` başlığı bekleniyor):**
`https://raw.githubusercontent.com/ancapenguin/mkvi-updates/main/windows-x86_64/MKVI_0.1.4_x64-setup.exe`
SmartScreen uyarısı normaldir (imza sertifikası yok).

**BU OTURUMDA ÇÖZÜLEN KÖK NEDEN — "uygulamayı kapatınca yine kod istiyor":**
`PeerRendezvous` odası 30 gün yaşıyor ama **posta kutusu yok**: karşı taraf çevrimdışıyken
relay edilen her şey çöpe gidiyor. Eski kod `connectKnown` çözülür çözülmez kimliği yayınlayıp
`transport.start()` çağırıyordu; önce açılan cihazın teklifi boşluğa gidiyor, ikinci cihaz
açıldığında kimse yeniden teklif etmiyordu. Anahtar sırasına göre eşleşmelerin yaklaşık yarısı
bu yüzden sessizce ölüyor ve kullanıcı yeniden kod girmek zorunda kalıyordu. Artık el sıkışma
*varlık* olayında tetikleniyor ve eş her göründüğünde tekrarlanıyor (`src/App.tsx:109-160`).
İkinci kusur aynı yerdeydi: kimlik doğrulaması `await` sürerken gelen offer/ICE **atılıyordu**;
artık `deferred` kuyruğunda bekleyip doğrulama bitince işleniyor.
**TUZAK:** `online` sayacı bu odada *kendini de sayar* (`PeerRendezvous.onlineDevices`), eşin
var olması `online > 1` demektir. `PairingRoom` ise farklı semantik kullanır — karıştırma.

**Sonra sırayla:**

1. **0.1.4'ü kuzenle canlı dene ve SONUCU SOR.** Özellikle: uygulamayı kapatıp açınca kod
   istemeden bağlanıyor mu? Bu oturumun ana iddiası bu ve **gerçek iki cihazla hiç denenmedi**.
2. **Arayüz hâlâ gerçek pencerede görülmedi.** İlerleme çubuğu, "Sen: <ad>" rozeti ve arama
   sırasındaki yan panel yalnızca akıl yürütmeyle doğrulandı (`ChatCallWorkspace.css`, grid
   satırları 5'e çıktı). Tarayıcıda doğrulanamaz: `loadDeviceIdentity` Tauri komutu, bu yüzden
   iki gerçek pencere gerekir.
3. **Uçtan uca dosya aktarımı hiç denenmedi** (≥100 MB). Kusur çıkarsa:
   `src/services/peer-transport.ts` `flushReceive` sıralaması ve `src-tauri/src/lib.rs`
   `file_sink_write`. İlerleme çubuğu artık `file-progress` olayını gösteriyor, teşhis kolaylaştı.
4. **Profil fotoğrafı (Faz 7) — KULLANICI ONAYLADI, sıradaki geliştirme işi bu.**
   `ARCHITECTURE.md:38`. Tasarım: DataChannel üzerinden ≤64 KB yeniden boyutlanmış kare
   (canvas ile yerelde küçült), şifreli SQLite'ta yerel saklama, sunucuya hiçbir şey gitmez.
   `profile` kontrol mesajı zaten var (`src/domain/peer-transport.ts`), doğal uzantısı —
   ama fotoğraf 32 KB'lık kontrol mesajı sınırını aşar, ayrı bir ikili çerçeve tipi gerekir
   (`FILE_FRAME` deseni gibi). `parseControl`'e ham base64 gömme.

**Açık işler (kullanıcı kararı bekliyor):**

- **`mkvi-updates` reposu artık her sürümde ~3,8 MB büyüyecek** (installer commit'leniyor) ve
  geçmiş küçülmez. **KARAR VERİLDİ: olduğu gibi kalacak** (kullanıcı 2026-07-27). Yeniden açma.
- **Flutter/UI yeniden yazımı gündemde.** Faz 8'in (`ARCHITECTURE.md:41`) asıl karar noktası.
  Karar verilmeden UI'a büyük yatırım yapma.
- **TURN kararı: KAPALI, yeniden açma.** Yalnızca kuzenle yapılan gerçek deneme "ifade ekranı
  geldi ama bağlanmadı" ile sonuçlanırsa gündeme gelir. Kodda yalnızca ayarlanabilir ICE alanı var.
- **Ses rölesi (Android) sorusu cevaplandı:** ayrı bir röle bileşeni eklenmeyecek; ses zaten
  WebRTC SRTP'dir, doğrudan bağlantı kurulamazsa cevap TURN'dür. `ARCHITECTURE.md:42`.
- **Özel imza anahtarları yerelde YOK.** Her yayın CI'dan geçmek zorunda; `npm run tauri build`
  yerelde imzasız olduğu için başarısız olur, bu beklenen davranıştır.

**Bilinen tuzaklar:**

- **DOSYA İÇERİĞİNİ ASLA PowerShell İLE YAZMA — sadece Edit kullan.** `Get-Content -Raw` Türkçeyi
  ANSI okuyup mojibake yapar; `Set-Content -Encoding utf8` JSON'lara BOM yazıp Tauri derlemesini
  kırar. Kurtarma: `git checkout -- <dosya>` sonra Edit.
- **Görünmez karakter içeren regex'i Edit ile yazma.** Bu oturumda `safeDisplayName`'in bidi/
  zero-width sınıfı iki kez bozuldu; çözüm kod noktası karşılaştırmasına geçmek oldu
  (`src/services/peer-transport.ts`, `safeDisplayName`). Test dosyasında `​` gibi kaçışlar
  güvenli, ama Bash heredoc'a ham kontrol karakteri koyma — araç reddediyor.
- **Codex CLI bu makinede dosya YAZAMIYOR.** `--full-auto` deprecated ve arka planda stdin'de
  asılıyor (`< /dev/null` şart); `--sandbox workspace-write` ile çalışsa bile `apply_patch`
  Windows PowerShell tırnaklaması yüzünden "Invalid patch: The last line of the patch must be
  '*** End Patch'" verip düşüyor. Bu oturumda worker test lane'i 2 testlik taslakta takıldı,
  paket elle tamamlandı. **Mekanik düzenlemeleri doğrudan Edit ile yap.**
- **Mojibake tekrar etmeye meyilli.** Türkçe string içeren bir dosyayı düzenleyen her araçtan
  sonra `grep -n 'Ã\|Å\|Ä' <dosya>` çalıştır; çıktı boş olmalı.
- Git bu repoda LF→CRLF uyarısı basıyor; normal, düzeltmeye çalışma.
