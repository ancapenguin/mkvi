# 0.2.0 — İki cihazlı elle test protokolü (Faz 0 karar kapısı)

> **Bu belge `spike/README.md`'den kurtarılmıştır.** Spike iskeleti bilinçli olarak
> silindi (`spike/` klasöründe yalnız README vardı, ölçümler burada yaşıyordu).
> Protokolün kendisi, gün 3-7 tabloları ve **karar kuralı** birebir korunmuştur;
> yalnızca silinen dosya adlarına işaret eden ekler güncellendi.
>
> **Bu bir kullanım kılavuzu değil, bir karar aracıdır.** Tek soruyu cevaplar:
> *MKVI'nin WebRTC taşıma katmanı `flutter_webrtc` ile Windows'ta gerçekten çalışıyor mu?*
>
> Cevap "evet"se düz port. "Hayır" veya "koşullu" ise `flutter_webrtc` bir path
> dependency olarak vendor edilir ve bilinen kusurlar C++'da yamalanır (Yappa'nın
> yaptığı yol). Bu karar **protokol geçmeden verilmez.**
>
> Bağlı kalan yer: `ROADMAP.md` Faz 0 · Karar: `docs/adr/0001-flutter-migration.md`
> (durum: *Kabul — koşullu*). Kök nedenler ve kanıt kaydı: `docs/legacy-tauri-line.md`.

---

## Güncellenmiş ekler (0.1.x'ten farkı — yalnız bu bölüm yeni)

| Eski | Artık | Neden |
|---|---|---|
| `src/services/rendezvous.ts` | **`app/lib/signaling/rendezvous_client.dart`** | 0.1.x istemcisi **iki gerçek kusur** taşıyor; Dart sürümü ikisini de düzeltiyor. Aşağıya bak. |
| `src/services/peer-transport.ts` (Gün 3 referansı) | **`app/lib/media/media_controller.dart`** + `webrtc_media_backend.dart` | Dart tarafı medyayı rollback'e **ihtiyaç duymayacak** şekilde tasarladı; bkz. "Gün 3 notu". |
| `mkvi_spike.exe` | `app/` içindeki gerçek Flutter istemcisi | Spike iskeleti silindi; ölçüm artık ürünün kendi istemcisiyle yapılır. |
| Tauri build'i (aktarım karşılaştırması) | 0.1.4 kurulu Windows makinesi | Karşılaştırma tabanı değişmedi: referans hâlâ yayımlanmış son Tauri sürümü. |

### Sinyalleşme istemcisi: 0.1.x `rendezvous.ts` **kullanılmaz**

Beklenmedik bir değişiklik: ölçümü 0.1.x istemcisiyle değil, **Dart sürümüyle**
yap. İki sebep — ikisi de 0.1.x'in kendi kusuru, bir stil tercihi değil:

