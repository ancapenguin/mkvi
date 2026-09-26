# 0002 — Taşıma mimarisi: kısa ömürlü rendezvous bileti, trickle ICE ve parmak izi SAS

**Tarih:** 2026-09-26
**Durum:** **Öneri.** Bu doküman bir *tasarım* kararıdır; uygulama ayrı ajanlara
verilecek. Kararın kendisi aşağıdaki "Karar" bölümünde tek cümlededir ve
bağlayıcıdır; "Araştırma" ve "Seçenekler" bölümleri onun gerekçesidir.
**Etki:** `app/lib/{session,signaling,chat,transport,security,bridge}/`,
`cloudflare/src/index.ts`, `cloudflare/wrangler.jsonc`, `vectors/wire-v1.json`

> **Bu dosyanın sahibi 0002'dir; 0003 değildir.** Paralel çalışan
> `docs/adr/0003-library-decisions.md` "hangi kütüphane?" sorusunu **kanıtla**
> cevaplar. Bu dosya **mimari kararı** verir: hangi katman alınacak, hangisi
> yazılacak, nerede sınır. İkisi aynı soruya bakar, **iki ayrı dosyaya** bakar.
> Çelişme olursa birleştirmeyi lead yapar. Burada paket adı geçen her yer
> **"hangi katmanın kütüphanesi"** cevabıdır; sürüm, indirme, lisans ve denetim
> kanıtı 0003'ün işidir.
>
> **Kapsam sınırı (2026-09-26'da eklenen kural):** `AGENTS.md` → *"Tekerleği
> yeniden icat etme — yeterince iyi bir kütüphane varsa al."* Bu kural
> aşağıdaki kararın **şeklini** belirlemiştir. ICE, DTLS, DTLS-SRTP, veri
> kanalı SCTP'si ve sıkıştırma **yeniden yazılmayacak**; hepsi
> **`flutter_webrtc` / `libwebrtc`** altında kalacak. Yeniden tasarlanan tek şey
> **sinyalleşme protokolüdür** — ve o, `AGENTS.md`'nin "bizim işimiz" listesinde
> açıkça sayılıyor. Bu ADR'nin her seçeneğinde hangi katmanın tekerlek olduğu
> ayrı bir tabloda gösterilmiştir.

> Bu bir **karar kaydıdır**, kullanım kuvuzu değildir. Yazıldığı gün doğru olan
> betimlemeleri tarihsel olarak korur; bugünün durumu için `ARCHITECTURE.md` ve
> `ROADMAP.md`'ye bakın.
>
> **Bu dokümanı yazan ajan hiçbir test koşmadı, hiçbir cihaz çalıştırmadı ve
> iki makine bağlamadı.** Her şey okumayla ve resmî dokümanla çıkarıldı. Doğrulanamayan
> her şey "**doğrulayamadım**" diye işaretlidir. `docs/manual-test.md` bu dokümandaki
> eşiklerin **ölçüleceği** yerdir; o ölçümler henüz yapılmadı.

## Bağlam — ölçülmüş mevcut durum

### 1. Arayüz envanteri: hangi katman, hangi sözleşme, kimin sahibi var

Aşağıdaki tablo **koddan** çıkarıldı. İmza satırları `dosya:satır`; sahiplik
"hangi katman bu arayüzü *tüketiyor*" demektir.

| Arayüz / tip | İmza | Sahibi (tüketen katman) | `app/lib` içindeki implementasyon |
|---|---|---|---|
| `PeerTransportBinding` | `reconnect_driver.dart:231-242` | `session` (yeniden bağlanma döngüsü) | **YOK** |
| `RendezvousClientFactory` (typedef) | `reconnect_driver.dart:53` | `session` | **YOK** (üretim örneği yok) |
| `PairingVerifier` (typedef) | `identity.dart:18-23` | `session` | **YOK** |
| `PairScopedDeviceIdFactory` (typedef) | `identity.dart:29-30` | `session` | İnşa eden fabrika var (`identity.dart:105`) ama `Sha256Base64Url` kaynağı **yok** |
| `DeviceIdentityLoader` | `identity.dart:54-56` | `session` | **YOK** |
| `PeerStore` | `peer_store.dart:246-252` | `session` (eş kaydı) | **YOK** |
| `LocalSettings` | `local_settings.dart:50-57` | `session` + `settings` | **YOK** |
| `ChatChannelBinding` | `chat_channel.dart:50-62` | `chat` | **YOK** |
| `HistoryStore` | `history_store.dart:122-161` | `chat` | **YOK** |
| `FileSink` | `file_sink.dart:49-74` | `chat` (dosya indirme) | **YOK** |
| `OutgoingFileSource` | `file_sink.dart:82-95` | `chat` (dosya gönderme) | **YOK** |
| `SignalingSocket` | `rendezvous_client.dart:75-96` | `signaling` | **VAR** — `IoSignalingSocket`, `rendezvous_client.dart:105` |
| `SignalingSocketFactory` (typedef) | `rendezvous_client.dart:99` | `signaling` | **VAR** — `defaultSocketFactory`, `:102` |
| `MediaSeams` (paket değeri) | `media_seam.dart:25-50` | `media` | Sınıf var, **`lib/` içinde hiç kurulmuyor** |
| `MediaCapture` | `media_seam.dart:247-276` | `media` | **VAR** — `WebRtcMediaBackend`, `webrtc_media_backend.dart:68` |
| `MediaSenderRegistry` | `media_seam.dart:123-154` | `media` | **VAR** — aynı sınıf, `webrtc_media_backend.dart:68` |
| `MediaStatsProbe` | `media_seam.dart:174-180` | `media` | **VAR** — aynı sınıf, `webrtc_media_backend.dart:68` |
| `MediaTrackHandle` | `media_seam.dart:59-80` | `media` | **VAR** — `_WebrtcTrack`, `webrtc_media_backend.dart:372` |
| `MediaSenderHandle` | `media_seam.dart:83-99` | `media` | **VAR** — `_SenderAdapter`, `webrtc_media_backend.dart:333` |
| `SignatureVerifier` | `update_verifier.dart:197-222` | `update` | Yalnız **her şeyi reddeden** `UnavailableSignatureVerifier`, `:231` |

**Grep ile doğrulama.** `app/lib` altında `implements`/`extends`/`with` araması
sonucu **tam olarak beş üretim sınıfı** verir: `WebRtcMediaBackend` (3 arayüz),
`_SenderAdapter`, `_WebrtcTrack`, `IoSignalingSocket` ve reddeden
`UnavailableSignatureVerifier`. **Dokuz arayüzün üretim implementasyonu
sıfırdır:** `PeerTransportBinding`, `ChatChannelBinding`, `HistoryStore`,
`FileSink`, `OutgoingFileSource`, `PeerStore`, `LocalSettings`,
`DeviceIdentityLoader`, ve `update_verifier.dart:18`'in gelecek için adlandırdığı
`RustSignatureVerifier`.

Aynı arayüzlerin `app/test` altında **otuz altı** sahte implementasyonu var. Bu
demek ki: **on katman test edilebilir biçimde yazıldı, hiçbiri bağlanmadı.**
`app/lib/main.dart` hâlâ `flutter create` şablonu (`MyApp`, `MyHomePage`).

**Köprü de bağlı değil.** `app/pubspec.yaml` `flutter_rust_bridge` **içermiyor**
ve `app/lib` içinde `mkvi_bridge`'e tek bir referans yok (yalnız bir yorumda
geçiyor, `update_verifier.dart:6`). `crates/mkvi_bridge/src/api.rs` dokuz
`tümü senkron` fonksiyon dışa veriyor (`open_core`, `device_public_key`, `sign`,
`verify`, `append_history`, `list_history`, `remember_peer`, `list_peers`) —
`verify_artifact` ve `key_is_legacy` **yok**. Yani `SignatureVerifier`'ın Rust
bağlantısı da 0.3.0'ın ön işidir.

**Sonuç:** 0.3.0'ın taşıma işi bir *iyileştirme* değil, bir **yazım** işidir.
Bu ADR o yazımın hangi şekilde yapılacağını seçer.

### 2. Protokolün bugün hâli (okundu, değiştirilmedi)

`app/lib/core/protocol/peer_protocol.dart`:

| Sabit | Değer | Satır |
|---|---|---|
| `maxMessageBytes` | 32 KiB | `:27` |
| `maxFileBytes` | 512 MB | `:49` |
| `maxConcurrentReceives` | 2 | `:57` |
| `fileChunkBytes` | **16 KiB** | `:79` |
| `fileFlushBytes` | 4 MiB | `:90` |
| `maxSafeInteger` | 2⁵³−1 | `:66` |

512 MB bir DataChannel sınırı **değildir**; MKVI'nin kendi ürün tavanıdır ve
zaten 16 KiB'lık parçalara bölünmüş bir çerçeveyle taşınıyor. Bu, ileride
"512 MB güvenilir mi" sorusuna cevaptır: **tek mesaj olarak güvenilir değil,
zaten parçalı bir protokol olarak güvenilir.**

### 3. Mevcut Cloudflare Worker (tamamı okundu)

`cloudflare/src/index.ts` 244 satır, **sıfır `import`** (üçüncü taraf bağımlılığı
yok), iki Durable Object.

**Yönlendirme** (`:31-53`)

- `GET /health` → `{"ok":true,"service":"mkvi-signal"}`, kimlik doğrulama yok.
- WebSocket yükseltmesi yoksa `426`.
- `/v1/rendezvous?code=<13-16>` → `PAIRING_ROOM.idFromName(code)`. Kod
  `^[A-HJ-NP-Z2-9]{13,16}$` (belirsiz karakter yok).
- `/v1/peer?pair=<43>&device=<43>` → `PEER_RENDEZVOUS.idFromName(pair)`.
- Başka → `404`.

**`PairingRoom` (`:57-112`)** — 15 dakikalık, `server.accept()` ile açılan soketler.

- `clients: Set<WebSocket>` — en fazla **2** canlı soket; üçüncüsü `409`.
- `MAX_ADMISSIONS = 8` (`:28`) — `storage.get("admitted")` her girişte artar,
  `put` edilir. **Bu bir cihaz sayısı değil, bir yeniden deneme bütçesidir**
  (yorum `:20-27` bunu açıkça söylüyor). Sayaç **asla azaltılmaz**, yalnız
  15 dakikalık alarm `delete("admitted")` ile siler (`:86`). Dokuzuncu giriş `409`.
- `setAlarm(Date.now() + 15*60_000)` **her girişte yeniden kurulur** (`:73`) —
  yani pencere kayan değil, kod ilk açıldığı andan itibaren 15 dakika.
- `rateWindows`: bağlantı başına **120 zarf/dakika**; aşılırsa `close(1008)`.
- Zarf boyutu `65_536` bayt; JSON parse hatası `1003`; şemaya uymayan `1008`.
- `isRelayEnvelope` → `isSignalPayload` başarısızsa `close(1008)`.
- `disconnect`/`error` → `broadcast({type:"presence", peers})`.

**`PeerRendezvous` (`:153-243`)** — 30 günlük, `state.acceptWebSocket()` ile
**hibernasyon destekleyen** soketler.

- `PEER_TTL_MS = 30 * 24 * 60 * 60_000` (`:20`), **kayan**: her `fetch` ile
  `expiresAt = now + PEER_TTL_MS` yenilenir.
- `peer-record = { devices: string[], expiresAt }`, en fazla **2** opak cihaz
  tutamacı; üçüncü `403`.
- `for (const socket of this.state.getWebSockets(device)) socket.close(4000, …)`
  → cihaz başına tek canlı soket; yeniden bağlanmak kota **tüketmez**.
- `serializeAttachment({device})` + `acceptWebSocket(server, [device])` — bu
  yüzden hibernasyon mümkün.
- `onlineDevices()` `Set` boyutu; `ready` ve `presence` bildirilir.
- `alarm()` sonu `closeAll(4001)` + `delete`.

**`isSignalPayload` beyaz listesi (`:121-141`)** — anahtar bazında:

| `kind` | Kabul edilen anahtarlar | Ek koşullar |
|---|---|---|
| `offer` / `answer` | **tam olarak 2** (`kind`, `sdp`) | `sdp` string, `0 < len ≤ 32_768` |
| `identity` | alt küme: `kind`, `publicKey`, `signature`, `session` | `KEY_B64` 43, `SIGNATURE_B64` 86, `session` opsiyonel `OPAQUE_ID` 43 |
| `ice` | tam olarak 2 (`kind`, `candidate`) | `candidate` nesne; içinde yalnız `candidate` (≤2048), `sdpMid` (≤64), `sdpMLineIndex` (güvenli tamsayı ≥0), `usernameFragment` (≤256) |

**Reddedilen her şey:** her türlü sohbet, dosya, ek adı, konum, arama sinyali.
`vectors/wire-v1.json` bunu iki tarafta da çalıştırıyor.

