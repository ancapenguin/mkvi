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
- **Faz 6 (Android denemesi) ve Faz 7 (sertleştirme) başlamadı.**

---

## Sıradaki Oturum Planı (handoff — bittiğinde sil)

> ⚠️ **BU BÖLÜM TEK OTURUM BLOĞU İÇERİR. Yeni handoff yazarken eski tarihli bloğu SİL,
> ÜSTÜNE EKLEME. >1 tarihli blok görürsen fazlasını SİL.**

### 2026-07-26 (gece)

**Durum:** Tam gate YEŞİL — `tsc` temiz, `npm test` 40/40, `cargo test` 6/6, worker dry-run OK.
Çalışma ağacı **temiz**, her şey commit'li ve `main` push'lu (son commit `84e63ac`).

**İLK İŞ:** `gh run list --repo ancapenguin/mkvi --limit 2` ile **v0.1.3 derlemesinin
(`30220047653`) bittiğini doğrula.** Başarılıysa şu linkin anonim indiğini test et:
`https://raw.githubusercontent.com/ancapenguin/mkvi-updates/main/windows-x86_64/MKVI_0.1.3_x64-setup.exe`
(200 + `MZ` başlığı bekleniyor). Başarısızsa `gh run view <id> --log-failed` oku.
Kullanıcı bu linki kuzenine gönderecek; SmartScreen uyarısı normaldir (imza sertifikası yok).

**DAĞITIM GERÇEĞİ — unutma:** `ancapenguin/mkvi` deposu **private**. Bu yüzden GitHub Releases
asset linkleri dışarıya **404** verir. Installer, public `ancapenguin/mkvi-updates` deposuna
commit'lenir ve `latest.json` oradaki raw URL'yi gösterir. Bu bilinçli bir geri dönüştür;
**Releases'e taşımayı yeniden önerme** (bu oturumda denendi, kırdı, geri alındı).

**ÇÖZÜLEN KÖK NEDEN (2026-07-26 akşam):** "Signaling sunucusuna bağlanılamadı." hatasının ve
kuzenle yaşanan ilk eşleşme başarısızlığının gerçek sebebi bulundu: `PairingRoom` odaya giren
bağlantıyı `admitted` olarak diske yazıyor ama kapanışta **azaltmıyordu**; eşik 2 olduğu için
tek bir yeniden deneme kodu 15 dakikalığına ölü hale getiriyordu. `MAX_ADMISSIONS = 8` ile
düzeltildi (`cloudflare/src/index.ts`), Worker yayına alındı ve canlı doğrulandı (4/4 yeniden
bağlanma başarılı). **Bu sunucu tarafı bir düzeltmedir; istemci güncellemesi gerektirmez.**

**ÇÖZÜLEN KÖK NEDEN 2 — asıl katil:** Rust, açık anahtarı ve imzayı `STANDARD_NO_PAD` ile
kodluyor (`security.rs:108`, `lib.rs:26`) — yani alfabede `+` ve `/` var. Worker ise
base64url bekliyordu (`/^[A-Za-z0-9_-]{86}$/`). İçinde `+` veya `/` geçen her imza
`close(1008, "Disallowed signaling envelope")` yiyordu; 86 karakterlik bir imzanın buna
takılmama şansı `(62/64)^86` ≈ %7. Yani eşleştirmelerin ~%93'ü kimlik alışverişinde sessizce
ölüyordu ve kullanıcı sadece "Kodu oluşturan cihazın bağlantıyı başlatması bekleniyor."
ekranında kalıyordu. Worker'da `KEY_B64` / `SIGNATURE_B64` her iki alfabeyi de kabul edecek
şekilde genişletildi (daraltma değil — eski istemciler kırılmaz), yayına alındı
(`c7abefd4`), iki istemcili canlı testle doğrulandı.
**İstemci tarafını DEĞİŞTİRME:** Rust'ı base64url'e çevirmek kayıtlı eşlerin `public_key`
temsilini değiştirir ve mevcut eşleşmeleri bozar.

**Sonra sırayla:**

1. **0.1.3'ü kuzenle canlı dene ve SONUCU SOR.** Hangi ekranda takıldıkları tek teşhis
   verisi. İfade ekranı gelmiyorsa sinyalleşme; gelip sonra takılıyorsa WebRTC/NAT
   (o zaman ve yalnız o zaman TURN gündeme gelir — aşağıdaki karara bak).
