# 0.1.x Tauri hattı — miras kaydı

> **Bu belge bir kullanım kılavuzu değil, bir MİRAS KAYDIDIR.** 0.1.x hattı
> 2026-09-26'da emekliye ayrıldı ve kodu depodan silindi. Aşağıdaki şeylerin
> **artık çalıştırılabilir bir referansı yoktur**; buradaki amaçları, o hatta ne
> kanıtlandığını ve o kanıtın nereye taşındığını kayıt altında tutmaktır.
>
> Silinen kod: `src/`, `src-tauri/`, `index.html`, `vite.config.ts`, `tsconfig*.json`,
> `package.json`, `package-lock.json`, `spike/`.
> Yayımlanmış son sürüm: **0.1.4** (git tag `v0.1.4`).

---

## Bu hat neydi

**Tauri 2 + React 19 + TypeScript + Rust**, tek bir masaüstü uygulaması olarak
Windows'ta çalışıyordu.

| Katman | Konum | Ne yapıyordu |
|---|---|---|
| Arayüz / orkestrasyon | `src/App.tsx` (581 satır), `src/components/ChatCallWorkspace.tsx` (564 satır) | Pairing, SAS onayı, otomatik yeniden keşif, çağrı ekranı |
| WebRTC taşıma | `src/services/peer-transport.ts` (545 satır) | Perfect negotiation, DataChannel üzerinde chat + kabul onaylı dosya + medya |
| Sinyalleşme istemcisi | `src/services/rendezvous.ts` (64 satır) | `wss`/`ws` soketi, `/v1/rendezvous` ve `/v1/peer` |
| ICE yapılandırması | `src/domain/ice.ts` (71 satır) | Kullanıcı verdiği STUN/TURN listesi; gömülü relay yok |
| Protokol tipleri | `src/domain/signaling.ts`, `src/domain/peer-transport.ts` | Platformdan bağımsız zarf + çerçeve tipleri |
| Yerel güvenlik / IPC | `src/services/local-security.ts` (34 satır) | `invoke()` sarmalayıcıları — 8 Tauri komutu |
| Dosya yazımı | `src/services/file-sink.ts` | Rust'a akan base64 parçalar; WebView belleği 4 MB ile sınırlı |
| Rust kabuk | `src-tauri/src/lib.rs` (165 satır), `main.rs` | Yalnız IPC yüzeyi; iş mantığı `mkvi_core`'da |
| Rust çekirdek | `mkvi_core` (o zaman `src-tauri`'nin bir parçası) | Ed25519 kimlik, keyring/DPAPI, XChaCha20-Poly1305'li SQLite, dosya sink'leri |

**Mimari kural şuydu:** Rust çekirdeğin sahibi, Tauri'den bağımsız olmak zorundaydı.
0.1.x'te bu kural zaten tutuluyordu — `lib.rs`'nin başındaki yorum *"This package owns
nothing but the IPC surface"* diyordu ve `mkvi_core` derlenirken Tauri bilmiyordu.
**Bu yüzden çekirdek bugün `crates/mkvi_core` olarak duruyor ve emeklilik onu
vurmadı.** Kaybedilen yalnız kabuk ve arayüzdü.

### Emekliye ayrılma sebebi

Karar: `docs/adr/0001-flutter-migration.md` (2026-09-26, *Kabul — koşullu*).
Özet gerekçe — 0.1.4 gerçek Windows cihazlarda iki kişi arasında denendi ve **on kök
neden** çıktı; ikisi ürünü kullanılamaz hale getiriyordu:

1. **Kamera ve ekran paylaşımı hiç çalışmıyordu** — sebep kod değil platformdu. Tauri
   hiçbir WebView2 izin handler'ı kaydetmiyordu, wry `--disable-features=msWebOOUI`
   ile izin balonunu kapatıyordu. Tauri 2.11.5'te bunun hazır bir API'si yok
   (`tauri-apps/tauri#14753` hâlâ açık). Çözüm elle COM (`ICoreWebView2_4`) yazmaktı.
2. **Yeniden bağlanma çalışmıyordu**, uygulama beyaz eşleştirme ekranına düşüyordu —
   dört ayrı hata: bootstrap hatasının "ilk kurulum" sanılması, IPC korumasının
   olmaması, keyring boşken **sessizce yeni kimlik** üretilmesi, kalıcı `return` ile
   ölen yeniden bağlanma döngüsü.

Ayrıca hedef platform değişti (Android ikinci hedef) ve güncelleme feed'i işleten
`ancapenguin/mkvi-updates` deposu 404 veriyordu (canlı doğrulandı, `ROADMAP.md` #10).

**Geriye dönük uyumluluk yapılmadı:** migration yok, eski istemcilerin otomatik
güncellenmesi yok. Uygulamayı kullanan iki kişi (kullanıcı + kuzen) 0.2.0'ı elle
kuracak. `identifier: com.mkvi.desktop` ve Tauri'nin `productName: MKVI`'si bu
yüzden iki uygulamanın kayıtlarını çakıştırmaya devam edebilir — ayrıntı
`CONTRIBUTING.md`'de kayıtlıydı, o kayıt da bu hatla birlikte emekliye ayrıldı.

---

## 0.1.x'in kanıtladığı ve artık referansı olmayan şeyler

> Bu liste, kod silinince kaybolan **bilgiyi** korur. Her madde için "nereye
> taşındı" sütunu, o bilginin bugün nerede yaşadığını gösterir.

### 1. `peer-transport.ts` — glare kurtarması (`rollback`)

`handleSignalNow()` içinde perfect negotiation'ın tamamı vardı:

```ts
const collision = this.makingOffer || this.pc.signalingState !== "stable";
this.ignoreOffer = !this.isPolite() && collision;
if (this.ignoreOffer) return;
if (collision) await this.pc.setLocalDescription({ type: "rollback" });
```

Politeli/kibar ayrımı, karışma anında `rollback`, kuyruğa alınmış ICE adaylarının
`setRemoteDescription` sonrası boşaltılması — hepsi bu dosyadaydı.

**Nereye taşındı: taşınmadı, ama gerek kalmadı.** Dart tarafı üç `sendrecv`
transceiver'ı `open()`'dan itibaren kurar; medya tarafında bir glare penceresi hiç
oluşmadığı için rollback'e ihtiyaç duymuyor. Bunu tahmin değil **sayıyla** söylüyor:
`MediaController.negotiationCount` `open()` sonrası **1** ve ebediyen **1**.
Bkz. `app/lib/media/README.md`, `app/lib/media/media_controller.dart`.

**Neden önemli:** `rollback` hâlâ plugin'in bilinmeyen bir yeteneği
([#625](https://github.com/flutter-webrtc/flutter-webrtc/issues/625), 2021'den beri
açık). Silinen bu kod, o bilinmezliğin **Dart'ta neden sorun olmadığının** kanıtıydı.
Artık bu kanıtın tek kaynağı `docs/manual-test.md` gün 1-2 ölçümü ve
`app/lib/media/` yorumlarıdır.

### 2. `ice.ts` — STUN/TURN mantığı

Kullanıcı verdiği ICE yapılandırması: bare URL listesi **ya da** JSON dizisi (TURN
kimlik bilgisi için), `stuns?:`/`turns?:` şema denetimi, 8 sunucu / sunucu başına 8
adres sınırı, `turns?:` görülüyorsa `username`+`credential` zorunluluğu,
`hasRelay()` ile "simetrik NAT'ı atlatabilir miyiz" sorusu. Ayrıca hat, **hiçbir
 relay sağlayıcısının gömülü olmadığını** ve TURN'ün yalnız DTLS şifreli kare
 aktardığını, ama iki adresin trafik değişimi gözlemlediğini açıklayan bir karar
 notu taşıyordu.

**Nereye taşındı:** kararın kendisi `ROADMAP.md` "Verilmiş kararlar" bölümünde
("Varsayılan sunucu gömülmez") ve `crates/mkvi_core` katman kuralında yaşıyor. Ayar
panelindeki metin alanı ve doğrulama kuralları ise bu satırda **kayıpsız bir kopyaya
taşınmadı** — 0.2.0'da yeniden yazılacak. Bu, iki cihazlı testte (5 numaralı ölçüm)
bağlantı kurulamıyorsa ilk bakılacak yer olmalı.

### 3. `rendezvous.ts` — sinyalleşme istemcisi

`/v1/rendezvous` (15 dakikalık, tek kullanımlık pairing odası) ve `/v1/peer`
(uzun ömürlü, çift kapsamlı keşif odası) bağlantıları; zarf grameri (`relay` /
`presence` / `room` / `ready`); `1003` ile bozuk mesaj kapatma; açılış öncesi
reddedilen promise; `onDisconnect`'in socket başına en fazla bir kez çalışması.

**Nereye taşındı: `app/lib/signaling/rendezvous_client.dart` — ve orası daha doğru.**
İki kusur düzeltildi, ikisi de ölçülmüş sözleşme ihlali:

| Kusur | 0.1.x | Dart |
|---|---|---|
| `wss://` adresi | `rendezvous.ts:13` yalnız `https:` → `wss:` eşliyor, `wss:` girdisi **`ws:`'ye düşüyor** — kimlik imzaları ve SDP açıkta | `buildSignalingUrl`: `https`/`wss` → `wss`, `http`/`ws` → `ws`; hiçbir şey yükseltilmez/düşürülmez |
| Geçersiz endpoint | `new URL(path, endpoint)` promise'in **dışında** → `connect(...).catch(...)` hiç çalışmaz, ham `TypeError: Invalid URL` | `_open` `async`: hata **reddedilen gelecek** olarak `signalingConnectError` taşır |
| `relay` zarfı | `onSignal` `unknown` tipli, ne gelirse iletir | payload `SignalPayload`'a çözülmezse 1003 ile kapatılır |

Kanıt: `vectors/wire-v1.json` (134 vaka) ve `ROADMAP.md` #11-#12.
**Kusurlar bu belgede de kalıyor; `rendezvous.ts` silindiği için `it.fails`
işaretleriyle yaşayan kanıt değil, buradaki kayıt.**

### 4. `src-tauri/src/lib.rs` — 12 IPC komutu, ham anahtar sınırı

Cihaz kimliği, imzalama/doğrulama, geçmiş (append/list), eş kaydı, ve 4 dosya-sink
komutu (`file_sink_open/write/close/abort`). Kritik tasarım kararı: **özel anahtar
frontend'e hiç geçmez** — `sign_pairing` imzayı döndürür, `device_public_key` yalnız
genel anahtarı. `MAX_OPEN_SINKS = 4` ile eşzamanlı disk yazımı sınırlıydı; transfer
baytları WebView belleğinde birikmiyordu.

**Nereye taşındı: `crates/mkvi_core/src/security.rs` ve `crates/mkvi_bridge`.**
Daha temiz çünkü kabuk katmanı Tauri'den tamamen ayrıldı: `SecretStore` trait'i
(`security.rs:40-43`) Android için doğru dikiş noktası, ve sessiz sır üretme
kapatılacak (`KeyringEntryMissing`, `ROADMAP.md` Faz 1) — bu, 0.1.x'in en can
yakıcı kusuruydu (`ROADMAP.md` #9).

### 5. Tauri yapılandırmasının taşıdığı, kodda görünmeyen kararlar

`src-tauri/tauri.conf.json` silindi, dolayısıyla şu sabitler de gitti:
`identifier: com.mkvi.desktop` (uygulama veri dizini + paylaşılan WebView2 profilinin
kimliği), `productName: MKVI`, `plugins.updater.pubkey` (minisign kök anahtarı) ve
`endpoints`, `createUpdaterArtifacts`, `installMode: passive`, ve sıkılaştırılmış CSP
satırı. **Güncelleme feed şeması geçerli kalıyor** (`latest.json` resmen doğru
şemada ve imzalı); yalnızca istemci değişti. `*.key` / `*.key.pub` / `.secrets/`
`.gitignore`'da **kaldı** — imzalama gerekiyor.

### 6. Testlerin kapsamı — ve kapsamadıkları

`src/` altında 6 test dosyası, 27 test vardı. `ROADMAP.md`'nin dürüstlük notu
doğruydu ve **bugün de doğru**: 27 testin **tamamı** ayrıştırıcı/doğrulama işlevleri
(`parseControl`, `safeName`, `safeMime`, `randomTransferId`) için; çağrı durum
makinesi, medya, müzakere, yeniden bağlanma, isim, bildirim ve kontrast için **sıfır**
test. Bu yüzden `ROADMAP.md`'deki on kusurun hiçbirinde regresyon testi yoktu ve
"kilitlendi" denemezdi.

### 7. Vektör sözleşmesinin ilk uygulaması

`src/services/signaling-vectors.test.ts` (414 satır) `vectors/wire-v1.json`'u
`import.meta.glob(..., { query: "?raw" })` ile okuyordu. Ortak vektör dosyası her iki
dili **aynı** kurallara bağlıyordu ve 0.1.x'in iki gerçek kusurunu bu sayede ortaya
çıkardı (8 vakit, iki kök neden). Bu, dosyanın TypeScript kopyasıydı; sözleşmenin
kendisi `vectors/` altında yaşamaya devam ediyor ve Dart tarafı da onu kullanıyor.

### 8. Arayüzün erişilebilirlik borcu (bilerek taşınmadı)

`ROADMAP.md` #4: 17 WCAG ihlali; en kötüsü video placeholder ışık temada
**1.17:1**, odak halkası vurguyla aynı (**1.00**). `src/App.css` ve
`src/components/ChatCallWorkspace.css` (593 satır) silindi — bu ölçümlerin **kaynağı**
gitti. Çözüm yolu kodda değil, `design/tokens.json`'da: kontrast testiyle kilitli
tasarımın tek kaynağı. `app/lib/ui/notice/README.md` bu sınıftan bulguların Dart
karşılıklarını zaten kayıt altına almış durumda.

### 9. Güncelleme hattı — ve iki kusurun **çelişen** anlatısı

Bu, koddan temizlenip buraya taşınan en çok yanlış iddia barındıran bölüm.

**Özel feed deposu.** 0.1.x `latest.json`'u
`ancapenguin/mkvi-updates` deposunda tutuyordu ve
`raw.githubusercontent.com/ancapenguin/mkvi-updates/main/latest.json` adresinden
okuyordu. `publish-update.yml` o depoyu SSH deploy key ile klonlayıp `latest.json`'ı
oraya push ediyordu.

**Bu yapısal olarak imkânsızdı:** `raw.githubusercontent.com` gizli bir depoyu
kimlik doğrulanmamış istemciye **hiç servis etmez**. Deploy key yalnız *yazma*
izni verir, okuma izni vermez. Depo kullanıcı tarafından 2026-09-26'da silindi.

**Legacy yayın anahtarı — buradaki iddia yanlıştı ve düzeltildi.** Yayın anahtarı
minisign'in **emekli** `Ed` biçimindeydi (`0x45 0x64`). Bu anahtarı üreten yapı
`src-tauri/tauri.conf.json`'a gömülüydü.

Kod ve kayıt defterinin uzun süre iddia ettiği şu idi: *"Tauri updater bu anahtarı
reddediyor ve kullanıcıya 'dosyan değiştirilmiş olabilir' diyor."* **Bu ölçüldü ve
yanlış çıktı:**

- `tauri-plugin-updater` 2.10.1, `src/updater.rs:1461`'de
  `public_key.verify(data, &signature, true)` çağırıyor — yani
  **`allow_legacy = true`**.
- `minisign-verify` 0.3.0 her iki algoritma etiketini de kabul ediyor
  (`lib.rs:296-299`).

Yani **0.1.x'i öldüren şey legacy anahtar değil, ölü feed'di.** Tek başına ölü
feed yeterliydi: imzaya hiç varılmadan ilk adımda 404 dönüyordu.

**Ama legacy anahtar ters yönde gerçek bir kusurdu ve öyle kaldı:** 0.2.0'ın Rust
çekirdeği `crates/mkvi_core/src/update.rs:116`'da `allow_legacy`'i **sabit `false`**
yapıyor ve `:103-105`'te legacy anahtarı doğrulamadan **önce** reddediyor. Yani bu
anahtar 0.1.x'i engellemiyordu, **0.2.0'ı engelliyor.**

**Bugünkü tek yüzü iki yerde:** `app/lib/update/update_config.dart` içindeki
`releaseFeedUrlText` ve `UpdateFailureReleaseKeyMissing`.

---

## Bu hattın yerine geçen şey

**Dart tarafı bu hattın yerine geçti.** Kanıtın ve kararın kayıtları:

| Konu | Kayıt |
|---|---|
| Karar, gerekçe, kabul edilen riskler, tersine çevirme koşulu | `docs/adr/0001-flutter-migration.md` |
| Depo haritası, fazlar, kanıtlanmış/kanıtlanmamış ayrımı, 0.1.4'ün on kusuru | `ROADMAP.md` |
| İki cihazlı elle test protokolü ve **önceden sabitlenmiş** karar kuralı | `docs/manual-test.md` |
| 0.1.x'in arayüz bulgularının Dart karşılıkları (satır satır) | `app/lib/ui/notice/README.md`, `app/lib/media/README.md` |
| Sinyalleşme zarf sözleşmesi ve ihlal vakaları | `vectors/README.md`, `vectors/wire-v1.json` |
| Rust çekirdeğin bugünkü hali | `crates/mkvi_core/`, `crates/mkvi_bridge/` |
| Güncelleme hattının bugünkü kurulumu (feed, anahtar, imza doğrulama) | `app/lib/update/update.dart` |

> **Bu belge bir miras kaydıdır, bir kullanım kılavuzu değil.** Silinen kodu
> geri getirmeye, taşımaya ya da 0.1.x'i çalıştırmaya çalışmak için kullanma.
> Ölçmek gereken şey bugün `app/` altındadır; nasıl ölçüleceği
> `docs/manual-test.md`'dedir.