**Worker ne saklıyor, ne saklamıyor (TTL'ler dahil) — `cloudflare/README.md` §6:**

| Saklar | Nerede | TTL |
|---|---|---|
| `admitted` (bir tamsayı) + alarm zamanı | `PairingRoom` | 15 dk, sonra `delete` |
| `peer-record`: ≤2 opak cihaz tutamacı + `expiresAt` | `PeerRendezvous` | 30 gün kayan, sonra `delete` |

Saklamaz: mesaj, dosya, medya, anahtar, veritabanı, kullanıcı adı.
Geçici **görür** (bellekten geçer, diske yazılmaz): açık anahtarlar, SDP ve
**her iki tarafın** IP adresleri + portları (ICE adayları).

**Mimariye itirazım (gerekçeli, ölçülmüş):**

1. **Kimlik Worker'dan geçiyor ve Worker'a hiçbir şey katmıyor.** `identity`
   zarfı taşınan tek şeydir ve Worker onu *aynen* iletir. Yani Worker'ın
   varlığı kimliğe hiçbir değer katmıyor, sadece **görünürlük** katıyor.
2. **`PeerRendezvous` sunucuda 30 günlük bir eş kaydı tutuyor** ve bu kayıt
   **istemciye hiçbir şey söylemiyor** — iki cihaz zaten birbirinin varlığını
   bu kayıt olmadan da bilir. Kayıt tek işi "aynı `pair` capability'sine sahip
   iki soketi aynı yere yönlendirmek"; bunun için 30 gün değil, **oturum
   ömrü** yeter.
3. **Bütün kurulum tek bir kullanım için iki ayrı protokol sürümü taşıyor.**
   `identity.dart:71-84` hem `mkvi/discover/v1/<id>` hem `mkvi/discover/v2/<id>/<session>`
   transcript'ini destekliyor ve `session` alanı opsiyonel. Yani **hiçbir 0.1.x
   istemcisi kalmadığı halde** (0.1.x 2026-09-26'da silindi, `AGENTS.md` ve
   `ROADMAP.md`) geriye dönük uyum hâlâ tel şemasında yaşıyor.
4. **`PairingRoom` maliyeti yapısal olarak yüksek.** `server.accept()` kullanıyor,
   yani WebSocket Standart API'si. Cloudflare'ın kendi dokümanına göre
   hibernasyon **ancak** "WebSocket standart API'si kullanılmıyorsa" mümkün —
   yani bu oda hiçbir zaman ücretsiz olamaz, açık kaldığı sürece süre yazar.
5. **Worker önünde istek sayısı sınırı yok.** `cloudflare/README.md` §5 bunu
   kendisi söylüyor: "eşleşme sayısı sınırı vardır ama **istek sayısı sınırı
   yoktur**." Kimlik doğrulaması yok, yalnız biçim doğrulaması var; herhangi bir
   anonim istemci geçerli biçimli bir kodla **DO örneği oluşturabilir**.

**Sonuç: 0.3.0 için bu mimariyi olduğu gibi korumak doğru değil.** Çünkü
korunan şey üç şeydir ve hiçbiri kullanıcıya görünür bir değer vermiyor:
bir geliştirici dostu olmayan 30 günlük sunucu kaydı, ölmüş bir geriye dönük
uyum yükü ve tavan maliyeti.

### 4. Katman haritası: tekerlek nerede, iş nerede

> Bu bölüm `AGENTS.md`'nin **"Tekerleği yeniden icat etme"** kuralının bu
> ADR'deki karşılığıdır. Kural şunu der: *"DTLS'yi, ICE'yi, DTLS-SRTP'yi, bir
> dosya biçimini, bir sıkıştırma algoritmasını veya bir veritabanı motorunu
> kendi başımıza yazmayız."* Aşağıdaki tablo o cümlenin **hangi satıra**
> uygulandığını gösterir.
>
> **Sütun anlamı:** "Paket" sütunu **kanıtlanmış** isimdir. "Tür" sütunu
> `AGENTS.md`'deki ikisinden hangisi olduğunu söyler: **tekerlek** (aldık) ya da
> **bizim işimiz** (`AGENTS.md`: "Sinyalleşme protokolü, eşleştirme akışı, çağrı
> durum makinesi, arayüz durumu").

#### 4a. Alınan tekerlekler — bu ADR'de **hiçbiri** yeniden yazılmıyor

| Katman | Paket | Sürüm / kanıt | Bu katman neyi bizim elimizden alıyor |
|---|---|---|---|
| ICE (aday toplama, NAT geçişi, yeniden başlatma) | **`flutter_webrtc`** → `libwebrtc` | 1.6.2+hotfix.3 — pub.dev, 15 Eyl 2026 | `restartIce()`, aday toplama, host/srflx adayları |
| DTLS el sıkışması + **sertifika parmak izi** | **`libwebrtc`** (aynı paketin içinde) | aynı | `a=fingerprint:sha-256 …` üretimi ve el sıkışması |
| DTLS-SRTP (medya şifreleme) | **`libwebrtc`** | aynı | SRTP anahtar türetme ve şifreleme — MKVI'de **hiçbir satır** |
| DataChannel / SCTP | **`libwebrtc`** | aynı | `createDataChannel`, sıralılık, güvenilirlik, kısmi teslim |
| Codec (Opus/VP8/H.264) | **`libwebrtc`** (dahili) | aynı | kodek seçimi, bit hızı uyarlaması |
| Kamera + mikrofon yakalama | **`flutter_webrtc`** | aynı | Windows'ta Media Foundation + WASAPI |
| Ekran yakalama | **`flutter_webrtc`** | aynı | Windows'ta DXGI (`#2137` kusuru bu katmanda) |
| Veritabanı motoru | **`rusqlite`** (SQLite, `bundled`) | 0.32 — `mkvi_core/Cargo.toml` | SQL, WAL, sayfa yönetimi |
| Asimetrik kimlik | **`ed25519-dalek`** | 2.1 — aynı | Ed25519 imza/doğrulama |
| Geçmiş şifreleme | **`chacha20poly1305`** | 0.10 — aynı | XChaCha20-Poly1305 AEAD |
| Yayın imzası doğrulama | **`minisign-verify`** | 0.3 — aynı | minisign `Ed`/`ED` ayrımı |
| Anahtar kasası | **`keyring`** | 3.6, platform arka uçları **açıkça seçiliyor** | Windows DPAPI · macOS Keychain · Linux Secret Service |
| Bellek temizleme | **`zeroize`** | 1 — aynı | Anahtar materyalinin yığını silmesi |
| Rastgelelik | **`rand_core`** + `getrandom` | 0.6 — aynı | CSPRNG |
| Base64 | **`base64`** | 0.22 — aynı | `STANDARD_NO_PAD` / URL güvenli |
| Dart ↔ Rust köprüsü | **`flutter_rust_bridge`** | `=2.13.0` **sabit** (`mkvi_bridge/Cargo.toml`) | FFI, kod üretimi, sürüm uyumu |
| Uygulama veri dizini | **`path_provider`** | 2.1.5 — `app/pubspec.yaml` | `getApplicationSupportDirectory` |
| Android anahtar kasası | **`flutter_secure_storage`** | 11.2.0 — aynı | `keyring`'in Android'de **olmadığının** karşılığı |
| Update feed indirme | **`http`** | 1.2.0 — aynı | HTTP/2, yönlendirme, TLS |
| Sinyal WebSocket'i | **`dart:io` `WebSocket`** | Dart SDK — harici paket **değil** | `IoSignalingSocket`, `rendezvous_client.dart:105` |
| Sinyal sunucusu çalışma zamanı | **Cloudflare Workers + Durable Objects** | Cloudflare ürünü | WebSocket barındırma, hibernasyon, alarm |
| Sıkıştırma (ileride gerekirse) | **`dart:io` `GZipCodec` / `ZLibCodec`** | Dart SDK'da hazır | Kütüphane zaten elde; **elle sıkıştırma yazılmaz** |

#### 4b. Bizim işimiz — `AGENTS.md`'nin "yalnız kendi işimiz olan katmanda el yaz" listesi

| Katman | Nerede | Neden bizim |
|---|---|---|
| Sinyalleşme protokolü (zarf şeması, beyaz liste, transcript) | `app/lib/signaling/` + `cloudflare/src/index.ts` | `AGENTS.md` açıkça sayıyor |
| Eşleştirme akışı (kod girişi, bilet, SAS onayı) | `app/lib/ui/pairing/` + `session` | `AGENTS.md` açıkça sayıyor |
| Çağrı durum makinesi | `app/lib/call/call_machine.dart` (704 satır, 110 test) | `AGENTS.md` açıkça sayıyor |
| Arayüz durumu (yeniden bağlanma döngüsü, timeline, bildirim) | `app/lib/session/`, `chat/`, `ui/notice/` | `AGENTS.md` açıkça sayıyor |
| Tel üstü çerçeveleme (16 KiB parça, kontrol mesajı) | `app/lib/core/protocol/peer_protocol.dart` | MKVI'nin kendi sözleşmesi, `vectors/wire-v1.json` |
| Rol seçimi (`isInitiator`) | `app/lib/session/identity.dart:109-118` | Deterministik, iki tarafta aynı — sunucuya danışmaz |
| Worker rota kodu + DO sınıfları | `cloudflare/src/index.ts` | Sunucu MKVI'nin kendi kodu |

#### 4c. Karma katman — dikkat gerektiren üç yer

Bunlar ne tam tekerlek ne tam bizim işimiz. **Her biri için paket adı yazılmıştır**;
"bir kütüphane" diye bırakılmamıştır.

| Yer | Kütüphaneden gelen | Bizim yazdığımız | Not |
|---|---|---|---|
| **DTLS parmak izi → SAS ifadesi** | `libwebrtc` parmak izi üretir (okuma bizim değil) | SHA-256 karıştırma + **Crockford Base32** kodlaması | ⚠️ **SHA-256 henüz bağımlılık değil** — `mkvi_core/Cargo.toml`'da `sha2` **yok** (ölçüldü). Bu kural gereği **`sha2` (RustCrypto) eklenmeli, elle SHA-256 yazılmamalı.** Base32 için `0003` paket kararı vermeli |
| **`pair` capability türetme** | `identity.dart:105` `Sha256Base64Url` fabrikası **var** | — | ⚠️ Fabrikanın **kullandığı `Sha256Base64Url` kaynağı yok** (ölçüldü, `Bağlam` §1). Yani türetme de `sha2`'ye bağlı |
| **Dosya aktarımı** | SCTP sıralılığı (`libwebrtc`) + `dart:io` yazma | 16 KiB çerçeve, `bufferedAmountLow` geri basıncı, kısa yazma | Sıkıştırma **yok**; eklenirse `dart:io` `GZipCodec` (4a) — el yazımı değil |

**Kuralın bu ADR'ye etkisi, tek cümledir:** Seçenek (c) "sinyalleşmeyi
yeniden tasarla" der; **bunu ICE, DTLS, DTLS-SRTP, SCTP veya WebRTC'yi
yeniden yazmadan yapar.** `flutter_webrtc` altında kalır. (c)'te yeniden
tasarlanan tek şey `SignalPayload`'ın zarf şemasıdır — ve o, `AGENTS.md`'nin
"bizim işimiz" listesinin ilk maddesidir.

## Araştırma — güncel durum, kaynaklarıyla

> Her satır ya **resmî dokümandan** ya da **bu depoda ölçülmüş koddan** gelir.
> Kaynağı olmayan hiçbir iddia "doğrulayamadım" ile işaretlenmiştir.

### A. Cloudflare Durable Objects, 2026 itibarıyla

**Limitler** — [developers.cloudflare.com/durable-objects/platform/limits](https://developers.cloudflare.com/durable-objects/platform/limits)
(sayfa "Last updated Jun 1, 2026"):

- SQLite-backed DO; nesne başına **10 GB**; anahtar+değer **≤ 2 MB**.
- **WebSocket mesaj boyutu 32 MiB** (yalnız alınan mesajlar için).
- İstek başına CPU: 30 sn varsayılan, `limits.cpu_ms` ile 5 dakikaya kadar.
- Sınıf sayısı: Paid 500 / Free 100. Free'de hesap başına depolama 5 GB.
- Nesne sayısı: sınırsız.

**Fiyatlandırma** — [platform/pricing](https://developers.cloudflare.com/durable-objects/platform/pricing)
("Last updated Aug 25, 2026"):

| | Free | Paid |
|---|---|---|
| İstek | **100.000 / gün** | 1M / ay + $0.15/M |
| Süre (GB-s) | **13.000 / gün** | 400.000 / ay + $12.50/M |

Kritik cümle: *"Durable Objects are billed for compute duration (wall-clock time)
while the Durable Object is actively running **or is idle in memory but unable
to hibernate**. Durable Objects that are idle and eligible for hibernation are
not billed for duration."* Ayrıca istek sayımı **WebSocket mesajlarını da
kapsar**.

**WebSocket API'leri** — [best-practices/websockets](https://developers.cloudflare.com/durable-objects/best-practices/websockets)
("Last updated Jun 19, 2026"):

1. **Hibernation WebSocket API** — `state.acceptWebSocket(ws)`; dokümanda
   **"(recommended)"** olarak etiketli.
2. **Web Standard WebSocket API** — `ws.accept()` + `addEventListener`.

Hibernasyon koşulları (aynı sayfa + [lifecycle](https://developers.cloudflare.com/durable-objects/concepts/durable-object-lifecycle)):

- `setTimeout`/`setInterval` yok, uçuşta `fetch()` yok, **WebSocket standart API'si
  kullanılmıyor**, işlenmekte olan olay yok, açık giden TCP/WS bağlantısı yok.
- 10 saniye hareketsizlikten sonra hibernasyon.
- Hibernasyon **olmazsa** nesne 70–140 saniye hareketsizlikten sonra bellekten
  tamamen atılır.
- Hibernasyon sırasında WebSocket istemcileri **bağlı kalır**; bellekteki durum
  sıfırlanır, `serializeAttachment`/`deserializeAttachment` ile geri gelir.
- DO başına **32.768** WebSocket bağlantısı ([api/state](https://developers.cloudflare.com/durable-objects/api/state)).

**Alarm doğruluğu** — [api/alarms](https://developers.cloudflare.com/durable-objects/api/alarms/)
("Last updated Apr 21, 2026"):

- DO başına **tek** alarm; `setAlarm` yeniden kurar.
- *"Alarms have guaranteed **at-least-once** execution"* ve `alarm()` handler'ı
  exception attığında **2 saniyeden başlayan üstel geri çekilmeyle, en fazla 6
  kez** yeniden denenir. `alarmInfo` `{retryCount, isRetry}` verir.
- **Doküman zamanında çalışma vaadi vermiyor.** "At-least-once" + retry demek
  "15. dakikada kapandı" değil, "15. dakikadan *sonra* bir noktada kapandı"
  demektir. `PairingRoom`'un 15 dakikalık penceresi bu yüzden **tavan değil,
  taban** garantisi.

**2026'da iki değişiklik — ve biri geri dönüşsüz kapı:**

- [Changelog, 9 Tem 2026](https://developers.cloudflare.com/changelog/product/durable-objects):
  *"New Durable Object namespaces must use the SQLite storage backend."* Yeni
  DO'lar KV arka ucu kullanamaz.
- [Changelog, 4 Tem 2026](https://developers.cloudflare.com/changelog/product/durable-objects):
  `exports` ile **bildirimsel** DO sınıf bildirimi (wrangler 4.107.0'de GA).
  `exports` ve `migrations` aynı Worker içinde **mutually exclusive**.
  [workers-sdk#14614](https://github.com/cloudflare/workers-sdk/issues/14614):
  `exports` akışından `migrations`'a **dönüş API 100403 ile yasaklanıyor**, yani
  bu **tek yönlü bir kapı**. `cloudflare/wrangler.jsonc` bugün hâlâ `migrations`
  kullanıyor (`wrangler.jsonc:12-15`). MKVI sınıf silme/yeniden adlandırma
  yapacaksa bu kapıdan geçmek zorunda — ve geçtikten sonra geri dönemez.
  **Bu bir tarihli karardır ve Uygulama sırası'nda konuşulmuştur.**

**Alternatifler — hangisi daha doğru?**

| Aday | Neden uygun / neden değil |
|---|---|
| **DO + Hibernation API** | İki soketi buluşturmak + "şu anda odada kim var" için hâlâ en doğru araç. Bellekte tutulan şey oda üyeliği, ki bu *koordinasyon* durumudur — depolama değil. Tek yönlü `exports` kapısı bedeli var. |
| **Workers KV** | **[Uygun değil — ölçüldü.](https://developers.cloudflare.com/kv/platform/limits)** Free: **1.000 yazma/gün**, "farklı anahtarlara" 100.000 okuma/gün, `minimum cacheTtl 30 saniye`. Eşleşme başına bir yazma demektir; günlük 1.000 eşleşmeliğinin üstü tutulamaz. Ayrıca "aynı anahtara 1 yazma/sn" ve **asenkron** (eventual) okuma, "kim bağlı" sorusuna yanıt vermeye uygun değil. |
| **D1** | Sorgulanabilir, ucuz, ama **bağlantı canlılığı** kavramı yok. 2 saniyelik bir ölüm sayacını doğru tutmak için sürekli yazmak gerekir; bu DO'nun yaptığı işin pahalı ve yanlış kopyası. |
| **R2** | Nesne deposası. Buluşma için değil, **dosya aktarımı için** doğru araç — ama MKVI'nin mimari sözü "sunucu içerik taşımaz", dolayısıyla R2 **kapsam dışı** (bkz. Reddedilenler). |
| **Queues** | 10.000 operasyon/gün (Free). Asenkron kuyruk; **düşük gecikmeli** SDP/ICE geçişi için yanlış araç (zarlar sıraya girip bekler). |
| **Workers Rate Limiting binding** | [Var](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) ve **doğru yerinde**: Worker'ın kendi içinde olmayan tek koruma bu yüzden kenarda. Ücretsiz planın **en ucuz** kullanımı: her gelen istek sayılmaz, yalnız sınır aşanlar için iş yapılır. **Mevcut Worker'da yok** — bu bir açık. |
| **"realtime"/callbacks" Workers ürünü** | Araştırdım: Cloudflare'ın Workers tarafında "realtime" adlı ayrı bir ürün, WebSocket yönlendirmesi için bir Durable Object değiştiricisi **bulamadım**. `ctx.exports` (4 Tem 2026) DO sınıf bildiriminin bildirimsel hâli; "callbacks" adı altında bir DO-alternative ürünü **doğrulayamadım**. Bu noktaya dayanan bir tasarım önerisi yapmıyorum. |

**Sonuç: DO kalsın, ama (i) her ikisi de **hibernating** olsun, (ii) eşleşme
durumu **oturum ömrüne** inen bir bilete olsun, (iii) Worker'a **doğrulanmış**
bir istek sınırı eklensin.**

**Doğrulama: `AGENTS.md`'daki maliyet sayısı resmî formülle tutuyor.** Bu,
bu oturumda ölçüldü ve `AGENTS.md`'deki "~115 GB-s / ~110 eşleşme gün"
tahmininin **doğru** olduğunu gösteriyor — ama yalnızca Free plan için:

```
900 sn (15 dk) × 128 MB = 115.200 MB = 112,5 GB-s   ← bir PairingRoom
13.000 GB-s/gün ÷ 112,5 GB-s = 115,5 eşleşme/gün     ← Free süre kotası
```

Kaynaklar: fiyat tablosu ve *"Duration billing charges for the 128 MB of memory
your Durable Object is allocated, regardless of actual usage"* dipnotu →
[platform/pricing](https://developers.cloudflare.com/durable-objects/platform/pricing)
("Last updated Aug 25, 2026"). `server.accept()` kullanan bir oda bağlantı
boyunca uyanık sayılır — aynı sayfa: *"Calling `accept()` on a WebSocket in an
Object will incur duration charges for the entire time the WebSocket is
connected"* — yani 15 dakikanın tamamı yazılır.

**Sonuç: `AGENTS.md`'nin sayısı kaynaklıdır ve doğrudur; ayrıca "tahmin"
değil, iki resmî sayının çarpımıdır.** Aynı hesap `PeerRendezvous` için geçerli
değildir — o sınıf `state.acceptWebSocket()` kullandığı için bağlantı boyunca
yazılmaz; kayan 30 günlük TTL yalnız *alarm anında* uyanık tutar.

> ⚠️ **Hibernasyon için bir uyarı, ölçülmemiş.** Aynı dokümanda *"Events such as
> alarms, incoming requests, and scheduled callbacks prevent hibernation"* yazıyor.
> `PairingRoom` `setAlarm` kuruyor (`index.ts:73`). Alarmın *planlanmış olması*
> hibernasyonu engelliyor mu, yoksa yalnız *çalıştığı an* mı engelliyor, bu
> oturumda **doğrulayamadım** — [lifecycle](https://developers.cloudflare.com/durable-objects/concepts/durable-object-lifecycle/)
> sayfasını ayrıntılı okumadım. Bu yüzden "hibernasyona geçince eşleşme günlüğü
> sınırsızlaşır" iddiası **bu ADR'de yapılmıyor**; ölçülecek bir madde olarak
> kabul kriterlerine girdi (bkz. A9).

**Cloudflare TURN/STUN hizmeti var — bu, "MKVI TURN sağlamaz" sözünü
tartışmaya açıyor.** [developers.cloudflare.com/realtime/turn](https://developers.cloudflare.com/realtime/turn/)
("Last updated Sep 25, 2026"):

| | Adres / Port |
|---|---|
| STUN / UDP | `stun.cloudflare.com:3478` |
| TURN / UDP | `turn.cloudflare.com:3478` **ve** `:443` |
| TURN / TCP | `turn.cloudflare.com:3478` **ve** `:80` |
| TURN / TLS | `turn.cloudflare.com:5349` **ve** `:443` |

- **Fiyat:** *"available free of charge when used together with the Realtime
  SFU. Otherwise, it costs **$0.05/real-time GB outbound**."* Yani MKVI'nin
  "kimseye hizmet vermeyiz" ilkesiyle **çelişir**: ücretsiz değil.
- **Coğrafya:** anycast ile otomatik en yakın lokasyon; **Çin ağı hariç**
  (*"with the notable exception of the Cloudflare's China Network"*). 40 ülke
  varsayımındaki ağlar eşit değildir.
- **Limitler (her tahsis için):** >5 yeni IP/sn, >5–10 kpps, >50–100 Mbps.

**Karar:** `mkvi.iceServers` **boş kalır** (bugünkü hâli —
`connection_settings.dart:128` `iceServersText = ''`, ölçüldü) ve MKVI
Cloudflare TURN'ü **varsayılan yapmaz**. Fakat bu artık "bulunamadı" değil,
**"bilerek reddedildi"** olur ve `SECURITY.md`'ye böyle yazılmalıdır. Kullanıcı
isterse `turn.cloudflare.com` satırını kendi yazar. Bu, `Bağlam` §1'de ölçülen
"hiçbir şey `iceServers`'ı yapılandırmaya geçirmiyor" boşluğunu kapatır —
kapatmanın yolu yeni bir paket değil, **zaten var olan ayarı bağlamaktır.**

### B. WebRTC signalling için endüstri standardı

**Perfect negotiation hâlâ öneriliyor mu?** Evet —
[MDN, "The WebRTC perfect negotiation pattern"](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Perfect_negotiation)
(sayfa "Last modified Jul 13, 2026"): *"introduces a WebRTC perfect negotiation
pattern, describing how it works and why it is the recommended way to negotiate
a WebRTC connection"*. Kural: **polite** taraf bir offer çakışmasında kendi
offer'ını **ICE rollback** ile geri alır; **impolite** taraf çakışmayı görmezden
geler.

**`rollback` bugün `flutter_webrtc`'de çalışıyor mu? Hayır. Ölçüldü:**

- [flutter-webrtc#625 "Perfect negotiation"](https://github.com/flutter-webrtc/flutter-webrtc/issues/625)
  — 9 Tem 2021'de açılmış, **durumu hâlâ `Open`**, atanan kişi yok, etiket yok.
- Sabitlenen sürümün C++ katmanında: `grep -n 'RTCSdpType|rollback|certificate|fingerprint'`
  `flutter_webrtc-1.6.2+hotfix.3/common/cpp/src/*.cc` → **1 eşleşme**, ve o
  eşleşme bile ilgisiz (`flutter_webrtc_base.cc:361`:
  `// FIXME: certificates of type sequence<RTCCertificate> (public API)`).
  **`rollback` için sıfır.**
- Tarayıcı tarafında `setRemoteDescription({type:'rollback'})` yıllardır var
  (Chromium issue 40634696; WPT `RTCPeerConnection-setRemoteDescription-rollback`
  beklenti dosyası PASS). Sorun tarayıcıda değil, Flutter köprüsünde.

**`flutter_webrtc`'de perfect negotiation'a alternatif desen var mı?**
Var, ve MKVI zaten onu kullanıyor: **müzakere etmeyen tek seferlik el sıkışma.**
`MediaSenderRegistry.open()` (`media_seam.dart:123-140`) bağlantı başına **üç
transceiver'ı `sendrecv` olarak bir kez** yaratır ve hiçbir medya yöntemi
transceiver eklemez/çıkarmaz. Kamera açmak, ekran paylaşımı başlatmak, ikisini
de kapatmak — hepsi `replaceTrack` çağrısıdır, **offer gerektirmez.** Dolayısıyla
**glare penceresi yoktur** ve perfect negotiation'a ihtiyaç yoktur.
`WebRtcMediaBackend.open()` (`webrtc_media_backend.dart:110-140`) bunu zaten
uyguluyor. `MediaController` müzakere sayacını 1'de tutuyor; bu, iddianın
testle okunabilir hâli.

**Rol nasıl belirlenecek?** Mevcut `isInitiator()`
(`identity.dart:109-118`) iki açık anahtarı UTF-16 kod birimiyle karşılaştırıp
`compareTo < 0` diyor. İki taraf aynı iki anahtardan **aynı cevabı** çıkarır,
tek bir "rol alışverişi" zarfa gerek kalmaz. Bu, perfect negotiation'ın
"polite/impolite" rolünün yerine geçen daha basit ve daha güvenli bir kuraldır:
**sunucu, karşı tarafın kim olduğunu bilmeden bile iki taraf da aynı sonuca varır.**

**Unbundled vs unified plan?** pub.dev özellik matrisi
([flutter_webrtc](https://pub.dev/packages/flutter_webrtc)) altı platformun
altısında da **Unified-Plan ✔️** işaretliyor (Android, iOS, Web, macOS, Windows,
Linux). **Bu noktada Chromium'ın Plan-B'yi ne zaman kaldırdığına dair bir birincil
kaynağı bu oturumda doğrulayamadım** — yalnız plugin'ın altı platformda unified
plan bildirdiğini ölçebildim. Pratik sonuç aynı: MKVI için bu bir seçenek değil.

**DTLS-SRTP parmak izi: en güvenilir yol hangisi?**

- **Şartname yolu var.** [W3C webrtc-stats](https://w3c.github.io/webrtc-stats/)
  `RTCCertificateStats`'ı tanımlar: `fingerprint` (RFC 4572 §5 biçiminde)
  ve `fingerprintAlgorithm` (örn. `sha-256`). Erişim yolu: `pc.getStats()` →
  `type === 'certificate'` girdisi. [MDN RTCCertificateStats](https://developer.mozilla.org/en-US/docs/Web/API/RTCCertificateStats)
  bunu doğruluyor.
- **Ama `flutter_webrtc` için "çalışıyor mu" olduğunu doğrulayamadım.** Ölçebildiğim:
  `getStats()` libwebrtc'nin ham `MediaRTCStats` raporlarını **olduğu gibi**
  geçiriyor (`flutter_peerconnection.cc:1074-1142`, `statsToMap(...)`); stat
  türlerini filtreleyen hiçbir katman yok. Yani bir `certificate` girdisi
  *varsa* Dart'a ulaşır — ama **bunda paketlenmiş libwebrtc sürümünün üretip
  üretmediği ancak gerçek cihazda ölçülebilir.** İşte bu, `docs/adr/0001`
  içindeki "Karar kuralı"nın **2. sorusunun** ("SDP parmak izi `getStats` parmak
  iziyle aynı mı") tam olarak ölçtüğü şeydir ve **ölçülmemiştir**.
- **SDP yolu her zaman çalışır ve RFC'e dayanır.** `a=fingerprint:sha-256 XX:…`
  satırı, el sıkışmanın *doğrulanacağı* değerin ta kendisidir
  (RFC 8122 §5 / RFC 4572). **Karar: SAS'yı SDP'den üret, `getStats()`'ı yalnız
  çapraz doğrulama olarak kullan, yoksa eğer varsa.** `getStats()` bir gün
  `certificate` üretmezse tasarım bozulmaz; tersi doğru olsaydı bozulurdu.
- **Önemli kısıt:** `webrtc_interface-1.5.1/lib/src/rtc_configuration.dart`
  **tamamen yorum satırı** (52 satırın hepsi `//`). Yani uygulama
  `RTCConfiguration` sağlayamıyor; plugin yapılandırmayı `Map<String, dynamic>`
  olarak alıyor. Bunun sonucu: **uygulama kendi kendine imzalı bir DTLS
  sertifikası üretemez** (`sequence<RTCCertificate>` FIXME'si bunun da
  karşılığı). Yani parmak izi sabitleme **otomatik üretilen** sertifika
  üzerinden yapılacak; kimlik hâlâ **Ed25519 transcript doğrulamasından** gelecek.
  Bu iki mekanizmanın **ayrı** olduğu ve ADR'ye öyle yazıldığı önemlidir.

**ICE, trickle, yeniden başlatma.**

- [W3C WebRTC Önerisi, 13 Mart 2025](https://www.w3.org/TR/webrtc/):
  *"Performing an ICE restart is recommended when `iceConnectionState` transitions
  to `failed`."*
- `restartIce()` **mevcut**: `webrtc_interface-1.5.1/lib/src/rtc_peerconnection.dart:93`
  ve `flutter_webrtc-1.6.2+hotfix.3/lib/src/native/rtc_peerconnection_impl.dart:539-547`.
- `iceTransportPolicy` alanı `webrtc_interface`'te **yorumda** (bkz. yukarıdaki
  kısıt); pratikte yapılandırma `createPeerConnection({'iceServers': [...]})`
  haritasıyla geçirilir. `LocalSettings` zaten `mkvi.iceServers` anahtarını
  tanımlıyor (`local_settings.dart:26`) ve `saveEndpointAndIce` onu yazıyor
  (`:76-87`) — **ama hiçbir şey onu okuyup bir yapılandırmaya geçirmiyor.**
- `mid` kullanımı: `sdpMid` zarf beyaz listesinde (`signal_payload.dart:213-230`).
  Doğru kural: **gelen adayda `sdpMid` öncelikli**, `sdpMLineIndex` yalnız
  `sdpMid` yoksa. Transceiver sırası bir uygulama ayrıntısıdır, güvence değildir.

**NAT traversal: STUN/TURN ne zaman zorunlu?**

- [RFC 8656 (TURN)](https://www.rfc-editor.org/rfc/rfc8656.html): *"it is best to
  use a TURN server only when a direct communication path cannot be found"* ve
  *"hosted by the TURN server … comes at a high cost to the provider"*.
- [RFC 8835 §](https://www.rfc-editor.org/rfc/rfc8835.pdf) WebRTC taşımaları için:
  *"In order to deal with situations where both parties are behind NATs of the
  type that perform endpoint-dependent mapping, **TURN be supported**."* Yani
  simetrik NAT'ın **her iki tarafta** birden olması TURN'suz çözümsüzdür.
- **MKVI'nin ürün gerçekliği:** kullanıcı sayısı iki (kullanıcı + kuzen). Konut
  bağlantısı senaryosunda STUN çoğu zaman yeter. Kurumsal ağ / VPN / simetrik
  NAT senaryosunda **bağlantı kurulamaz ve TURN olmadan kurulamaz.**
  Yaygın kaynaklarda "bağlantıların %20–30'u TURN ister" gibi sayılar
  dolaşıyor; **bunlar resmî olmayan, ölçülmemiş tahminlerdir ve MKVI için
  ölçülmüş bir sayı değildir.** Kaydedilen gerçek: MKVI hiçbir TURN sunucusu
  sağlamaz ve **sağlayamaz**; kullanıcı kendi TURN'ünü `mkvi.iceServers` ile
  yazacaktır. Bu, ürünün "iki kişi arasında" sınırının doğal sonucudur ve
  `SECURITY.md`'ye "bilinen sınır" olarak yazılmalıdır.

**DataChannel `binaryType` ve 512 MB — ölçülmüş sonuç:**

- `webrtc_interface-1.5.1/lib/src/rtc_data_channel.dart:11` `String binaryType = 'text'`
  diyor, ama `toMap()` (`:14-25`) **`binaryType`'ı haritaya koymuyor.**
- `flutter_webrtc-1.6.2+hotfix.3/common/cpp/src/*.cc` içinde
  `grep 'binaryType|binary_type'` → **sıfır eşleşme.**
  **Sonuç: `binaryType` alanı ölü bir alandır; hiçbir yere gitmiyor.**
- **Ama pratik davranış güvenli, ve sebebi ilginç:** gelen mesajın türü
  **zarf başına** native tarafta belirleniyor — `flutter_data_channel.cc:142-153`,
  `OnMessage(const char* buffer, int length, bool binary)`. Yani karşı taraf
  ikili mesaj gönderdiyse Dart'ta `MessageType.binary` olarak gelir; uygulamanın
  `binaryType` ayarlamasına **gerek yoktur.**
- **Kural: `binaryType`'a asla güvenme. Dosya parçalarını
  `RTCDataChannelMessage.fromBinary(...)` ile gönder.** Metin kanalı native'de
  `EncodableValue(std::string)` olarak geçer ve UTF-8 doğrulanır
  (`flutter_utf8_sanitize.cc`); ikili olmayan bir dosya parçası bozulabilir.
- **512 MB güvenilir mi?** Tek mesaj olarak hayır; **zaten öyle taşınmıyor.**
  `fileChunkBytes = 16 KiB` (`peer_protocol.dart:79`) + `maxMessageBytes = 32 KiB`
  + `fileFlushBytes = 4 MiB` mevcut. SCTP mesaj sınırı bu ölçekte sorun değil.
  Güvenilirliği belirleyen şey kanal değil, **chunk'lı çerçeve + kısa yazma
  (`FileSink.write` bayt sayısı döndürür, `file_sink.dart:61-67`) +
  `bufferedAmountLow` geri basıncı + `maxConcurrentReceives = 2`.**

- **512 MB bir DataChannel sınırı değildir; bu yanlış inanış nereden geliyor?**
  `maxFileBytes = 512 MB` bir **ürün kararıdır** (tavan), protokol sınırı değil.
  Gerçek sınırlar çok daha küçük ve dağınıktır:
  WebRTC şartnamesi §6.6 güvenli olmak için **16 KiB** önerir; Chromium'un
  **alıcı** sınırı 256 KiB'ye çıkarıldı
  ([lgrahl.de, Chromium issue 7774](https://bugs.chromium.org/p/webrtc/issues/detail?id=7774));
  Firefox `sctp.maxMessageSize` ile daha yüksek değerler bildirebilir. Yani
  **tarayıcıdan tarayıcıya değişen, pazarlık edilen bir sınır var** ve
  `a=max-message-size` SDP'den okunur. MKVI'nin mevcut 16 KiB parçası tam olarak
  şartnamenin önerdiği değerdir; **bu bir tesadüf değil, doğru seçimdir ve
  değiştirilmemelidir.** `0003`'e not: "dosya boyutu tavanı" ile "DataChannel mesaj sınırı" farklı şeylerdir — `maxFileBytes` bir ürün kararıdır, protokol sınırı değildir.
  
  

**`flutter_webrtc` paket sağlığı — kuralın 2. sorusu (özet; tam denetim `0003`'te).**
Kaynak: [pub.dev/packages/flutter_webrtc](https://pub.dev/packages/flutter_webrtc),
bu oturumda okundu.

| Soru | Cevap |
|---|---|
| **1. İşi yapıyor mu?** | Evet. Yayınlanmış sürüm **1.6.2+hotfix.3**, **15 Eyl 2026** (brifing tarihinde 11 gün önce). `app/pubspec.yaml`'daki `^1.6.2` güncel. |
| **2. Bakım kim yapıyor?** | **Doğrulanmış yayıncı** `flutter-webrtc.org`. 306k indirme, 1,36k beğeni, **160 pub puanı**. Haftalık indirme grafiği sayfada ayrı bir widget olarak çiziliyor — **sayıyı okuyamadım, iddia etmiyorum.** |
| **3. Denetim / lisans?** | **MIT.** Bağımlılıklar: `dart_webrtc ^1.8.0`, `webrtc_interface ^1.5.1`, `collection`, `logger`, `path_provider`, `web`. |
| **4. Doğru mu bildiğimiz?** | Kısmen. **Doğru:** Data Channel ✔️, Screen Capture ✔️, Unified-Plan ✔️ — altı platformun altısında da; `restartIce()` API'de **gerçekten var** (pub.dev API belgeleri, `RTCPeerConnection.restartIce()`). **Yanlış/eksik:** `rollback` **yok** (#625); `binaryType` ölü alan; `RTCConfiguration` sınıfı yorumda. |

> **`restartIce()` API'de var — ama davranışı ölçülmedi.** Var olması, ICE
> restart'ın `flutter_webrtc` altında **çalıştığı** anlamına gelmez: yeniden
> aday toplama tetikleniyor mu, `onIceCandidate` yeniden ateşleniyor mu, bilinmiyor.
> Bu yüzden kabul kriterlerinde **"ICE `failed` → `restartIce()` → yeniden
> bağlanır"** bir *kabul* değil bir *ölçüm* maddesidir (A8), ve `0001`'in karar
> kuralına bağlanmıştır.

## Seçenekler

> Üçü de farklı; ikisi de "mevcut kodu koru" değil.

### Seçenek (a) — Mevcut ikiliyi koru, eksik taşımayı yaz

**Özet.** `PairingRoom` + `PeerRendezvous` aynen kalır, `isSignalPayload` aynen
kalır, `identity` zarfı aynen kalır. Yazılan tek şey dokuz sahipsiz arayüzün
üretim implementasyonu: `PeerTransportBinding` (peer connection + data channel),
`ChatChannelBinding`, `FileSink`, `OutgoingFileSource`, `LocalSettings`, sonra
`flutter_rust_bridge` ile `DeviceIdentityLoader` / `PeerStore` / `HistoryStore` /
`RustSignatureVerifier`.

**Güvenlik modeli.** Kriptografik olarak doğrulanan: her iki tarafın Ed25519
imzası `mkvi/discover/v2/<id>/<session>` transcript'i üzerinde yerel olarak
doğrulanıyor (`reconnect_driver.dart:696-752`). **Doğrulanmayan:** DTLS parmak
izi ifadeye bağlı değil (`SECURITY.md` §"DTLS parmak izi doğrulaması — bağlanmadı").
Worker açık anahtarı, imzayı ve **iki tarafın IP'lerini** görüyor ve kalıcı bir
30 günlük eş kaydı tutuyor. Faz 4'ün açık maddesi **kapanmaz.**

**Bağlantı güvenilirliği.** `ReconnectDriver`'ın geri çekilme döngüsü
(700 ms → 12 sn), epoch sayacı ve `_superseded` ayrımı **bu seçenekte
kullanılabilir ve test edilmiş bir varlık.** Hata durumları: soket açılmaz
→ `ReconnectConnectFailed`; kimlik okunamaz → `ReconnectIdentityUnavailable`
(yeniden denenir); imza geçersiz → `ReconnectPeerUnverified` + soket kapatma;
kanal açılmaz → `ReconnectConnectFailed`. Hepsi **yeniden denenir**, hiçbiri
döngüyü öldüremez — bu, `reconnect_driver.dart:80-94`'te bir sınıf dokümanı olarak
yazılı.

**NAT geçiş başarısızlığı.** `iceServers` bugün **hiçbir yere geçirilmiyor**;
STUN listesi kullanıcıdan gelse bile bağlantı kurulumuna girmiyor. Yani bu
seçenekte NAT geçişi **bugünkü haliyle aynı**: varsayılan STUN, kurumsal ağda
sessiz başarısızlık. Düzeltmek bu seçeneğin kapsamı dışında kalır.

**Bakım maliyeti.** 10 katman, ~0 yeni dosya, **0 yeni bağımlılık**, Worker'da
0 değişiklik. En düşük.

**Hangi katman kütüphane, hangi katman bizim?**

| Katman | Sahibi | Paket / yer |
|---|---|---|
| ICE, DTLS, DTLS-SRTP, SCTP, DataChannel | **kütüphane** | `flutter_webrtc` → `libwebrtc` |
| Kamera / mikrofon / ekran yakalama | **kütüphane** | `flutter_webrtc` (MF · WASAPI · DXGI) |
| `RTCPeerConnection` + `createDataChannel` + aday aktarımı | **bizim** (çağrı düzeni) | yeni `app/lib/transport/peer_transport.dart` — API'yi `libwebrtc` verir, **düzeni biz kurarız** |
| Sinyalleşme zarf şeması | **bizim** | `app/lib/signaling/signal_payload.dart` (değişmez) |
| Veritabanı, kripto, anahtar kasası | **kütüphane** | `rusqlite` · `ed25519-dalek` · `chacha20poly1305` · `keyring` |
| Kimlik / eş kaydı / geçmiş | **kütüphane** (Rust çekirdek) | `mkvi_core` + `flutter_rust_bridge` |
| Çağrı durum makinesi, arayüz durumu | **bizim** | `app/lib/call/`, `session/`, `ui/` |
| Worker DO sınıfları | **bizim** | `cloudflare/src/index.ts` (bu seçenekte **değişmez**) |
| **Yeni tekerlek** | — | **yok** |

> (a)'nın "0 yeni bağımlılık" iddiası tekerlek kuralıyla **tutarlıdır** ve bu
> yüzden (a)'ya karşı olan itirazım yeni bağımlılık değil, **güvenlik açığının
> açık kalmasıdır.**

**Flutter'da uygulanabilirlik.** Yüksek. `flutter_webrtc`'in ihtiyaç duyduğu
her şey (`RTCPeerConnection`, `RTCDataChannel`, `addTransceiver`,
`replaceTrack`, `restartIce`) mevcut. `rollback` **gerekmiyor** — çünkü (a)
seçeneği de mevcut "tek seferlik, üç transceiver'lı müzakere" tasarımını korur.

**Ne kazanıyoruz / ne kaybediyoruz (0.1.x'e göre).** Kazanılan: ilk çalışan
P2P taşıma, `vectors/wire-v1.json` tek tarafta ama hâlâ geçerli, Worker'a
hiç dokunulmaz. Kaybedilen: Faz 4 açık kalır; Worker'daki 30 günlük kayıt
kalır; "güvenli sunucu" vaadi bir varsayılan adresle (`local_settings.dart:14-15`,
resmî geliştiricinin `workers.dev` adresi!) çelişmeye devam eder.

---

### Seçenek (b) — Cloudflare **yalnız eşleşme** için, sonrası sunucu tamamen devre dışı

**Özet.** Eşleşme bir kez Cloudflare'da olur, `PeerRendezvous` **tamamen
silinir**, `PairingRoom` da silinir. Eşleşmeden sonra hiçbir MKVI sunucusu
devrede değildir. Yeniden bağlanma, iki cihazın yerelde türettiği bir
`pair` capability'siyle **herkese açık bir STUN/keşif hizmeti** üzerinden
yapılır.

**Güvenlik modeli.** Eşleşmeden sonra sunucu tarafı neredeyse sıfırlanır:
yalnız STUN, iki tarafın IP'sini görür ve içerik taşımaz. **Ancak** DTLS parmak
izi SAS'ı yine zorunludur, çünkü bir araya giren kişi iki ayrı DTLS oturumu
açıp iki parmak izi göstermek zorundadır. Kimlik yine Ed25519'ten gelir.

**Bağlantı güvenilirliği.** Yeniden bağlanma **çöker.** Eş, ağını değiştirdiğinde
(eski IP, yeni NAT eşlemesi) karşı cihazın onu *bulması* için bir rendezvous
noktası gerekir. Yerelde türetilen `pair` capability'si bir **adres** değildir.
Bu seçenek, ürünün ana vaadini ("Windows'ta iki cihaz kurulumdan sonra **bir
kez** kod girer, **bir daha asla girmez**", `ROADMAP.md` §Hedef) doğrudan ihlal
eder: yeniden bağlanma başarısız olduğunda kullanıcıdan **yeniden kod** istenir.

**NAT geçiş başarısızlığı.** STUN tarafı (b)'de de aynı. Ek olarak: keşif için
herkese açık bir hizmet kullanılıyorsa bu hizmet MKVI'nin "varsayılan sunucu
gömülmez, kimseye hizmet vermeyiz" ilkesini ihlal eder; kullanıcı kendi
Worker'ını kurarsa keşif yine kendi Worker'ı olur ve (b) pratikte (c)'ye
dönüşür.

**Bakım maliyeti.** Katman sayısı en az görünen, ama **en çok gizli bağımlılığı**
var: üçüncü taraf bir STUN/keşif hizmeti, sürümlenmeyen ve MKVI'nın kontrolünde
olmayan bir bileşen. `SECURITY.md` §"Kendi sunucunu kurma ilkesi" ile çelişir.

**Hangi katman kütüphane, hangi katman bizim?**

| Katman | Sahibi | Paket / yer |
|---|---|---|
| ICE, DTLS, DTLS-SRTP, SCTP, DataChannel | **kütüphane** | `flutter_webrtc` → `libwebrtc` |
| **STUN** (aday toplama) | **kütüphane** | `libwebrtc` — *hizmet* tarafı üçüncü taraf |
| **Keşif / buluşma (eşleşmeden sonra)** | ⚠️ **tekerlek değil — dışarıdan hizmet** | MKVI dışında, sürümlenmiyor, denetlenmiyor |
| Kamera / mikrofon / ekran | **kütüphane** | `flutter_webrtc` |
| Sinyalleşme zarf şeması | **bizim** | `app/lib/signaling/` |
| DTLS parmak izi → SAS | **kütüphane** (`libwebrtc` parmak izi) + **bizim** (türetme) | ⚠️ `sha2` henüz bağımlılık değil — bkz. §4c |
| Veritabanı, kripto, anahtar kasası | **kütüphane** | `rusqlite` · `ed25519-dalek` · `chacha20poly1305` · `keyring` |
| Worker DO sınıfları | **bizim** | `cloudflare/src/index.ts` — bu seçenekte **silinir** |
| **Yeni tekerlek** | — | **yok** — ama (b)'nin asıl riski zaten tekerlek değil |

> (b)'de tekerlek kuralına uyum sorunu **yok**; sorun şudur: (b) tekerleği
> almaz, tekerleğin **özellikle TURN/STUN kısmını** üçüncü tarafa devreder ve
> denetimimiz dışına çıkarır. Kural bunu yasaklamaz; **ürün vaadi** yasaklar.

**Flutter'da uygulanabilirlik.** Yüksek, ama `iceServers` dışarıdan geldiği için
`RTCConfiguration` yorumdaki sınıf yerine `Map<String, dynamic>` geçirmek gerekir
(ölçüldü: `webrtc_interface-1.5.1/lib/src/rtc_configuration.dart` tamamen yorum).

**Ne kazanıyoruz / ne kaybediyoruz.** Kazanılan: Worker'daki kalıcı durum
**sıfıra** iner. Kaybedilen: yeniden bağlanma; kullanıcı deneyimi; "sunucu
içerik taşımaz" vaadi daha da güçlenir ama **bağlantı kurulabilirliği** düşer.

---

### Seçenek (c) — Kısa ömürlü bilet + trickle ICE + parmak izi SAS (önerilen)

**Özet.** Üç parça değişir:

1. **Eşleşme, tek kullanımlık, kısa ömürlü bir bilet üzerinden.** Kullanıcı
   13 karakterlik kodu girer → Worker `POST /v1/ticket` → Worker **128 bit rastgele**
   bir `r` üretir, `ticket:{expiresAt}` yazar, `wss://…/r/<r>` döner. **Kod artık
   bir Durable Object anahtarı değildir.** İki cihaz aynı bilete bağlanır, iki
   taraflı **imzalı** teklif/cevap ve trickle ICE aktarılır, bilet 10 dakika
   sonunda kendiliğinden yok olur. **Sunucuda kalıcı eş kaydı yoktur.**
2. **Kimlik Worker'dan hiç geçmez.** Eşleşme bittiğinde iki taraf birbirinin
   Ed25519 açık anahtarını **şifreli `PeerStore`'da** zaten tutar. Yeniden
   bağlanmada Worker'a giden şey: `pair` capability'si ile alınan **yeni bir
   bilet** ve o bilet üzerinden `{offer|answer|ice|bye}`. Uzun ömürlü gizli
   **telden hiç çıkmaz.** Teklif/cevap, `mkvi/connect/v1/<nonce>/<hash>`
   transcript'i üzerinde cihazın Ed25519 imzasını taşır; karşı taraf imzayı
   **zaten bildiği** açık anahtarla doğrular. `identity` zarfı **kaldırılır**.
3. **Glare yok, perfect negotiation yok.** `isInitiator()` (`identity.dart:109-118`)
   tek teklifçiyi belirler; üç transceiver bir kez yaratılır
   (`media_seam.dart:123-140`); `rollback`'e hiç ihtiyaç duyulmaz.

**Güvenlik modeli.** Kriptografik olarak doğrulanana ek olarak: **DTLS parmak
izi SAS'ı ifadeye bağlanır** (Faz 4 kapanır). Doğrulanmayana: kullanıcının
ifadeyi gerçekten karşılaştırması (insan varsayımı, aşağıda kayıtlı).

**Bağlantı güvenilirliği.** `ReconnectDriver`'ın geri çekilme döngüsü **korunur**
ve üstüne şunlar eklenir: `iceConnectionState == 'disconnected'` → **sessiz
bekleme penceresi** (Wi-Fi/mobil flap'leri `disconnected` üretir; hemen
sökmek yanlış alarm); `== 'failed'` → `restartIce()` (W3C önerisi), belli bir
pencerede başarısız olursa epoch'un sökülmesi → yeni bilet → yeniden katılım.
`PeerRendezvous`'un "cihaz başına tek canlı soket" davranışı (`:182`) bilete
taşınır: yeni bağlantı eskisini kapatır.

**NAT geçiş başarısızlığı.** `mkvi.iceServers` ayarı **ilk kez gerçekten
bağlantı kurulumuna girer.** Varsayılan: STUN listesi (kullanıcı yazar).
TURN: kullanıcının kendi sunucusu; MKVI sağlamaz. Kurumsal ağda bağlantı
**sessizce değil, açık bir Türkçe mesajla** başarısız olur ("bu ağ doğrudan
bağlantıya izin vermiyor").

**Bakım maliyeti.** Worker tarafı **küçülür** (2 DO sınıfı → 1, kalıcı durum →
10 dakikalık tek bilet). Dart tarafı **büyür**: yeni `app/lib/transport/`,
yeni `app/lib/security/fingerprint_sas.dart`, yeni `app/lib/bridge/`. Bağımlılık:
`flutter_rust_bridge` + `mkvi_bridge` (zaten var, sadece `pubspec.yaml`'a girecek);
`LocalSettings` için **yeni bağımlılık yok** — `path_provider` zaten bağımlı,
küçük bir JSON dosyası yeter.

**Hangi katman kütüphane, hangi katman bizim?**

| Katman | Sahibi | Paket / yer | (c) bunu **değiştiriyor mu?** |
|---|---|---|---|
| **ICE** (aday toplama, NAT geçişi) | **kütüphane** | `flutter_webrtc` → `libwebrtc` | ❌ **Hayır — kesinlikle hayır** |
| **DTLS** el sıkışması | **kütüphane** | `libwebrtc` | ❌ **Hayır** |
| **DTLS-SRTP** medya şifreleme | **kütüphane** | `libwebrtc` | ❌ **Hayır** |
| **SCTP / DataChannel** | **kütüphane** | `libwebrtc` | ❌ **Hayır** |
| Codec (Opus/VP8/H.264) | **kütüphane** | `libwebrtc` (dahili) | ❌ **Hayır** |
| Kamera / mikrofon / ekran | **kütüphane** | `flutter_webrtc` (MF · WASAPI · DXGI) | ❌ **Hayır** |
| Sıkıştırma (varsa) | **kütüphane** | `dart:io` `GZipCodec` | ❌ **Hayır** |
| Veritabanı motoru | **kütüphane** | `rusqlite` (bundled SQLite) | ❌ **Hayır** |
| Ed25519 · XChaCha20-Poly1305 · minisign | **kütüphane** | `ed25519-dalek` · `chacha20poly1305` · `minisign-verify` | ❌ **Hayır** |
| Anahtar kasası | **kütüphane** | `keyring` (+ `flutter_secure_storage`, Android) | ❌ **Hayır** |
| **DTLS parmak izi** (okuma) | **kütüphane** | `libwebrtc` (`a=fingerprint:`) | ✅ değiştirilmez, **tüketilir** |
| **Parmak izi → SAS** (SHA-256 + Crockford B32) | **bizim** | `app/lib/security/fingerprint_sas.dart`; hash için **`sha2` (RustCrypto) eklenmeli** | ✅ **yeni** — bkz. §4c |
| **Sinyalleşme zarf şeması** | **bizim** | `app/lib/signaling/signal_payload.dart` | ✅ **yeniden tasarlanan tek şey** |
| **Bilet ömrü / rol seçimi / transcript** | **bizim** | `identity.dart`, `rendezvous_client.dart`, `cloudflare/src/index.ts` | ✅ **yeni** |
| Çağrı durum makinesi | **bizim** | `app/lib/call/call_machine.dart` | ❌ değişmez |
| Arayüz durumu | **bizim** | `session/`, `chat/`, `ui/` | ❌ değişmez |
| Worker DO sınıfları + rota | **bizim** | `cloudflare/src/index.ts` | ✅ 2 sınıf → 1, `identity` zarfı çıkar |
| **Yeni tekerlek** | — | **`sha2` (RustCrypto) — tek yeni bağımlılık.** `sha2` için dört soru `0003`'te yanıtlanır | |

> **(c) neyi yeniden yazmaz — açık liste.** `AGENTS.md`'nin tekerlek kuralı
> 2026-09-26'da eklendi ve (c)'yi doğrudan bağlıyor. (c) "sinyalleşmeyi yeniden
> tasarla" der; **aşağıdakilerin hiçbiri (c)'nin kapsamında değildir ve
> değiştirilmesi teklif edilmemelidir:**
>
> - ICE'yi / STUN-TURN'ü **kendi yazmak** — `libwebrtc` zaten yapıyor.
> - DTLS el sıkışmasını veya parmak izi üretimini **kendi yazmak** —
>   `libwebrtc` zaten üretiyor; MKVI yalnız **okuyor**.
> - DTLS-SRTP'yi veya bir medya şifresini **kendi yazmak** — `AGENTS.md`'nin
>   "özel kripto yazma" kuralı bunu zaten yasaklıyor.
> - SCTP'yi / güvenilirliği / sıralamayı **kendi yazmak** — `libwebrtc` yapıyor.
> - Sıkıştırmayı **kendi yazmak** — `dart:io` `GZipCodec` hazır.
> - Veritabanı motorunu **kendi yazmak** — `rusqlite` hazır.
>
> (c)'nin eline aldığı tek yeni kriptografik bağımlılık **`sha2`**'dır ve o
> **tek bir satır** iş içindir: parmak izinden SAS ifadesi türetmek. Elle
> SHA-256 yazmak bu ADR'in önerdiği bir şey **değildir** — aksine reddettiği şeydir.

**Flutter'da uygulanabilirlik.** Yüksek ve **kanıtlanmış yollara dayanıyor**:
`RTCPeerConnection`, `RTCDataChannel`, `addTransceiver`, `replaceTrack`,
`restartIce()` hepsi ölçülmüş olarak mevcut. Kullanılmayacak tek özellik
`rollback` — ve kullanılmaması bir tasarım tercihi, bir eksik değil.
**Kırıcı yer:** `RTCConfiguration` sınıfı yorumda; yapılandırma
`Map<String, dynamic>` olarak geçirilecek. Bu, `WebRtcMediaBackend`'un zaten
yaptığı şeyle aynı desen (`webrtc_media_backend.dart:19-26`).

**Ne kazanıyoruz / ne kaybediyoruz (0.1.x'e göre).** Kazanılan: sunucu durumu
30 günden 10 dakikaya; Worker önündeki istek sayısı sınırı var; DTLS parmak izi
ifadeye bağlı; `identity` zarfı kalktığı için sunucu **hiçbir uzun ömürlü
kimlik malzemesi** görmüyor; 0.1.x geriye uyum yükü kalkıyor. Kaybedilen:
`isSignalPayload`'dan iki alan (`identity`'in tamamı, `session`) **daralıyor** —
bu, `AGENTS.md`'deki "protokolü daraltmak kırıcıdır" kuralına bir istisnadır ve
**gerekçesi bu ADR'dir**: kural kırıcıydı *çünkü* 0.1.x istemcileri vardı; onlar
2026-09-26'da silindi ve iki kullanıcı da yeni sürümü elle kuracak
(`ROADMAP.md` §"2026-09-26 — 0.1.x Tauri hattı emekliye ayrıldı").

## Karar

> **0.3.0, Seçenek (c) ile ilerler:** Cloudflare Durable Object **bir** sınıfa
> iner (`RendezvousRoom`, hibernating) ve **oturum ömürlü, tek kullanımlık
> biletler** üretir; kimlik (`identity` zarfı) Worker'dan tamamen kaldırılır ve
> teklif/cevap cihazın Ed25519 imzasıyla taşınır; bağlantı **tek seferlik,
> üç transceiver'lı** bir müzakereyle kurulur (glare yok, `rollback` yok);
> SAS ifadesi **DTLS sertifika parmak izlerinden** türetilir ve `ROADMAP.md`
> Faz 4'teki açık madde böylece kapanır; iki kimlik/şifreleme mekanizması
> ayrı ayrı korunur (Ed25519 transcript doğrulaması **ve** parmak izi).

**Gerekçe, maddeler halinde:**

1. **Korunacak tek şey korunur.** `ReconnectDriver` (`reconnect_driver.dart`),
   `MediaSenderRegistry`'nin "müzakere etmeyen üç transceiver" tasarımı
   (`media_seam.dart:123-140`), `isSignalPayload`'ın beyaz liste fikri
   (`index.ts:121-141`), 16 KiB parçalı dosya çerçevesi
   (`peer_protocol.dart:79`) ve `vectors/wire-v1.json` altındaki iki canlı
   kusur sözleşmesi. Hiçbiri atılmıyor.
2. **Atılacak tek şey, kullanıcıya değer vermeyen şeydir.** 30 günlük
   `PeerRendezvous` kaydı iki cihaza hiçbir şey söylemiyor; o cihazlar birbirini
   zaten biliyor. 30 gün, oturum ömrüyle değiştirilebilir.
3. **Açık güvenlik maddesi kapanır.** `SECURITY.md` §1 ve `ROADMAP.md` Faz 4'te
   açık duran DTLS parmak izi bağı, (c)'de mimari bir adım değil bir
   **zincirleme** adımdır: parmak izi `localDescription.sdp`'den okunur → iki
   tarafın parmak izi SHA-256 ile karıştırılıp aynı kısa ifadeye indirgenir →
   ifade **yalnız bağlantı `connected` olduktan sonra** gösterilir.
4. **Sunucunun görevi daraltılır, kullanıcı direktifi birebir uygulanır.**
   "Cloudflare'ın görevi cihazları buluşturmak; mesaj içeriğini depolamak
   değil." (c) bunu şu ankinden daha da daraltır: sunucu artık **kimliği de**
   depolamaz ve **kalıcı eş kaydı da** tutmaz.
5. **Bakım maliyeti düşer, ürün riski düşer.** (a) en ucuzdur ama bilinen
   en büyük güvenlik açığını açık bırakır; (b) en az sunucu yükü taşır ama
   ürünün ana vaadini (bir kez kod) ihlal eder. (c) ikisinin ortasıdır ve tek
   vaadi ihlal etmez.
6. **Eldeki kanıt bunu seçmeyi zorunlu kılıyor.** `rollback`'in
   `flutter_webrtc`'de **hâlâ olmadığı** ölçüldü (#625 açık; C++'da sıfır
   eşleşme). Bu yüzden perfect negotiation tabanlı **hiçbir** seçenek
   kabul edilemez. (c) tek seferlik müzakereyle glare'i yapısal olarak
   ortadan kaldırdığı için bu eksikten **bağımsızdır.**

## Güvenlik varsayımları

KIRK dört göz kuralı: **aşağıdaki listede hiçbir varsayım tek başına doğru
değildir; doğruluk zincirinin tamamı boyunca tutulmalıdır.** Her satır "hangi
varsayım hangi kodu kırıyor" ve "hangi bilgi varsayımı kırıyor" biçimindedir.

| # | Varsayım | Hangi kodu kırar | Hangi bilgi kırar | Durum / karşı önlem |
|---|---|---|---|---|
| 1 | "Sinyalleşme sunucusu dürüsttür" | Hiçbir kodu kırmaz — varsayım zaten yapılmıyor | — | **Tasarlanarak elendi.** (c)'de sunucu bilet üretip iletir; doğrulama iki tarafta yereldir. |
| 2 | "Sunucu içerik taşıyamaz" | `cloudflare/src/index.ts:121-141` (`isSignalPayload`) — beyaz listeye bir anahtar eklemek Worker'ı tünele çevirir | Sunucunun taşıdığı her bayt | **Korunuyor ve daraltılıyor.** Karşı önlem: `vectors/wire-v1.json`'ın `forbiddenKeys` listesi + Dart aynası (`signal_payload.dart:185-236`) + yeni anahtar eklendiğinde kırmızıya düşen test. |
| 3 | "Sunucu, aynı eşin iki oturumunu ilişkilendiremez" | (c)'nin yeni bilet rotası; `?pair=` capability'si her yeniden bağlanmada telde görünürse ilişkilendirme mümkün olur | Sunucunun gördüğü zaman damgaları ve aynı IP çiftleri | **Yeni gereksinim.** Uzun ömürlü `pair` capability'si **hiçbir zaman URL'ye girmeyecek**; yalnız 128 bit'lik, 10 dakikalık bilet giracak. |
| 4 | "Sunucu iki cihazı birbirine bağlayamaz / DTLS'i kıramaz" | **Bugün yanlış.** `SECURITY.md` §1, `ROADMAP.md` Faz 4 | Sunucunun gösterdiği iki ayrı parmak izi | (c) ile kapanıyor: parmak izi ifadeye bağlanıyor ve ifade yalnız `connected` sonrası gösteriliyor. |
| 5 | "Kullanıcı ifadeyi gerçekten karşılaştırır" | Eşleşme/verifikasyon ekranı; onay düğmesi otomatik kabul edemez | — | **İnsan varsayımı, burada açıkça yazılıdır.** Karşı önlem: `connected` olmadan ifade gösterilmez, onay **açık bir eylem** olmalı, "eşleşmiyor" durumunda eşleşme iptal edilebilir olmalı. Bu olmadan 2–4 arasındaki hiçbir zincir işe yaramaz. |
| 6 | "Sunucu önünde istek sınırı yoktur" kabul edilebilir değil | `index.ts:37-41` — herhangi bir anonim istemci geçerli biçimli kodla **DO örneği oluşturabilir** | Saldırganın hesabın kotasını tüketme isteği | (c)'de kod DO anahtarı **değildir**; bilet önce `POST /v1/ticket` ile alınır ve o uç **Workers rate limiting binding** ile sınırlanır. Ayrıca `wrangler.jsonc`'ye binding eklenir. |
| 7 | "Depolanan eş açık anahtarı karşı tarafın gerçek anahtarıdır" | Eşleşme akışı — bir MITM iki farklı anahtar sunabilir | `PeerStore`'daki kayıt | (c)'de **parmak izi ilk bağlantıda `PeerStore`'a çivilenir**; sonraki bağlantılarda aynı parmak izi görülmezse bağlantı reddedilir. Anahtar değişimi = yeniden eşleşme. |
| 8 | "512 MB'ı tek bir DataChannel mesajı olarak taşıyoruz" | `FileSink` / `OutgoingFileSource` uygulaması | — | (c)'de taşımıyoruz: 16 KiB parça + kısa yazma + `bufferedAmountLow` + `maxConcurrentReceives = 2` (`peer_protocol.dart:57,79`). |
| 9 | "`binaryType` ayarlanıyor" | — | — | **Yanlış varsayım, ölçüldü ve elendi.** `toMap()`'e girmiyor, C++'da sıfır eşleşme. Yerine: her zaman `fromBinary(...)`. |
| 10 | "Alarm 15. dakikada çalar" | `setAlarm` (`index.ts:73,178`) | — | **Yanlış varsayım.** Alarm "at-least-once" + en fazla 6 retry; zamanında çalışma garantisi yok. Bu yüzden bilet TTL'i **kendi kendine doğrulanan** olmalı: `expiresAt` alanı zaten `PeerRendezvous`'ta öyle yazılmış (`:166,177`) — bilet de aynı kalıbı kullanacak, yani geç bir alarm **kota dışı bırakmayacak.** |
| 11 | "Oda/nesne yalnız eşleşme sırasında ayaktadır" | `PairingRoom`'un `server.accept()` kullanımı | Hesabın GB-s kotası | (c)'de **her iki DO da hibernating**; boşta süre yazılmaz. |
| 12 | "Sunucu eşleri tanımlayamaz" | İki tarafın aynı Worker'dan bilet alması | Zamanlama korelasyonu | **Dürüst sınır olarak kabul ediliyor.** Sunucu iki biletin aynı IP'den, yakın zamanlarda geldiğini görebilir. `SECURITY.md`'ye "gizlilik değil, ilişkilendirme yüzeyi" notu düşülmeli. |

**`SECURITY.md` ile tutarlılık.** (c) uygulanırsa `SECURITY.md`'nin üç yeri
güncellenmek zorundadır: §"Sunucu içerik taşımaz" tablosu (kalıcı satır
kalkar), §"DTLS parmak izi doğrulaması — bağlanmadı" (kapanır) ve
§"Kendi sunucunu kurma ilkesi" (bilet kavramı). Bu ADR, `SECURITY.md`'yi
**kendisi değiştirmez**; değişikliyi uygulama ajanı yapar.

**DTLS parmak izi — ROADMAP Faz 4'ün nasıl kapanır (algoritma).**

```
fpL = SHA-256( yerel DTLS sertifikası )        ← localDescription.sdp'deki a=fingerprint:
fpR = karşı tarafın bildirdiği parmak izi      ← remoteDescription.sdp'deki a=fingerprint:
mix  = SHA-256( min(fpL,fpR) || max(fpL,fpR) ) ← sıralama iki tarafta aynı olsun
sas  = Crockford tabanında 40 bit (8 karakter) ← iki tarafta da aynı
```

Gösterim **yalnız** `connectionState == 'connected'` olduktan sonra. Çünkü
el sıkışma tamamlanmadan DTLS'in hangi sertifikayla biteceğini bilmiyoruz.
`getStats()` bir `certificate` girdisi verirse aynı SAS'ı **doğrulamak** için
kullanılır; vermezse SAS yine üretilir (SDP yeterli). Bu, `docs/adr/0001`
"Karar kuralı"nın 2. sorusunu ("SDP parmak izi ≡ `getStats` parmak izi") bir
**sonuca değil, bir ölçüme** bağlar: doğrulanmasa da mimari çalışır.

**Neden bu, "sunucunun korsanlığı ifadeyi değiştiremez" hedefini kapatır.**
Korsan iki tarafı da kendi arkasına alıp iki ayrı DTLS oturumu açmak zorundadır
(bir tarafa kendi anahtarıyla imza atamaz — açık anahtar `PeerStore`'da sabittir
ve sunucu onu değiştiremez). İki ayrı oturum = iki ayrı sertifika = iki ayrı
parmak izi = **farklı SAS**. Tek oturum yapabilirse (tek sertifika ile iki tarafa
da DTLS el sıkışması yapmak) `identity` transcript doğrulaması onu durdurur:
imza, `mkvi/connect/v1/<nonce>/<hash>` üzerine atılır ve `hash` karşı tarafın
**gerçek** açık anahtarından türetilir. İki ayrı engel, birbirinin yerine
geçmez — zincir budur.

## Kabul kriterleri

> Her satır **test edilebilir**. "Çalışıyor" bir kabul kriteri değildir.

> ### ⚠️ Kriter yazma kuralı (2026-09-26'da eklendi)
>
> **Hiçbir kabul kriteri "el yazımız doğru çalışıyor" diyemez.** Bu, `AGENTS.md`'nin
> tekerlek kuralının ölçülebilir hâlidir ve şu anlama gelir:
>
> - Bir kriterin konusu **kriptografik bütünlük, şifreleme, sıkıştırma,
>   sıralılık/güvenilirlik, veri bütünlüğü, ya da bir dosya/veri biçimi** ise,
>   o katman ya **zaten bir kütüphane** kullanır — kriter o kütüphanenin
>   **yerleşik** davranışını ölçer — ya da kriter **"bu katman bize ait
>   değil"** diye işaretlenir ve kabul listesinden **çıkarılır**.
> - MKVI'ye düşen kriterler yalnızca **düzen, akış ve eşleştirme** üzerine
>   olabilir: "doğru sırada gönderildi", "eşleşmediğinde reddetti", "sessizce
>   donmadı, Türkçe mesaj verdi".
> - **MKVI'nin yazdığı kodun doğruluğunu kanıtlamak** kriterin konusu
>   **olamaz** — çünkü o zaman kriter "ben doğru yazdım" demek olur. Bunun
>   yerine kriter **"kütüphane X'in sözleşmesi Y'yi verdi"** biçiminde yazılır.
>
> Aşağıdaki **§0** bu ayrımın kaydını tutar; her yeni kriter ya bu tablaya ya
> da "bizim" listesine girer.

### 0. "Bu katman bize ait değil" kaydı

Bu katmanların **doğruluğu MKVI'nin kabul kriteri değildir.** Kırmızıya
düşmeleri MKVI'nin hatası değildir; yine de **kayıt altındadır** çünkü
`docs/manual-test.md` bunları günlük denemede gözlemlenecek.

| Katman | Sahibi | MKVI'nin kabulü |
|---|---|---|
| ICE aday toplama / NAT geçişi | `libwebrtc` | ❌ **değil** — yalnız *gözlenir*: bağlantı kuruldu mu (S3/S4/S5) |
| DTLS el sıkışması | `libwebrtc` | ❌ **değil** — yalnız parmak izi *okunur* |
| DTLS-SRTP şifreleme | `libwebrtc` | ❌ **değil** — sıfır satır MKVI kodu |
| SCTP sıralılık / güvenilirlik | `libwebrtc` | ❌ **değil** |
| SHA-256 | **`sha2` (RustCrypto)** | ❌ **değil** — `sha2`'nin test vektörleri kastedir |
| Base32 (Crockford) | 0003'ün kararı | ❌ **değil** — paketin test vektörleri kastedir |
| Ed25519 · XChaCha20-Poly1305 · minisign | `ed25519-dalek` · `chacha20poly1305` · `minisign-verify` | ❌ **değil** — `mkvi_core` testleri kastedir |
| Codec / bit hızı uyarlaması | `libwebrtc` | ❌ **değil** |
| Ekran yakalama başarısı (#2137) | `flutter_webrtc` | ⚠️ **yarı** — plugin **hatasız boş track** veriyor; **MKVI'nin işi** bunu tespit edip kullanıcıya göstermek (S11) |
| SQLite | `rusqlite` | ❌ **değil** |
| Hibernasyon / alarm | Cloudflare DO | ❌ **değil** — yalnız *maliyet* ölçülür (A9) |

### 1. Katman → arayüz → sahiplik

| Arayüz | Kim implement edecek | Nerede | Ölçüm |
|---|---|---|---|
| `PeerTransportBinding` | `app/lib/transport/peer_transport.dart` | `session` tarafından tüketilir, `transport` yazar | Sınıf `implements PeerTransportBinding` |
| `ChatChannelBinding` | `app/lib/transport/datachannel_channel.dart` | `chat` | idem |
| `FileSink` | `app/lib/bridge/io_file_sink.dart` | `chat` | idem |
| `OutgoingFileSource` | `app/lib/bridge/io_outgoing_file.dart` | `chat` | idem |
| `HistoryStore` | `app/lib/bridge/core_history_store.dart` | `chat` | idem |
| `PeerStore` | `app/lib/bridge/core_peer_store.dart` | `session` | idem |
| `DeviceIdentityLoader` | `app/lib/bridge/core_identity_loader.dart` | `session` | idem |
| `LocalSettings` | `app/lib/settings/file_local_settings.dart` | `session`+`settings` | idem + **0 yeni paket** (`path_provider` zaten bağımlı) |
| `SignatureVerifier` | `app/lib/bridge/core_signature_verifier.dart` | `update` | idem + `UnavailableSignatureVerifier` `app/lib`'den **silinir** |
| DTLS parmak izi → SAS | `app/lib/security/fingerprint_sas.dart` | yeni | Saf fonksiyon; **hash için `sha2` (RustCrypto) çağrılır, elle hash yazılmaz** — kriter A8 |

**Kabul:** `grep -rl "package:flutter_webrtc" app/lib` **tam olarak 2 dosya**
 döndürür: `app/lib/media/webrtc_media_backend.dart` ve
`app/lib/transport/webrtc_peer_connection.dart`. Üçüncüsü kapıyı kırmızıya
 döndürür (bir dikiş, iki yer).

> **Bu grep tekerlek kuralının da kapısıdır.** `flutter_webrtc`'e yalnız bu iki
> dosya dokunur; yani **WebRTC yığını tek bir dikişten geçer.** `app/lib`
> altına üçüncü bir `import package:flutter_webrtc` girerse iki şeyden biri
> bozulmuş demektir: ya katman sınırı kaymıştır, ya da tekerlek yerine ikinci
> bir yol yazılmaya başlanmıştır. İkisi de reddedilir.

### 2. Otomatik kapılar

| # | Kriter | Eşik |
|---|---|---|
| A1 | `vectors/wire-v1.json` yeni zarfı Dart ve vitest tarafında **aynı dosyadan** çalıştırır | yeşil |
| A2 | `isSignalPayload`'a `identity` veya `session` geri eklenirse test kırmızıya döner | kırmızı |
| A3 | `exports` geçişinden sonra Worker dry-run (`npm run check`) yeşil | yeşil |
| A4 | `MediaController` müzakere sayacı `open()` sonrası **ve** 10 dakika sonra hâlâ `1` | `== 1` |
| A5 | Hata ayrımı: `ReconnectEndpointUnusable` / `ReconnectIdentityUnavailable` / `ReconnectPeerUnverified` / `ReconnectConnectFailed` — her biri **yeniden denenir** ve döngüyü bitirmez | mevcut testler yeşil kalır |
| A6 | 2 saatlik soak: **sıfır** işlenmemiş Dart istisnası, sıfır `finally`-clobber | `== 0` |
| A7 | **Tekerlek kuralı kapısı.** `mkvi_core/Cargo.toml` ve `app/pubspec.yaml` içinde, `§4a`'daki listede olmayan **hiçbir** kriptografi/veri/sıkıştırma paketi yok. Yeni bir hash/şifre/AEAD/CRC **paketi olmadan** `lib/` veya `crates/` altına girerse kapı kırmızıya döner. | kırmızı |
| A8 | **SHA-256 kütüphane testidir, MKVI testi değil.** `fingerprint_sas` kendi koduyla değil, `sha2`'nin **resmî test vektörleriyle** (NIST CAVP) doğrulanır. Elle yazılmış bir hash varsa A7 kırmızıdır. | yeşil |
| A9 | **`restartIce()` ölçümü.** ICE `failed` → `restartIce()` → `onIceCandidate` **yeniden ateşleniyor** ve yeni adaylarla bağlantı kuruluyor. Bu bir *kabul* değil, `docs/adr/0001` karar kuralına bağlanmış bir **ölçüm** maddesidir; **ölçülmeden başarı varsayılmaz.** | ölçülecek |
| A10 | **Hibernasyon maliyeti ölçümü.** `RendezvousRoom` `state.acceptWebSocket()` kullanıyor — `server.accept()` **hiçbir yerde** geçmiyor — ve gerçek bir eşleşmede GB-s **bugünkü 112,5 GB-s'in belirgin şekilde altında.** Alarm planlamasının hibernasyonu engelleyip engellemediği §A'daki uyarı nedeniyle **ölçülür.** | ölçülecek |

### 3. İki cihazlı el senaryoları (`docs/manual-test.md`'ye eklenir)

| # | Senaryo | Beklenen | Eşik |
|---|---|---|---|
| S1 | Eşleşme → `connected` → SAS gösterilir | iki tarafta **aynı** 8 karakter | 10/10 |
| S2 | **S1'in kötü niyetli karşılığı:** 1. cihazın Worker'ı 2. cihazın Worker'ı yerine geçer | iki tarafta **farklı** SAS | 10/10 farklı |
| S3 | İki cihaz aynı LAN'da, **STUN tanımlı değil** | bağlanır | 10/10 |
| S4 | Farklı konut ağları, STUN yalnız | bağlanır, p50 `connected` süresi **≤ 6 sn** | 10/10 |
| S5 | Bir taraf simetrik NAT / UDP engelli | **sessiz takılma değil**, Türkçe ve eyleme dönük mesaj | 3/3 |
| S6 | 10 dk boşta, sonra mesaj | sohbet çalışır, **yeniden eşleşme yok** | 3/3 |
| S7 | A'yı kapat, B'yi aç → 30 dk sonra A yeniden açılır | A "yeniden bağlanılıyor" gösterir; B dönünce **kodsuz** bağlanır | 3/3 |
| S8 | S7 sırasında B'de **aktif arama** varsa | arama **düşer** (kanal koptu), sessizce donmaz | 3/3 |
| S9 | 512 MB dosya, tek yön | hatasız, ilerleme **monoton**, p50 MB/s **kaydedilir** (eşik yok, ilk ölçüm eşiği belirler) | 3/3 |
| S10 | S9'u 2. cihazda iptal et | **sıfır** dosya kalır (0 bayt dosya bile) | 3/3 |
| S11 | `flutter-webrtc` #2137 ekran paylaşımı (ADR-0001'in **aynı** 10 senaryosu) | `≥8/10` | değişmez |
| S12 | **ICE `failed` zorlanır** (ağ kesilir/açılır), sonra `restartIce()` | Yeniden aday toplama **ateşlenir** ve bağlantı **yeniden kurulur** — sessizce donmaz | 3/3 · **ölçüm, kabul değil** (A9) |
| S13 | `mkvi.iceServers` boş bırakılır, iki farklı konut ağında | Bağlantı **ya kurulur ya da** sessiz takılmaz; takılırsa Türkçe ve eyleme dönük mesaj çıkar | 3/3 |

### 4. Hata → davranış eşlemesi

| Hata | Nerede sınıflandırılır | Kullanıcıya görünen | Bağlantı |
|---|---|---|---|
| Worker'a ulaşılamıyor / TLS yok | `ReconnectConnectFailed` | "Yeniden bağlanılıyor: \<neden\>" | korunur, 700 ms → 12 sn |
| Endpoint geçersiz | `ReconnectEndpointUnusable` | "Sinyal sunucusuna bağlanılamadı." | döngü **bitmez** |
| Keyring kilitli | `ReconnectIdentityUnavailable` | "Cihaz kimliği açılamadı." | döngü **bitmez** |
| Karşı tarafın imzası geçersiz | `ReconnectPeerUnverified` | "Bilinen cihaz kimliği doğrulanamadı." | soket kapanır, yeni epoch |
| Bilet süresi dolmuş / oda dolu | `ReconnectConnectFailed` (alt metin) | "Eşleşme kodu süresi doldu. Yeni kod üret." | **yeniden eşleşme gerekir** |
| ICE `disconnected` | transport | "Bağlantı kesildi, yeniden bağlanılıyor…" | **sessiz bekleme penceresi**, sonra `restartIce()` |
| ICE `failed` | transport | "Doğrudan bağlantı kurulamadı." + TURN ipucu | epoch sökülür, yeni bilet |
| SAS eşleşmiyor | `app/lib/security/` | eşleşme reddedilir, kanal **kapanır** | bağlantı **kurulmaz sayılır** |
| Parmak izi değişmiş (sonraki bağlantı) | `app/lib/bridge/core_peer_store.dart` | "Cihaz değişmiş. Yeniden eşleşme gerekiyor." | bağlantı reddedilir |
| Rust köprüsü yoksa | `UnavailableSignatureVerifier` kaldırıldığı için **derleme hatası** | — | sessiz kabul **yapısal olarak imkânsız** |

### 5. Ölçümler ve eşikler

| Ölçüm | Nerede | Eşik | Not |
|---|---|---|---|
| p50 / p95 eşleşme süresi (kod girme → `connected`) | S1, S4 | p50 ≤ 6 sn | eşik bu ADR'de sabitlendi |
| p50 / p95 yeniden bağlanma süresi (S7) | S7 | p95 ≤ 20 sn | |
| eşleşme başına Worker GB-s | `wrangler tail` / faturalama | bugünkü 112,5 GB-s'in altında | ⚠️ **Düzeltilmiş:** bu sayı artık tahmin değil; 900 sn x 128 MB resmî fiyat tablosundan türetildi (§A), yani `AGENTS.md`'in "~115 GB-s"i **doğrulanmış aritmetiktir.** Gerçek **ölçülen** GB-s hâlâ ölçülmedi; ilk ölçüm eşiği belirler |
| Hibernasyon sonrası aynı ölçüm | A10 | 112,5 GB-s'in **belirgin** altında | Alarm planlamasının hibernasyonu engelleyip engellemediği **doğrulanamadı** (§A uyarısı) — bu yüzden ölçüm |
| Ücretsiz plan dayanıklılığı | tek hesapta ardışık gün | **≥ 500 eşleşme/gün** tüketmeden bitmemeli | Free istek kotası 100.000/gün; eşleşme başına istek sayısı ölçülmeli |
| Dosya aktarımı MB/s | S9 | eşik yok, **ilk ölçüm eşiği belirler** | uydurma sayı yazmıyoruz |
| 2 saat soak çökmesi | A6 | `== 0` | |

## Reddedilenler ve nedenleri

> **2026-09-26 ek bölümü — tekerlek kuralının reddettikleri.** Aşağıdaki beş
> seçenek "yazarız" seçenekleri olarak **gerçekten değerlendirildi** ve elendi.
> Hepsi `AGENTS.md`'nin *"Tekerleği yeniden icat etme"* kuralına çarpar. Buraya
> yazılmalarının sebebi: bu ADR'de "tekerlek aldık" denilen her yerde **paket
> adının** yazılı olması ve bir sonraki oturumun aynı tartışmayı baştan
> yapmaması.

| Reddedilen seçenek | Neden reddedildi (kural) | Yerine alınan paket |
|---|---|---|
| **Kendi ICE'mizi yazmak** (STUN/TURN istemcisi + aday eşleştirme) | ICE bir *protokol* değil, olgun ve çok dilli bir uygulamadır (RFC 8445/8838/8656). Elle yazmak `AGENTS.md`'nin saydığı beş kategoriden biri. | **`flutter_webrtc` → `libwebrtc`** |
| **Kendi DTLS el sıkışmamızı yazmak** (sertifika üretimi + fingerprint) | DTLS 1.2 el sıkışması ve X.509 zinciri elle yazılır. Zaten `libwebrtc` her bağlantıda bunu yapıyor. | **`libwebrtc`** — MKVI yalnız `a=fingerprint:` satırını **okur** |
| **Kendi DTLS-SRTP'mizi / medya şifrelememizi yazmak** | `AGENTS.md`'nin "özel kripto yazma" kuralı bunu **zaten** yasaklıyor; ayrıca tekerlek kuralı da. | **`libwebrtc`** (dahili SRTP) |
| **Kendi sıkıştırmamızı yazmak** (LZ4/RLE benzeri) | Dosya aktarımı ileride sıkıştırma isterse `dart:io`'nun `GZipCodec`/`ZLibCodec`'i **hazır**; elle yazıma sıfır gerekçe. | **`dart:io` `GZipCodec`** (veya `0003`'ün seçeceği bir paket) |
| **Kendi veritabanı motorumuzu / dosya formatımızı yazmak** | `AGENTS.md`'in saydığı kategoriler. `rusqlite` + `chacha20poly1305` zaten projede. | **`rusqlite`**, `chacha20poly1305` |

**Ve reddedilen alt seçenek: elle SHA-256.** SAS ifadesini türetmek bir hash
gerektirir. Elle SHA-256 yazmak cazip görünebilir ("tek fonksiyon"), ama
`AGENTS.md` bunu yasaklar ve `mkvi_core`'ta `sha2` **yoktur** (ölçüldü). Doğru
yol **bağımlılık eklemektir**: `sha2` (RustCrypto, `ed25519-dalek`'in de
kullandığı aynı proje) — dört sorusunun cevabı `0003`'te. Bu, "yeni bağımlılık
ekle" ile "kriter 'bu katman bize ait değil' işaretle" arasındaki dengeyi
çözer: hash **kütüphanenin** sorumluluğunda olur, `fingerprint_sas.dart` yalnız
onu **çağırır**.

**Seçenek (a) — mevcut ikiliyi koru.** Reddedildi çünkü:

1. `SECURITY.md`'nin "1. bilinen sınır"ını (`SAS` ↔ DTLS parmak izi bağlı değil)
   kapatmaz, ve `ROADMAP.md` Faz 4'ün tek açık güvenlik maddesi budur.
2. `PairingRoom` `server.accept()` kullandığı için **hiçbir zaman hibernating
   olamaz** (ölçüldü: Cloudflare dokümanı hibernasyonu "WebSocket standart
   API'si kullanılmıyorsa" mümkün sayıyor). Yani 15 dakika boyunca GB-s yazılır
   ve bu yapısal, ayar gerektirmiyor.
3. Worker önünde istek sınırı yok; herhangi bir anonim istemci geçerli biçimli
   kodla DO örneği oluşturup hesabın kotasını tüketebilir (Worker'ın kendi
   `README.md` §5'i bunu kabul ediyor).
4. `PeerRendezvous`'un 30 günlük kaydı kullanıcıya hiçbir şey kazandırmıyor.
5. 0.1.x geriye uyum yükü (`legacyDiscoveryTranscript`, opsiyonel `session`)
   **ölü istemciler için** taşınıyor.

**Seçenek (b) — eşleşmeden sonra sunucu tamamen yok.** Reddedildi çünkü:

1. **Ürünün ana vaadini ihlal eder.** Yeniden bağlanma, eş ağ değiştirdiğinde
   çöker ve kullanıcıdan yeniden kod ister; `ROADMAP.md` §Hedef'in ilk maddesi
   bunu açıkça yasaklıyor.
2. Ya üçüncü taraf bir STUN/keşif hizmeti gerekir (MKVI'nin kontrolünde değil,
   sürümlenmeyen, gizlilik modeline yabancı) ya da kullanıcı yine kendi
   Worker'ını kurar — ve o zaman (b) sessizce (c)'ye dönüşmüş olur.
3. "MKVI kimseye hizmet vermez" ilkesiyle çelişir.

**R2 ile dosya aktarımı (kapsam dışı).** Reddedildi çünkü mimari söz açıkça
"sunucu içerik taşımaz" diyor ve `SECURITY.md` bunu `Worker ne saklamaz`
bölümünde madde madde sayıyor. R2'nin çıkış ücreti olmaması cazip, ama vaadi
bozmak bir fiyat avantajına değmez. Aynı gerekçeyle **Queues** ve **D1** de
sinyalleşme için reddedildi (bkz. Araştırma tablosu).

**Workers KV ile eşleşme.** Reddedildi çünkü Free planda **1.000 yazma/gün**
(resmî limit) — günlük 1.000 eşleşmeliğinin üstüne çıkamaz; ayrıca
`minimum cacheTtl 30 sn` ve "aynı anahtara 1 yazma/sn" kısıtları, "kim şu anda
bağlı" sorusunu yanıtlamaya uygun değil.

**"Sunucuyu sıfırlamak" (hiçbir sunucu yok).** Reddedildi çünkü (b) ile aynı
sebeplerden; ayrıca `docs/adr/0001` "Rust çekirdek korunur" kararıyla da
bağdaşmıyor (Rust çekirdek bir sunucu değil, ama onu kullanacak bir buluşma
noktası olmadan kimlik eşleşmesi için bile gerekiyor).

**`flutter_webrtc` yerine başka bir WebRTC sarmalayıcısı.** `ROADMAP.md`
"Verilmiş kararlar" bunu zaten karara bağlamış ("WebRTC sarmalayıcısı
alınmaz") ve gerekçesi bu ADR'in konusu değil. Not: bu ADR sarmalayıcı seçimini
**yeniden açmıyor**; `rollback`'in eksikliği bu ADR'i (c)'ye yönlendirdi ama
alternatif sarmalayıcı önermiyor.

## Uygulama sırası

> Her adım tek sahipli dosyalara karşılık gelir ve bir sonrakine bağımlıdır.

| # | Adım | Dosyalar | Bağımlılık |
|---|---|---|---|
| 1 | **Taşıma çekirdeği.** `RTCPeerConnection` + `RTCDataChannel` + teklif/cevap + aday aktarımı, `PeerTransportBinding` uygulaması. Mevcut `SignalPayload` türlerini **kullanır** — protokol değişikliği yok, böylece `ReconnectDriver`'ın sahte soket testleriyle uçtan uca sınanabilir. | yeni `app/lib/transport/{peer_transport.dart,webrtc_peer_connection.dart}` | — |
| 2 | **Sohbet yüzü.** `ChatChannelBinding` (data channel üzerinde), `FileSink`, `OutgoingFileSource`. Bunlar `dart:io` + `path_provider` kullanır; **Rust köprüsü gerektirmez**, bu yüzden 4'ten önce gelir. | yeni `app/lib/transport/datachannel_channel.dart`, `app/lib/bridge/io_file_sink.dart`, `app/lib/bridge/io_outgoing_file.dart` | 1 |
| 3 | **İlk uçtan uca çalışan kabuk.** `main.dart`'ı `AppShell`'e bağla; `LocalSettings` dosya uygulaması; `SessionController(transport: …)` bağlanır. **Yeni paket yok** (`path_provider` zaten bağımlı). | `app/lib/main.dart`, `app/lib/settings/file_local_settings.dart`, `app/lib/ui/app_shell.dart` | 1, 2 |
| 4 | **Rust köprüsü.** `flutter_rust_bridge` + `mkvi_bridge` `pubspec.yaml`'a; `build_runner` ile Dart API. `DeviceIdentityLoader`, `PeerStore`, `HistoryStore`, `RustSignatureVerifier`. **Yavaş adım** (kod üretimi) ve 1–3'ten hiçbiri buna bağlı değil — bu yüzden sonra. `crates/mkvi_bridge/src/api.rs`'e `verify_artifact` + `key_is_legacy` eklenmesi gerekebilir (bugün **yoklar** — ölçüldü). | `app/pubspec.yaml`, yeni `app/lib/bridge/*.dart`, `crates/mkvi_bridge/src/api.rs` | 1 |
| 5 | **`sha2` kararı + DTLS parmak izi SAS.** **Önce `sha2` (RustCrypto) `mkvi_core/Cargo.toml`'a eklenir** — dört soru `0003`'te yanıtlanır, elle hash yazılmaz. Sonra `a=fingerprint:` ayrıştırıcısı, iki taraflı türetme, ilk bağlantıda `PeerStore`'a çivile. `docs/manual-test.md` S1/S2 senaryolarını ekle. | `crates/mkvi_core/Cargo.toml`, yeni `app/lib/security/fingerprint_sas.dart`, `docs/manual-test.md` | 4 |
| 5b | **`iceServers`'ı bağlantı kurulumuna geçir.** Bugün `ConnectionSettings.iceServersText` **hiçbir yere okunmuyor** (ölçüldü: `connection_settings.dart:128` yalnız saklıyor). Bu adım o metni `createPeerConnection({'iceServers': […]})` haritasına çevirir. **Varsayılan boş kalır** (Cloudflare TURN ücretli — §A). | yeni `app/lib/transport/ice_config.dart` | 1 |
| 6 | **Worker yeniden tasarımı.** `POST /v1/ticket` + tek hibernating `RendezvousRoom`; `PairingRoom` ve `PeerRendezvous` **silinir**; `identity` zarfı `isSignalPayload`'dan **çıkarılır**; `wrangler.jsonc`'ye rate-limiting binding + **`exports`** geçişi. | `cloudflare/src/index.ts`, `cloudflare/wrangler.jsonc`, `cloudflare/README.md`, `cloudflare/src/index.test.ts` | 5 |
| 7 | **Sözleşme vektörleri.** `vectors/wire-v1.json` yeni zarfı; Dart aynası; `forbiddenKeys` güncel; `identity`/`session` vakaları kaldırılır. | `vectors/wire-v1.json`, `app/lib/signaling/signal_payload.dart`, `app/test/signaling/*` | 6 |
| 8 | **Dokümantasyon.** `SECURITY.md` §1 kapanır, "ne saklar" tablosu güncellenir, TURN/ilişkilendirme sınırları yazılır. `ARCHITECTURE.md` ve `ROADMAP.md` Faz 3/Faz 4 kutuları kanıt satırıyla işaretlenir. | `SECURITY.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `AGENTS.md` (CLAUDE.md `tool.ps1 docs` ile türetilir) | 7 |

**Adım 6'nın geri dönüşsüz kapısı — uyarı.** `exports`'a geçiş
`workers-sdk#14614`'e göre tek yönlüdür (API 100403). Bu yüzden adım 6'da sınıf
**silme** ile `exports` geçişi **aynı deploy'da** yapılmalı ya da hiç yapılmamalı;
"önce sınıfı sil, sonra ayrı bir PR'da exports'a geç" şeklinde bölmek, geri
dönüşsüz kapıyı yarı açık bırakır.

**Adım 3'ün doğru sırası, `AGENTS.md`'nin "Mimari harita"sıyla tutarlıdır:**
`SettingsController` → `SessionController` → `ChatController` + `CallMachine` +
`MediaController` + `UpdateClient`. `main.dart` bugün hâlâ `flutter create`
şablonu; adım 3 bunu gerçek kabuğa bağlar.

## Dönüştü

Bu karar, `docs/adr/0001-flutter-migration.md` içindeki şu ifadenin **kapsamını**
daraltır: *"Sinyalleşme sunucusu (`cloudflare/`) **hiç değişmez** — zaten platform
bağımsız, sıfır bağımlılıklı bir TypeScript Worker."* Platform bağımsızlığı ve
bağımlılıksızlık **aynen korunur** (tek `import` yok, mobil de aynı Worker'ı
kullanır). Değişen şey zarf şeması ve DO sayısıdır, ve bunun gerekçesi bu
belgedir. 0001'in **kararı** (Flutter + korunmuş Rust çekirdek) değişmemiştir;
yalnız `cloudflare/`'ın dokunulmazlığı bu ADR ile sona ermiştir. 0001'in
karar kuralı (düz port / vendor fork / NO-GO) **aynen geçerlidir** ve bu ADR onu
değiştirmez; yalnızca 2. sorusunun (SDP parmak izi ≡ `getStats` parmak izi)
cevabı artık **mimari olarak bağımsız** sayılır.

## Uygulama notu — adım 4, yerel köprü yükleme kararı (2026-09-26)

> Bu bölüm **yeni bir karar değildir**; adım 4'ün yüklenmesiyle ilgili bir
> alt-kararı kayda geçirir. Yukarıdaki mimari karar "Rust köprüsü `pubspec`'a
> girer" diyordu; **nasıl yükleneceğini** söylemiyordu. Bu, o boşluğu doldurur.

**Sorun.** Üretilen `dart/lib/src/rust/frb_generated.dart:70-76`
`ioDirectory: '../target/release/'` diyor ve
`flutter_rust_bridge-2.13.0/lib/src/loader/_io.dart:18` bunu
**`Directory.current`**'e göre çözüyor (ölçüldü:
`Directory.current.uri.resolve(ioDirectory)`). Bir Flutter uygulamasının "çalışma
dizini", geliştiricinin `flutter run` yazdığı kabuğun dizinidir; uygulamanın bir
özelliği değildir. Dolayısıyla varsayılan **kullanılamaz**.

**Seçenekler ve akıbetleri.**

| Seçenek | Sonuç |
|---|---|
| (a) `RustLib.init`'e `ExternalLibraryLoaderConfig` vermek | **İmkânsız.** Üretilen `RustLib.init` yalnız `api`, `handler`, `externalLibrary`, `forceSameCodegenVersion` alıyor (`frb_generated.dart:23-35`); `config` parametresi yok ve `defaultExternalLibraryLoaderConfig` üreticinin sahip olduğu bir getter. (a)'nın *amacı* `externalLibrary` üzerinden ulaşılabilir. |
| (b) `rust_crate_flutter` / cargokit | **Doğru paketleme cevabı, ertelendi.** İki ölçülmüş sebep: (i) bir build hook eklediği için `flutter test` bir Rust araç zincirine bağımlı hâle gelir ve Dart CI işinin Rust kurulu olduğu varsayılamaz; (ii) etkisi yalnız `flutter build` üzerinden görünür ve bu değişiklikte `flutter build` **çalıştırılamadı** — yani doğrulanmamış bir mekanizma göndermek anlamına gelirdi. Çözülmemiş bir eksik olarak kayıt altına alındı. |
| (c) `MKVI_BRIDGE_DLL` ortam değişkeni + `DynamicLibrary.open` | **Seçilen.** Sıfır yeni bağımlılık, her Flutter hedefinde aynı davranış ve — yük taşıyan kısım — hatayı **yakalayıp adlandırma** imkânı. |

**Seçilen şekil: (a)'nın amacı, (c)'nın mekanizmasıyla.**
`app/lib/core/rust/rust_bridge_loader.dart` kütüphaneyi bir aday listesinde arar
(sıra: `MKVI_BRIDGE_DLL` → frb'nin kendi
`FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` değişkeni → çalıştırılabilir dosyanın
yanı ve `lib/` altı → `crates/mkvi_bridge/target/{release,debug}` → üretilen
`../target/release`), ve `app/lib/core/rust/rust_core.dart` bulunan dosyayı
`ExternalLibrary.open(path)` ile açıp `RustLib.init(externalLibrary: …)`'e verir.

**Yükleme gecikmeli ve hata toleranslıdır.** `RustCore.open` **hiçbir zaman
fırlatmaz**: eksik kütüphane bir istisna değil, `isAvailable == false` durumudur.
`RustPeerStore` bu durumda `PeerUnreadable(PeerStoreUnavailable())` döner,
`SessionBootstrap` bunu `SetupBroken`'e çevirir ve `SetupBroken.showsPairingScreen`
**yapı gereği** `false`'tir. Yani eksik kütüphane beyaz eşleştirme ekranına
**ulaşamaz**. Ölçüm: `app/test/integration/bridge_availability_test.dart`
(14 test) — CI'ın Linux runner'ında geçmesinin tek yolu budur, çünkü
`MKVI_BRIDGE_DLL` ile var olmayan bir dosya adreslemesiyle "köprü yok" yolu
**bilerek** seçilir.

**Ölçülen yan bulgu.** Çözülmüş bağımlılık grafiğinde Rust derleyen **hiçbir**
build hook yoktur: `app/.dart_tool/hooks_runner/` altında çalışan tek hook
`objective_c`'ninkidir (`path_provider_foundation`'dan geliyor). Yani (b) gerçekten
de seçilmemiş durumda, "gizlice seçilmiş" değil.

**`app/pubspec.yaml`'a iki bağımlılık girdi.** `mkvi_bridge` (yol) ve
`flutter_rust_bridge: 2.13.0`. İkincisi yalnız `ExternalLibrary` **tipini
adlandırabilmek** için; Dart iki paketin aynı çalışma zamanı sürümünü paylaşmasını
zorunlu kıldığı için sürüm `mkvi_bridge/dart/pubspec.yaml`'daki ile birebir aynı.
Kullanım tek satır.
