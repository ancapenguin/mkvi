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

Detaylı mimari karar: `ARCHITECTURE.md`.
**Bitirme planı, verilmiş kararlar ve çalışma kuralları: `ROADMAP.md` — işaretlenmemiş ilk
kutu sıradaki iştir.**

## Değişmez kurallar

- **Özel kripto yazma.** Sadece audited crate'ler (`ed25519-dalek`, `chacha20poly1305`). Yeni bir şifreleme şeması gerekiyorsa önce sor.
- **Worker içerik taşımaz.** `cloudflare/src/index.ts` içindeki `isSignalPayload` anahtar bazında beyaz liste kullanır. Buraya yeni alan eklemek Worker'ı içerik tüneline çevirme riskidir — gerekçesiz genişletme.
- **Protokol daraltmak kırıcıdır.** `isSignalPayload`'dan bir alan çıkarmak, o alanı hâlâ gönderen eski istemcileri `close(1008)` ile düşürür. Çıkarmadan önce repo genelinde o alanın gönderildiği yer olmadığını kanıtla.
- **Türkçe stringler UTF-8, BOM'suz.** Bu dosyalar bir kez mojibake'e uğradı (bkz. faz özeti). Türkçe metin içeren bir dosyayı düzenledikten sonra `grep -n 'Ã\|Å\|Ä' <dosya>` çalıştır; çıktı boş olmalı.
- **Kod yorumları İngilizce**, kullanıcıya görünen her string Türkçe.

## Oturum Devir Akışı

Bu proje oturumlar arası devri `CLAUDE.md`'nin en altındaki tek handoff bloğuyla yürütür.

1. **Oturum başında:** önce `git status` + `git log --oneline -10`, sonra en alttaki
   "Sıradaki Oturum Planı (handoff)" bloğunu, ardından **`ROADMAP.md`'yi** oku ve
   işaretlenmemiş ilk kutudan devam et. Kullanıcıya "ne yapıyorduk?" diye sorma.
   Bir kutu bitince `[x]` yap ve altına tek satır kanıt yaz.
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

**Bu blok kısadır çünkü plan artık `ROADMAP.md`'de.** Oturuma şöyle başla: `git status` +
`git log --oneline -5`, sonra **`ROADMAP.md`'yi aç ve işaretlenmemiş ilk kutudan devam et.**

**Durum:** Sürüm 0.1.4. Çalışma ağacı temiz, **4 commit yerelde ve PUSH EDİLMEDİ**
(kullanıcının kararıydı, ama artık yayın Faz 0'ın ilk maddesi). Tam gate YEŞİL:
`tsc` temiz · `npm test` 58/58 · `cargo test` 6/6 · worker dry-run OK.

**İLK İŞ:** `ROADMAP.md` → Faz 0 → "0.1.4'ü yayınla". Kullanıcı onaylarsa `git push` ve
`v0.1.4` tag'ini at, sonra `gh run list --repo ancapenguin/mkvi --limit 1` ile izle.

**Neden acil:** indirilebilir tek sürüm hâlâ **0.1.2** ve **onda sohbet hiç çalışmıyor** —
mesaj kimliği düzeltmesi (`randomTransferId`, `84e63ac`) v0.1.2'den sonra geldi ve v0.1.3 CI'ı
kırık olduğu için hiç yayınlanmadı. Feed deposunda yalnızca 0.1.0 / 0.1.1 / 0.1.2 var.
v0.1.3'ü kıran hata (`$env:VERSION` tanımsız, installer feed'e kopyalanmıyor) düzeltildi ama
**bu düzeltme CI'da hiç çalışmadı.**

**Bu oturumda çözülen iki kök neden (ikisi de "kapatınca yine kod istiyor" şikâyetine çıkıyor):**

1. **`keyring 3` mock store'a düşüyordu** (`c411f48`). Hiçbir varsayılan özellik getirmiyor;
   platform arka ucu seçilmezse bellek içi mock kullanıyor. Cihaz kimliği ve SQLite anahtarı
   hiç diske yazılmıyordu → her açılışta yeni kimlik → kayıtlı eş çözülemiyor → kod ekranı.
   `Cargo.toml`'da artık platform başına açık arka uç var. **Asıl fail muhtemelen buydu.**
2. **Rendezvous odasının posta kutusu yok** (`150cc6e`). Karşı taraf çevrimdışıyken atılan
   kimlik/teklif çöpe gidiyordu. El sıkışma artık varlık olayında tetikleniyor
   (`src/App.tsx:109`). **TUZAK:** `online` sayacı kendini de sayar, eş varsa `online > 1`.

**Sürüm engelleyici güvenlik açığı — `ROADMAP.md` Faz 1:** SAS ifadesi DTLS parmak izlerini
bağlamıyor, sinyalleşme sunucusunu kontrol eden biri araya girip iki tarafa da aynı ifadeyi
gösterebilir. Android'e geçmeden kapatılmalı.

**Doğrulanmamış olanlar (iddia etme):** arayüz gerçek pencerede hiç görülmedi; uçtan uca dosya
aktarımı ≥100 MB ile hiç denenmedi; keyring düzeltmesi gerçek kapat-aç testinden geçmedi.

**Çalışma kuralları ve tuzaklar `ROADMAP.md`'nin sonundadır** — Codex'in bu makinede mevcut
dosyayı düzenleyemediği (ama yeni dosya oluşturabildiği), PowerShell'in Türkçeyi bozduğu ve
model seçimi (`sol` yalnız araştırma, mekanik lane'ler `terra`) orada yazılı. Oraya bak.