2. **`cloudflare/` paketine test yaz.** Bu oturumdaki üç kusur da (`admitted` sayacı, base64
   alfabe uyuşmazlığı, UUID'li mesaj kimliği) tip kontrolünden ve testlerden sağ çıktı; Worker'ın
   `isSignalPayload`/`isRelayEnvelope` fonksiyonlarının **hiç testi yok**. Vitest ekle ve kilitle:
   standart alfabeli (`+`,`/`) 43/86 karakterlik kimlik zarfı KABUL edilir; yanlış uzunluk
   reddedilir; aynı kodla 3+ yeniden bağlanma çalışır.
3. **Arayüz gerçek pencerede hiç görülmedi.** 0.1.3'teki grid düzeltmesi yalnızca akıl yürütmeyle
   doğrulandı (`ChatCallWorkspace.css`, açık `grid-template-columns`). Aramada sohbetin yan panel
   olduğunu, sayfanın kaymadığını, başlığın sabit kaldığını gözle doğrula.
4. **Uçtan uca dosya aktarımı hiç denenmedi.** `file_sink_*` yalnızca birim testli; ≥100 MB'lık
   gerçek aktarım yapılmadı. Kusur çıkarsa: `src/services/peer-transport.ts` `flushReceive`
   sıralaması ve `src-tauri/src/lib.rs` `file_sink_write`.
5. `mkvi-updates` reposu her sürümde ~3,8 MB büyüyor ve geçmiş küçülmez. Depo private olduğu
   sürece alternatif yok. **Karar noktası:** ya `mkvi` public yapılır (Releases çalışır), ya
   feed deposuna Releases açmak için PAT secret'ı eklenir, ya da olduğu gibi bırakılır. Kullanıcıya sor.

**Açık işler (kod dışı, kullanıcı kararı bekliyor):**

- **Özel anahtarlar silindi — yerelde imzalı derleme ARTIK MÜMKÜN DEĞİL.** `.secrets/` içinde
  yalnızca `.pub` dosyaları kaldı. İmza anahtarı sadece GitHub Secrets'ta
  (`TAURI_SIGNING_PRIVATE_KEY`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`, `MKVI_UPDATES_DEPLOY_KEY_B64`).
  Yani **her yayın CI'dan geçmek zorunda**: sürümü 4 yerde yükselt
  (`package.json`, `src-tauri/tauri.conf.json`, `src-tauri/Cargo.toml`, `src-tauri/src/lib.rs`
  `application_info`), commit'le, `v*` tag'i push et. `npm run tauri build` yerelde imza
  olmadığı için başarısız olur; bu beklenen davranıştır, düzeltmeye çalışma.
- **Flutter/UI yeniden yazımı gündemde.** Kullanıcı Tauri'nin Windows dışında sorun
  çıkaracağından endişeli; "çekirdek Rust kalsın, UI Flutter olsun" fikrini attı, acelesi yok.
  Bu Faz 6'nın (`ARCHITECTURE.md:41`) asıl karar noktası. Karar verilmeden UI'a büyük yatırım yapma.
- **TURN kararı: KAPANDI, yeniden açma.** Kullanıcı hem Cloudflare Realtime TURN'ü (0,05 USD/GB)
  hem kendi sunucusunu reddetti ("siktir et turnu"). Kod tarafında yalnızca **ayarlanabilir ICE
  alanı** var, sunucu yok, koda gömülü sağlayıcı yok. Bu konuyu **sadece** kuzenle yapılan gerçek
  deneme "ifade ekranı geldi ama bağlanmadı" ile sonuçlanırsa gündeme getir; başka hiçbir durumda açma.
  (Araştırma yapıldı: Netcup Nürnberg ~2,60 €/ay + coturn 4.15 Docker + REST/HMAC kimlik önerisi
  çıktı. Rapor oturum scratchpad'indeydi, kalıcı değil.)

**Bilinen tuzaklar:**

- **DOSYA İÇERİĞİNİ ASLA PowerShell İLE YAZMA — sadece Edit kullan.** Bu oturumda üç kez
  patladı: (1) `Get-Content -Raw` Türkçeyi ANSI okuyup `lib.rs` ve `Cargo.toml`'u mojibake
  yaptı; (2) `Set-Content -Encoding utf8` JSON'lara **BOM** yazdı ve Tauri derlemesi
  "unable to parse JSON ... line 1 column 1" ile kırıldı; (3) `Substring` hatası `CLAUDE.md`'yi
  boşaltmasına ramak kaldı. Sürüm yükseltmek gibi "basit" bir `-replace` bile bunu tetikler.
  Kurtarma yolu: `git checkout -- <dosya>` sonra Edit ile tekrar yap.
- **Claude'un izin sınıflandırıcısı `Remove-Item`'ı engelliyor.** Dosya silme gerektiren
  adımları kullanıcıya komut olarak ver, döngüye girme.

- **Codex CLI bu makinede `--full-auto` ile dosya YAZAMIYOR.** Windows sandbox'ı
  "split writable root sets" hatası verip reddediyor (`CreateProcessAsUserW failed: 5`).
  Lane'ler patch uygulayamadan döngüye girer. Çözüm `--dangerously-bypass-approvals-and-sandbox`
  ama bunu Claude Code'un izin sınıflandırıcısı da engelliyor — kullanılacaksa önce
  `.claude/settings.json`'a Bash izin kuralı eklenmeli. Mekanik düzenlemeleri doğrudan
  Edit ile yapmak daha hızlı ve Türkçe karakterler açısından daha güvenli.
- **Codex lane çıktısına güvenme, doğrula.** Bu oturumda bir lane `rendezvous` şartını
  silerken imza kontrolünü sessizce kopyaladı (`cloudflare/src/index.ts`, iki özdeş satır).
  Typecheck ve testler yine de geçiyordu. Lane raporu iddiadır, kanıt değil — diff'i oku.
- **Mojibake tekrar etmeye meyilli.** Türkçe string içeren bir dosyayı düzenleyen her
  araçtan sonra `grep -n 'Ã\|Å\|Ä' <dosya>` çalıştır.
- Git bu repoda LF→CRLF uyarısı basıyor; bu normal, düzeltmeye çalışma.
