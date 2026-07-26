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
- **Faz 6 (Android denemesi) ve Faz 7 (sertleştirme) başlamadı.**

---

## Sıradaki Oturum Planı (handoff — bittiğinde sil)

> ⚠️ **BU BÖLÜM TEK OTURUM BLOĞU İÇERİR. Yeni handoff yazarken eski tarihli bloğu SİL,
> ÜSTÜNE EKLEME. >1 tarihli blok görürsen fazlasını SİL.**

### 2026-07-26

**Durum:** Tam gate YEŞİL — `npx tsc --noEmit` temiz, `npm test` 26/26, `cargo test` 3/3,
`cloudflare && npm run check` dry-run başarılı. Çalışma ağacında **commit edilmemiş** değişiklikler var.

**İLK İŞ:** Çalışma ağacındaki inceleme düzeltmelerini tek commit olarak kaydet —
`src/services/peer-transport.ts`, `src/services/peer-transport.test.ts`,
`cloudflare/src/index.ts`, `src/domain/signaling.ts`, `src/App.tsx`, `CLAUDE.md`
→ "İnceleme bulguları: mojibake, ölü signaling alanı, birim testleri".
Commit'ten sonra **push etme**, kullanıcıya sor.
(0.1.1 sürüm yükseltmesi ve pairing yarış düzeltmesi `ff38c1e`'de zaten commit'li.)

**Sonra sırayla:**

0. **ACİL — sürüm yayınlamadan önce:** `e4e3ab8` workflow'u `MKVI_UPDATES_DEPLOY_KEY`
   yerine **`MKVI_UPDATES_DEPLOY_KEY_B64`** adlı yeni bir GitHub secret'ı bekliyor
   (`.github/workflows/publish-update.yml:32`), ve değeri base64 kodlu olmalı. Bu secret
   repo ayarlarında oluşturulmadıysa bir sonraki `v*` tag'i push edildiğinde yayın adımı
   patlar. Kullanıcıya secret'ın eklenip eklenmediğini sor; eklenmediyse önce onu hallet.

3. `src/services/peer-transport.ts:333` — `finishReceive` tüm dosyayı bellekte `Blob`
   parçaları olarak topluyor. `MAX_FILE_BYTES` 512 MB (`src/domain/peer-transport.ts:50`),
   yani 512 MB'lık bir aktarım WebView'i şişiriyor. Streaming yazma (File System Access
   API veya Tauri tarafında chunk'ları diske yazan bir komut) araştır. **Karar noktası:**
   Tauri komutuna mı taşınsın (güvenli, hedef yolu Rust seçer) yoksa tarayıcı API'siyle mi?
   Kullanıcıya sor, kendi başına seçme.
4. `.github/workflows/publish-update.yml:47-48` — her sürümde NSIS installer'ı
   `mkvi-updates` git reposuna commit'liyor. Git geçmişi asla küçülmez; birkaç düzine
   sürüm sonra klonlama dayanılmaz olur. GitHub Releases asset'lerine taşımayı öner.
   **Karar noktası:** `latest.json`'daki `url` alanı Releases URL'sine dönerse eski
   istemciler hâlâ raw.githubusercontent adresini soruyor olacak — geçiş planı gerekiyor.
5. `src-tauri/tauri.conf.json:23` — CSP'de `connect-src 'self' https: wss:` her hosta açık.
   Endpoint kullanıcı ayarlanabilir olduğu için bilinçli bir taviz olabilir; daraltmadan
   önce kullanıcıya sor.
6. `src/App.tsx:90` — `listPeers()` liste dönüyor ama sadece `knownPeers[0]` kullanılıyor;
   `display_name` ve UI'daki `peerName` sabit `"Kuzenim"`. Tek eş bilinçli bir ürün kararıysa
   `peers()`'ın liste dönmesi yanıltıcı — ya çoklu eşe açılsın ya tip daraltılsın. Ürün kararı, sor.

**Açık işler (kod dışı, kullanıcı kararı bekliyor):**

- `.secrets/mkvi-updater.key` + `.password` diskte düz metin duruyor. `.gitignore`'da,
  commit riski yok, ama bu anahtar tüm kurulu istemcilere imzalı güncelleme gönderebilen
  kök yetkisi. CI zaten GitHub Secrets kullanıyor. **Silinsin mi, yoksa yedeği alınıp
  parola korumalı bir kasaya mı taşınsın?** Kullanıcı onayı olmadan bu dosyalara dokunma.
- Faz 6 (Android denemesi) hiç başlamadı. `ARCHITECTURE.md:41` bunun Flutter'a geçiş
  kararının yeniden ele alınacağı nokta olduğunu söylüyor.

**Bilinen tuzaklar:**

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