1. **`wss:` sessizce `ws:`'ye düşürülüyor.** `rendezvous.ts:13` yalnız
   `https:` → `wss:` eşlemesi yapıyor; `wss:` girdisi `ws:`'ye düşüyor. Ayarlara
   `wss://` adresi yazan kullanıcı **şifresiz** sinyal bağlantısı alıyor, kimlik
   imzaları ve SDP açıkta. Vektörlerle sabitlendi (`ROADMAP.md` #11).
2. **Geçersiz endpoint `connect()`'i senkron olarak `TypeError` ile kaçırıyor.**
   `new URL(path, endpoint)` promise'in **dışında**, yani `connect(...).catch(...)`
   hiç çalışmıyor; kullanıcı "Signaling sunucusuna bağlanılamadı." yerine ham bir
   `TypeError: Invalid URL` görüyor. 7 vaka (`ROADMAP.md` #12).

Dart sürümü ikisini de düzeltir: `buildSignalingUrl` önce doğrular ve
`https`/`wss` → `wss`, `http`/`ws` → `ws` eşlemesi yapar; `_open` `async` olduğu
için hatalı endpoint **reddedilen bir gelecek** üretir. Kaza ile 7 vaka
`test/signaling` altında yeşildir.

> Bu protokol 0.1.x'in o iki kusurunu **düzeltmek için** yazılmadı — o hat artık
> yayımlanmıyor. Kusurların kaydı `ROADMAP.md` ve `vectors/README.md`'de kalır.
> Buradaki tek gerekçe: **ölçtüğünüz şey ürünün gerçekten kullandığı şey olmalı.**

---

## Ortam (ölçüldü, 2026-09-26)

| Bileşen | Değer |
|---|---|
| Flutter | 3.44.9 stable · Dart 3.12.2 |
| `flutter_webrtc` | **1.6.2+hotfix.3** |
| `webrtc_interface` (Dart API ayrı pakete taşındı) | 1.5.1 |
| Rust | 1.94.1 (x86_64-pc-windows-msvc) |
| Visual Studio | Build Tools 2026, `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` mevcut |
| CMake | scoop ile kurulu |
| libwebrtc | `libwebrtc.m150.7871.02` (CMake yapılandırmasında otomatik indirildi) |
| Android SDK | **yok** — Android fazı daha sonra |

## Gün 1-2 · Derleme ve temel — **GEÇTİ**

Bu aşamanın çıktısı: `flutter build windows --release` → `mkvi_spike.exe`, **143 saniye**
(ilk derleme, libwebrtc indirmesi dahil). Ek araç gerekmedi: `cl` PATH'te yoktu ama
CMake/VS doğru buldu.

**Bu ne kanıtlar:** Flutter + `flutter_webrtc` Windows'ta derleniyor, libwebrtc indirme
boru hattı çalışıyor, MSVC/C++ araç zinciri yeterli. Ayrıca Tauri'deki asıl engel
(WebView2 izin katmanı) Flutter'da **yok** — plugin tarayıcı değil, native
MF/WASAPI/DXGI üzerinden konuşuyor, yani izin balonu diye bir şey yok.

**Bu ne kanıtlamıyor:** hiçbir şeyi. Derlenen bir plugin çalışan bir plugin demek
değil. Aşağıdaki bilinen kusurların hiçbiri derleme aşamasında görünmez.

---

## Gün 3-7 · Çalıştırma protokolü (insan + iki makine gerekir)

Bu bölüm, ekranla yapılacak denemelerin sırasıdır. Her satır için **"çalıştı mı, ve
nasıl anladık"** yazılır. Üçüncü sütun boş bırakılırsa o senaryo sayılmaz.

### Gün 3 — `peer-transport.ts` iskeleti birebir

`src/services/peer-transport.ts` içindeki WebRTC çağrıları birebir çevrilir; oyuncak
örnek değil, gerçek dosya. Kopyalanacak yapı: bağlantı anında **üç `sendrecv`
transceiver** (1 ses + 2 video), `mkvi-v1` adlı sıralı data channel, `getUserMedia` →
ses/kamera sender'larına `replaceTrack`, `getDisplayMedia` → ekran sender'ına
`replaceTrack`, dosya çerçeveleme bayt bayt aynı.

| # | Ölçüm | Sonuç |
|---|---|---|
| 1 | `setLocalDescription(rollback)` çalışıyor mu? (`Invalid type or sdp` veriyor mu?) | |
| 2 | `getStats()` içinde `type == 'certificate'` var mı? `fingerprint` + `fingerprintAlgorithm` değerleri | |
| 3 | `getRemoteDescription().sdp` içindeki `a=fingerprint:` satırı (2) ile **aynı mı**? | |
| 4 | Üç transceiver'ın `mid` değerleri arama boyunca sabit ve ayırt edilebilir mi? | |

> **Gün 3 güncellemesi (yalnız ölçüm, tasarım değişmedi):** 1 numaralı ölçüm
> **plugin'in yeteneğini** yoklar, MKVI'nin ihtiyacını değil. Dart tarafı üç
> transceiver'ı `open()`'dan itibaren kurduğu için medya tarafında bir glare
> penceresi hiç oluşmuyor ve rollback'e ihtiyaç duymuyor — bkz.
> `app/lib/media/README.md` (`MediaController.negotiationCount` `open()` sonrası 1
> ve ebediyen 1). Yani 1'in cevabı ne olursa olsun **ürün davranışını değiştirmiyor**;
> cevabı yine de yaz, çünkü "kapalıyken de davranış bozulmuyor" demek için elde
> kanıt şart. 2-4 aynen geçerlidir ve DTLS parmak izi SAS'ı bağlamak için
> gereklidir (güvenlik açığı, bkz. `ROADMAP.md` Faz 1). (3) geçerse SDP'den almak
> yeter; `getStats` turu gereksiz olur.

### Gün 4 — İki makine, gerçek arama

Sinyalleşme için sahte sunucu değil, **gerçek MKVI rendezvous sunucusu** kullanılır.

| # | Ölçüm | Sonuç |
|---|---|---|
| 5 | `connected` süresi (offer → ICE succeeded), 20 aramanın p50'si | |
| 6 | Çift yönlü ses+video, data channel açılışı | |
| 7 | 512 MB dosya aktarımı uçtan uca — **Tauri build'iyle karşılaştır**, %30 regresyon sınır | |
| 8 | 30 dakika soak: RSS ve handle sayısı | |

> **Gün 4 güncellemesi:** sunucu `cloudflare/` Worker'ıdır ve **hiç değişmedi** —
> aynı Durable Object, aynı zarf sözleşmesi. İstemciyi `rendezvous_client.dart`
> ile çalıştır (yukarıdaki "Sinyalleşme istemcisi" notu). 7'nin karşılaştırma
> tabanı: yayımlanmış son Tauri sürümü, yani 0.1.4.

### Gün 5 — Ekran paylaşımı (kararı belirleyen gün)

İki makinede de, ve **düğmeye tıklayarak değil, arama sırasında `replaceTrack` ile**
başlatarak denenmeli — `#2137` yalnızca o yolda tetikleniyor.

| # | Senaryo | Ne arıyor | Sonuç |
|---|---|---|---|
| 9 | Başka uygulama öne geliyorken ekran paylaşımı | `#2137`: çözümüyor, sonsuza kadar siyah, `framesEncoded=0`, hata yok | |
| 10 | Hedef pencere küçültülmüş | `#2137` ikinci dalı | |
| 11 | 20 kez başlat/durdur | capturer yarış durumları | |
| 12 | HDR ekran (varsa) | `#2205`: renk bozuk (2 gün önce açıldı, RustDesk'te de aynı) | |
| 13 | Kamera + ekran aynı anda | iki video transceiver tasarımı | |
| 14 | Arama sırasında mikrofon değiştirme | `#2097`: AEC sızıntısı, giden seslerde cızırtı | |
| 15 | Arama sırasında kamera değiştirme | |
| 16 | `getDisplayMedia({'audio': true})` ile sistem sesi | WASAPI loopback: çalışıyor mu, yoksa sessizce boş `audioTracks` mi dönüyor? |
| 17 | Kamera yok / cihaz takılı değil | hata tipi **ham `String`**, `PlatformException` **değil** — yakalama yerini doğrula |
| 18 | Arama sırasında uygulamayı kapat, 20 kez | çıkışta çökme |

> **Gün 5 güncellemesi:** senaryolar ve sıraları aynen geçerli; arayüz eşleşmesi
> `app/lib/media/` (`MediaController`) ve `app/lib/call/` (`CallMachine`). 17 özellikle
> önemli: 0.1.x'te kamera/ekran hatası Türkçe olmayan ham `DOMException` metniydi
> (`ROADMAP.md` #6) — yakalama yerinin doğru olduğunu kanıtla, sadece hatayı
> gördüğünü sanma.
>
> Her ekran paylaşımı hatası için ayrıca kaydet: **anlamam kaç saniye sürdü?**
> 3 saniyeden uzun sürüyorsa bu bir ürün bulgusudur: "ilk kare bekleniyor" durumu
> (`outbound-rtp.framesEncoded` izlenerek) arayüze eklenmeli. Plugin hiçbir şey
> bildirmediği için bu bilgiyi biz üretmek zorundayız.

### Gün 6 — Dayanıklılık

`close()`/`dispose()` döngüleri, 60 dakika soak, 1080p30'da CPU, `getStats` tur süresi
(çağrı başına rapor sayısı ve gecikme).

### Gün 7 — Karar

| Soru | Cevap |
|---|---|
| 1. `rollback` çalışıyor mu? | |
| 2. SDP parmak izi ile `getStats` parmak izi aynı mı? | |
| 3. 10 ekran paylaşımı senaryosundan kaçı geçti, kaçı **sessizce** başarısız oldu? | |
| 4. Dosya aktarımı Tauri'ye göre ne durumda? | |
| 5. Soak'ta çökme var mı? | |

**Karar kuralı (denemeden önce sabitlendi, sonradan oynanmayacak):**

- 1 · 2 · 5 olumlu **ve** 3'te ≥8/10 senaryo geçiyorsa ve çökme yoksa → **Düz port.**
- `rollback` bozuksa, `#2137` **tespit edilemiyorsa** veya 4'ten fazla senaryo
  başarısızsa → **Vendor fork**: `flutter_webrtc` path dependency olur,
  `flutter_screen_capture.cc` içinde `Start()` dönüş değeri yayınlanır, `OnError`
  iletilir, HDR için WGC arka ucu eklenir.
- Soak'ta çökme varsa veya dosya aktarımı Tauri'ye göre %30 geriliyorsa →
  **Windows'ta NO-GO.** Tauri 0.1.x donmuş hat olarak kalır.

> **Karar kuralı değiştirilmedi, yalnız kapsamı daraldı:** "Tauri 0.1.x donmuş hat
> olarak kalır" dalı artık **güncel değil** — hat 2026-09-26'da emekliye ayrıldı
> (`docs/legacy-tauri-line.md`). Bu dal **yalnız** şu anlama gelir: *Windows'ta
> Flutter'a geçme; Android fazını atla ve mimariyi yeniden düşün.* Kararın
> kendisi, eşiği ve yönü aynen korunmuştur.

## Bilinen kusurlar (denemeden önce kayda geçirildi)

| Kimlik | Durum | Etki |
|---|---|---|
| [#2137](https://github.com/flutter-webrtc/flutter-webrtc/issues/2137) | açık | `getDisplayMedia` **başarılı** dönüyor, track asla kare üretmiyor. Dart tarafından **tespit edilemiyor.** |
| [#2205](https://github.com/flutter-webrtc/flutter-webrtc/issues/2205) | açık (2 gün önce) | HDR ekranda renk bozuk (DXGI 8-bit BGRA taşması). WGC arka ucu yok. |
| [#1953](https://github.com/flutter-webrtc/flutter-webrtc/issues/1953) | açık | Ekran paylaşımı başlatırken native çökme. |
| [#625](https://github.com/flutter-webrtc/flutter-webrtc/issues/625) | 2021'den beri açık | Perfect negotiation / `rollback` hiç test edilmemiş. |
| [#2097](https://github.com/flutter-webrtc/flutter-webrtc/issues/2097) | açık | Windows'ta mikrofon değiştirme AEC sızdırıyor. |
| [#2146](https://github.com/flutter-webrtc/flutter-webrtc/issues/2146) | kapandı | Ses yakalamada çöken bir `libwebrtc.dll` sürülmüştü. |

**Bağlam:** plugin her push'ta Windows derlemesi yapıyor ama **çalışma anında hiç test
yok**; `flutter test` yalnızca Linux'ta koşuyor. 116 açık Windows issue'ı var ve son 12
günde üç çökme düzeltmesi çıktı. Bu, portun "çoşkın görünen ama sinsi olan" risk
taşıdığı anlamına gelir — bu protokol bu yüzden formalite değil, kararın dayanağıdır.
