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
- **Faz 6 (Android denemesi) ve Faz 7 (sertleştirme) başlamadı.**

---

## Sıradaki Oturum Planı (handoff — bittiğinde sil)

> ⚠️ **BU BÖLÜM TEK OTURUM BLOĞU İÇERİR. Yeni handoff yazarken eski tarihli bloğu SİL,
> ÜSTÜNE EKLEME. >1 tarihli blok görürsen fazlasını SİL.**

### 2026-07-26 (akşam)

**Durum:** Tam gate YEŞİL — `npx tsc --noEmit` temiz, `npm test` 30/30, `cargo test` 6/6,
`cloudflare && npm run check` dry-run başarılı. İnceleme listesinin **6 maddesinin tamamı kapandı**.
Çalışma ağacında **commit edilmemiş** değişiklikler var.

**KURULUM/DAĞITIM DURUMU (kullanıcı sordu, cevap burada dursun):**
GitHub Releases **boş** — `v0.1.0` ve `v0.1.1` tag push'larının ikisi de başarısız oldu; sadece
26 Tem 19:09'daki `workflow_dispatch` çalışması feed'e yükledi. Bugün çalışan tek indirme linki:
`https://raw.githubusercontent.com/ancapenguin/mkvi-updates/main/windows-x86_64/MKVI_0.1.1_x64-setup.exe`
(HTTP 200, 3.61 MB doğrulandı). Worker canlı — `/` adresine `426 Upgrade Required` dönmesi
normaldir, yalnızca WebSocket kabul ettiği anlamına gelir.

**İLK İŞ:** Çalışma ağacını tek commit olarak kaydet —
`src-tauri/src/lib.rs`, `src-tauri/tauri.conf.json`, `src/domain/peer-transport.ts`,
`src/services/peer-transport.ts`, `src/services/file-sink.ts`, `src/services/file-sink.test.ts`,
`src/services/local-security.ts`, `src/App.tsx`, `.github/workflows/publish-update.yml`, `CLAUDE.md`
→ "Akışlı dosya alımı, Releases tabanlı güncelleme, daraltılmış CSP ve tek eş tipi".
Commit'ten sonra **push etme**, kullanıcıya sor.

**ÇÖZÜLEN KÖK NEDEN (2026-07-26 akşam):** "Signaling sunucusuna bağlanılamadı." hatasının ve
kuzenle yaşanan ilk eşleşme başarısızlığının gerçek sebebi bulundu: `PairingRoom` odaya giren
bağlantıyı `admitted` olarak diske yazıyor ama kapanışta **azaltmıyordu**; eşik 2 olduğu için
tek bir yeniden deneme kodu 15 dakikalığına ölü hale getiriyordu. `MAX_ADMISSIONS = 8` ile
düzeltildi (`cloudflare/src/index.ts`), Worker yayına alındı ve canlı doğrulandı (4/4 yeniden
bağlanma başarılı). **Bu sunucu tarafı bir düzeltmedir; istemci güncellemesi gerektirmez.**

**Sonra sırayla:**

1. **Gerçek uçtan uca dosya testi yapılmadı.** `file_sink_*` komutları yalnızca birim
   testleriyle doğrulandı; iki cihaz arasında büyük (≥100 MB) bir dosya hiç aktarılmadı.
   `npm run tauri dev` ile iki örnek açıp aktarım yap, İndirilenler klasöründe dosyanın
   bozulmadan oluştuğunu ve WebView belleğinin şişmediğini gör. Kusur çıkarsa bakılacak yer:
   `src/services/peer-transport.ts:300` (`flushReceive` sıralaması) ve
   `src-tauri/src/lib.rs` içindeki `file_sink_write`.
2. **Yayın akışı canlıda denenmedi.** Yeni workflow installer'ı GitHub Releases'e yüklüyor,
   feed reposuna sadece `latest.json` gidiyor (`.github/workflows/publish-update.yml:29-49`).
   `permissions: contents: write` eklendi. Bir `v*` tag'i push etmeden önce workflow'u
   `workflow_dispatch` ile elle çalıştırıp doğrula. **Eski istemciler kırılmaz** — feed URL'si
   (`raw.githubusercontent.com/.../latest.json`) değişmedi, sadece içindeki `url` alanı değişti.
3. `mkvi-updates` reposunda **eski installer binary'leri hâlâ git geçmişinde**. Yeni sürümler
   artık oraya yazmıyor ama geçmiş küçülmez. **Karar noktası:** repo yeniden mi kurulsun
   (temiz history, tek `latest.json`) yoksa olduğu gibi mi bırakılsın? Kullanıcıya sor.

**Açık işler (kod dışı, kullanıcı kararı bekliyor):**

- **`.secrets/` içindeki düz metin özel anahtarlar HÂLÂ DURUYOR.** Kullanıcı silinmesini
  onayladı ama Claude'un izin sınıflandırıcısı `Remove-Item`'ı engelledi. Kullanıcının elle
  çalıştırması gereken komut:
  `Remove-Item .secrets\mkvi-updater.key, .secrets\mkvi-updater.password, .secrets\mkvi-updates-deploy -Force`
  Ayrıca artık kullanılmayan eski GitHub secret'ı: `gh secret delete MKVI_UPDATES_DEPLOY_KEY --repo ancapenguin/mkvi`.
  (Karşılıkları GitHub Secrets'ta mevcut: `TAURI_SIGNING_PRIVATE_KEY`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`,
  `MKVI_UPDATES_DEPLOY_KEY_B64` — doğrulandı.)
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

- **PowerShell 5.1 `Get-Content -Raw` bu dosyaları ANSI okuyor.** `CLAUDE.md` gibi Türkçe
  içeren dosyaları PowerShell ile kesip yazmaya çalışma — Edit aracını kullan. Bu oturumda
  `Substring` denemesi patladı ve dosyayı boşaltmasına ramak kaldı.
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
