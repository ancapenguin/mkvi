# MKVI sinyalleşme sunucusu

Bu dizin, MKVI'nin **sinyalleşme (signaling)** sunucusudur: iki cihazın ilk kez
birbirini bulması ve WebRTC el sıkışmasını kurması için gereken küçük paketleri
birbirine iletir. **Mesaj, dosya, ses, video ve ekran içeriğinin hiçbiri bu
sunucudan geçmez.** İçerik doğrudan iki cihaz arasında akar (P2P).

Uygulamayı kendiniz derleyip çalıştıracaksanız bu sunucuya ihtiyacınız yoktur:
resmî kurulum dosyası hazır bir sunucu adresiyle gelir. **Kendi sunucunuzu kendi
Cloudflare hesabınıza kurarsanız** verileriniz tamamen kendi hesabınızda kalır ve
hiçbir yabancıya bağımlı olmazsınız. Kurulum beş adımda sürer.

> **Lisans: AGPL-3.0.** Bu lisans **yalnızca bu dizine** uygulanır; deponun geri
> kalanı (`src/`, `src-tauri/`) `Apache-2.0 OR MIT` altındadır. Tam metin:
> [`LICENSE`](./LICENSE). AGPL'nin ağ sunucusu kapsamındaki yükümlülüğü
> (çalıştırılan programın kaynak kodunu o programı kullananlara sunma) bu
> sunucunun **barındırma hizmeti olarak yeniden satılmasını** engellemek için
> seçilmiştir. Kendi hesabınızda çalıştırıp kendiniz kullanmak sorun değildir;
> başkalarına ücretli/ücretsiz bir hizmet olarak sunmak, lisansın şartlarına
> aykırı olur.

---

## 1. Gereksinimler

- **Node.js 22**
- **Cloudflare hesabı** (ücretsiz plan yeterlidir — yeterli olup olmadığını
  [sınırlar](#4-sınırlar) bölümü okuyun)
- BİR Cloudflare Workers **Workers** aboneliği değil, normal ücretsiz hesap yeterli

Ücretlendirme hesabınıza bağlıdır. Ücretsiz planın Durable Object **süre**
kotası sınırlıdır; aşarsanız eşleşmeler çalışmaz (aşağıda anlatıldığı gibi).

---

## 2. Kurulum — beş adım

Bu dizinde çalışın:

```bash
cd cloudflare
npm install
npx wrangler login
npx wrangler deploy
```

Adım adım:

| # | Komut | Ne yapar |
|---|---|---|
| 1 | `cd cloudflare` | Worker'ın bulunduğu dizine geçin. Tüm komutlar **bu dizinden** çalıştırılır. |
| 2 | `npm install` | Geliştirme bağımlılıklarını kurar (yalnızca `wrangler`, `typescript`, `vitest`). Üretilen Worker'ın **çalışma zamanında** hiçbir bağımlılığı yoktur. |
| 3 | `npx wrangler login` | Tarayıcı açılır, Cloudflare hesabınızla yetkilendirir. Bu bilgisayarda `wrangler` kimlik bilgisi saklanır. |
| 4 | `npx wrangler deploy` | Worker'ı yayımlar ve adresini yazar, örn. `https://mkvi-signal.<sizin-alt-etki-adiniz>.workers.dev` |
| 5 | — | Bu adresi MKVI uygulamasının **Ayarlar → Signaling sunucusu** alanına yapıştırın ve kaydedin. |

`wrangler deploy` çıktısındaki adresi kopyalayın. Uygulamadaki varsayılan
değer, resmî geliştiricinin Worker'ının adresidir; kendi adresinizi
yazmayı unutursanız trafiğiniz **oraya** gider.

### Doğrulama

```bash
# 1. Sunucu ayakta mı? (çalışma zamanı kimlik bilgisi gerektirmez)
curl https://<adresiniz>/health
# beklenen: {"ok":true,"service":"mkvi-signal"}

# 2. Kaynak kod derleniyor mu? (HIÇBİR Cloudflare kimlik bilgisi gerektirmez)
npm run check
```

`npm run check`, `wrangler deploy --dry-run` demektir. CI'daki dört komutlu
gate'in dördüncüsüdür ve kimlik bilgisi istemediği için her yerde çalışır.

### Yerelde denemek

```bash
npm run dev       # wrangler dev — Worker'ı yerelde çalıştırır
npm test          # Zarf doğrulayıcı birim testleri (kimlik bilgisi gerektirmez)
```

Uygulamada Worker adresini `ws://localhost:8787` olarak vererek yerel sunucuya
bağlanabilirsiniz.

---

## 3. İki Durable Object nedir?

Kaynak tek dosyadır: [`src/index.ts`](./src/index.ts). İki sınıf vardır ve
ikisi de Cloudflare'ın **Durable Objects** ürünüdür — küresel, tek yazarlı,
dayanıklı (persistent) bir koordinasyon noktası. Mesaj içeriği saklamazlar;
sadece "şu anda odada kim var" ve "bu eşleşmenin cihazları kim" bilgisini
tutarlar.

### `PairingRoom` — 15 dakikalık tanışma odası

İki cihaz kısa kodu paylaştığında açılır.

- **Oda kimliği koddan türetilir:** `PAIRING_ROOM.idFromName(code)`. Kod, odaya
  erişmek için gereken tek anahtardır (URL'de `?code=` ile gelir).
- **Süre: 15 dakika.** `setAlarm` ile bir alarm kurulur; süre dolunca tüm
  soketler kapatılır ve `admitted` sayacı silinir.
- **Aynı anda en fazla 2 canlı soket** (yani iki cihaz).
- `MAX_ADMISSIONS = 8`: odaya en fazla 8 kez giriş hakkı. Bu bir *eşleşme sayısı
  değil, yeniden deneme bütçesidir* — uygulama yeniden başlatıldığında, düğmeye
  iki kez basıldığında veya soket düştüğünde yeniden giriş sayılır. Kod
  yeniden kullanılamaz; süre dolduğunda biter.
- **Sinyalleşme hızı sınırlı:** bağlantı başına dakikada 120 zarf. Aşılırsa
  soket `1008` ile kapatılır.
- **Zarf boyutu sınırlı:** mesaj başına 65.536 bayt. SDP en fazla 32.768, ICE
  adayı en fazla 2.048 bayt.

### `PeerRendezvous` — 30 günlük kalıcı eş kaydı

Eşleşme onaylandıktan sonra, uygulama bir kez daha bağlanır ve artık kodu
girmeye gerek kalmadan aynı eşi bulur.

- **Eşleşme kimliği** 32 rastgele baytın base64url gösterimidir (43 karakter).
  Kısa kod değildir; eşleşme onayı sırasında iki tarafın yerel olarak türettiği
  bir yetenek değeridir. URL'de `?pair=` ile gelir.
- **Cihaz başına en fazla 2 cihaz** kaydedilir. Üçüncü cihaz `403` alır.
- **TTL: 30 gün**, kayan (sliding). Yeni bir bağlantı geldiğinde süre yenilenir.
  Süre dolunca tüm soketler `4001` ile kapatılır ve kayıt silinir.
- **Cihaz başına tek canlı soket.** Yeni bağlantı geldiğinde eskisi
  `4000` (Superseded connection) ile kapatılır; bu iki cihazlık kotanın birini
  harcamaz, yani yeniden bağlanmak kotayı tüketmez.

### Neden iki tane?

`PairingRoom` **güvensizdir** (kod bilen biri girer) ve **kısa ömürlüdür** —
kurulumun kendisi. `PeerRendezvous` **zaten kimliği doğrulanmış** bir eşleşmenin
üzerine kurulur (kimlik zarfındaki Ed25519 imzası iki tarafta yerel olarak
doğrulanır) ve eşin 30 gün boyunca "şu anda çevrimiçi mi?" bilgisini taşır.
Kurulumun güvensizliği kalıcı eş kaydına sızmaz.

### Uç noktalar

| Yöntem + yol | Davranış |
|---|---|
| `GET /health` | `{"ok":true,"service":"mkvi-signal"}` — kimlik doğrulaması yok, WebSocket de gerekmez |
| `GET` / WebSocket olmayan istek | `426 WebSocket required` |
| `WebSocket /v1/rendezvous?code=<KOD>` | `PairingRoom`'a yönlendirir. Kod `^[A-HJ-NP-Z2-9]{13,16}$` olmalı (belirsiz karakterler `I O 0 1` yok), aksi halde `400` |
| `WebSocket /v1/peer?pair=<43>&device=<43>` | `PeerRendezvous`'a yönlendirir. Her iki kimliğin biçimi doğrulanır, aksi halde `400` |
| Diğer yollar | `404` |

---

## 4. Sınırlar

Bunlar kazara değil, bilerek konulmuş güvenlik sınırlarıdır.

| Sınır | Değer | Nerede |
|---|---|---|
| Eşleşme odasında eşzamanlı cihaz | **2** | `PairingRoom.fetch` — 3. bağlantı `409` alır |
| Oda başına toplam giriş | **8** | `MAX_ADMISSIONS` — 9. giriş `409` alır |
| Oda ömrü | **15 dakika** | `setAlarm` |
| Kalıcı eşte cihaz | **2** | `PeerRendezvous` — 3. cihaz `403` alır |
| Kalıcı eş ömrü | **30 gün** (kayan) | `PEER_TTL_MS` |
| Zarf boyutu | **65.536 bayt** | `relay` |
| SDP boyutu | **32.768 bayt** | `isSignalPayload` |
| ICE adayı boyutu | **2.048 bayt** | `isSignalPayload` |
| Sinyalleşme hızı | **120 zarf/dakika** | `rateWindows` — aşılırsa `1008` |
| Zarf şeması | **anahtar bazında beyaz liste** | `isSignalPayload` — alışılmadık JSON `1008` ile reddedilir |

### ⚠️ Ücretsiz planın günlük tavanı — en önemli sınırlardan biri

Cloudflare'ın ücretsiz planında Durable Object **süre** kotası **13.000 GB-s /
gün**'dür. `PairingRoom`, hibernasyon desteklemeyen WebSocket API'sini
kullanır (`server.accept()`), yani **her açık oda süre ücreti yazdırır** ve
kapatılana kadar bekler.

Bir 15 dakikalık kabul kabaca **115 GB-s** durum maliyetine denk gelir:

```
13.000 GB-s / gün  ÷  115 GB-s / eşleşme  ≈  110 eşleşme / gün
```

**Bu, ölçülmüş bir sayı değil, kotadan türetilmiş bir tahmindir.** Yine de
sonucun şu olduğu kesindir: **ücretsiz bir hesap, günde yaklaşık 110
eşleşmeden sonra tükenir** ve aşan istekler reddedilir. Paylaşılan bir ücretsiz
instance'ı arkadaşlarınıza açtığınızda, kotanın bir kısmı onların kullanımına
gider. Ölçek gerekiyorsa Workers Paid planı şarttır.

`PeerRendezvous` ise hibernasyon destekleyen `state.acceptWebSocket()` API'sini
kullandığı için boştayken ücret yazdırmaz; kalıcı eş kayıtlarının maliyeti
`PairingRoom`'dan belirgin biçimde düşüktür.

---

## 5. Kötüye kullanım yüzeyi — kendiniz okumalısınız

**Bu, herkese açık bir instance'ı paylaşmadan önce bilmeniz gereken en önemli
bölümdür.**

### Oda kimliği koda doğrudan türetilir

```ts
env.PAIRING_ROOM.idFromName(code)   // src/index.ts
```

Durable Object kimliği **koddan deterministik olarak türetilir.** Bu, kod
kombinasyonunun bilinmesini gerektirir — kod 13–16 karakter ve `I O 0 1`
karakterlerini içermez, yani pratikte tahmin edilemez. **Ama kodun kendisi
kimlik değildir, tek erişim anahtarıdır:** kod bilen herkes odaya girebilir.

Bunun kötüye kullanım sonucu:

> **Herhangi bir anonim istemci, biçimsel olarak geçerli rastgele bir kod
> üreterek bir Durable Object örneği *oluşturabilir*.** Bunu yapmak için
> Worker'da hiçbir ön koşul, oturum ya da kimlik doğrulama yoktur; durum
> yazmaya (`admitted` sayacı, alarm) yeterlidir. Aynı şekilde
> `PeerRendezvous` için 43 karakterlik geçerli biçimli iki `base64url` değer
> yeterlidir.

Yani Worker'ın önünde **kimlik doğrulama yoktur, yalnızca biçim doğrulaması
vardır.** Bu bilinçli bir tasarımdır (kurulum gerektirmez), ama şu sonucu
doğurur: **Worker'ı internete açtığınızda, geliştiricinin hesabınızın kotasını
tüketmek isteyen tek bir kişi bile onu tüketebilir.** Eşleşme sayısı sınırı
vardır ama **istek sayısı sınırı yoktur.**

### Ne yapmalısınız

1. **Kendi hesabınızda, kendiniz ve birkaç güvendiğiniz kişi için kullanın.**
   Bu, kurulumun varsayılan ve önerilen kullanımıdır.
2. **Paylaşılacak bir instance açıyorsanız mutlaka kenarda (edge) bir hız
   sınırı koyun.** Worker'ın kendi içinde olmayan tek koruma budur — Cloudflare
   WAF / rate limiting kuralları, Workers rate limiting binding'i veya Cloudflare
   Access. Bu Worker, hiçbirini kendi içinde uygulamaz.
3. **Açık bir instance'ta asla kimlik doğrulama beklemeyin.** Eşleşme
   kodları birer *bearer* yetenek değeridir; sızarsa o odaya girilir.
4. **Kendi domain'inizi ve HTTPS'yi kullanın** (aşağıdaki bölüm).

### Worker'ın yapmadığı, bilerek yapmadığı şeyler

- Kimlik doğrulama (amaçlanan: hesapsız)
- Yetkilendirme / kotalama
- İstek sayısı sınırı
- Hız sınırı (WebSocket *zarf* hızı sınırlıdır; bağlantı açma istekleri sınırsızdır)

---

## 6. Bu sunucu ne saklar, ne saklamaz

Bu sorunun cevabı, MKVI'nin tüm güvenlik modelidir. Dürüst olmak gerekirse
"operator'ın neyi *görebildiği*" ile "neyi *sakladığı*" farklı sorulardır.

### ❌ Saklamaz — hiçbir koşulda

- **Mesaj içeriği.** Metin mesajları P2P DataChannel üzerinden akar.
- **Dosyalar.** Akışlı dosya aktarımı P2P'dir.
- **Ses, video ve ekran paylaşımı medyası.** P2P'dir.
- **Mesaj şifreleme anahtarları.** Anahtarlar hiçbir zaman ağa çıkmaz;
  cihaz Ed25519 anahtarı işletim sistemi kasasında tutulur.
- **Yerel veritabanı.** Şifreli SQLite, yalnızca yerelde.
- **Kullanıcı adı, telefon numarası, e-posta, hesap.** Alınmaz; MKVI'de hesap
  yoktur.

### ✅ Saklar — iki Durable Object'ta, toplam iki şey

| Nerede | Ne | Süre |
|---|---|---|
| `PairingRoom` | `admitted` sayacı (bir tamsayı) ve alarm zamanı | 15 dakika; alarm sonrası `admitted` silinir, nesne yok olur |
| `PeerRendezvous` | `peer-record`: **en fazla 2 opak cihaz tutamacı** ve `expiresAt` | 30 gün (kayan), sonra silinir |

Cihaz tutamakları **adres değildir**: 32 rastgele baytın base64url gösterimi,
üretildiği tarafta saklanan bir yetenek değeridir. Sizin adınızı, IP'nizi veya
cihaz kimliğinizi tutmaz.

### 👁 Geçici olarak *görebilir* (saklamaz)

Cloudflare Workers bir *bulut geçidi* olduğu için, Worker'ın belleğinden
**geçen** paketleri işleten kişi teorik olarak görebilir. Bunlar:

- `identity` zarflarındaki cihaz **açık** anahtarı ve **imzası**
- `offer` / `answer` zarflarındaki **SDP**
- `ice` zarflarındaki **ICE adayları** (IP adresleri ve portlar)

Bunlar **diskte saklanmaz** ve Worker'da kalıcı iz bırakmaz; paket bellekten
geçip diğer tarafa iletilir. Yine de açıkça söylemek gerekir: **sinyalleşme
sunucusunu işleten kişi, sizin cihazınızın IP adresinizi (ICE adaylarında) ve
SDP'nizi görür.** Yalnızca alıcı tarafın IP'si değil, **her iki tarafın** IP'si
görünür olabilir.

Bu, içerik gizliliğini bozmaz (içerik akmaz) ama kimlik doğruluğu tarafında
bilinen bir sınırdır: **doğrulama (SAS) ifadesi henüz DTLS sertifika parmak
izlerini bağlamıyor**, yani sunucuyu kontrol eden biri iki tarafa aynı ifadeyi
gösterebilir. Bu açık `SECURITY.md` içinde açıkça yazılıdır ve
`ROADMAP.md`'de düzeltilmesi izlenmektedir.

### Zarf şeması bir içerik tüneli değildir

`isSignalPayload` anahtar bazında beyaz liste kullanır. Şemaya uymayan her
zarf `1008` ile reddedilir. Yani Worker, taşıdığı verinin **ne olduğunu
doğrulayan** bir katmandır — keyfi bir içerik taşıyıcısı olamaz. Protokolü
**daraltmak** kırıcıdır: bir alanı çıkarmak, hâlâ o alanı gönderen eski
istemcileri düşürür.

---

## 7. Kendi domain'inizi bağlamak (isteğe bağlı)

`*.workers.dev` yerine kendi alan adınızı kullanmak isterseniz: kendi
alan adınızı Cloudflare'a ekleyin, bir Worker rotası oluşturup
`mkvi-signal` Worker'ına yönlendirin, ardından uygulamadaki ayarı kendi
`https://` adresinizle değiştirin. Uygulama `https://` girdiğinizde otomatik
olarak `wss://` kullanır.

`wrangler.jsonc` içindeki `"name"` alanını değiştirirseniz `*.workers.dev`
adresiniz de değişir — iki Worker'a aynı adı veremezsiniz.

---

## 8. Yapılandırma dosyası

[`wrangler.jsonc`](./wrangler.jsonc):

- `name`: Worker adı (`mkvi-signal`) — adresi belirler.
- `main`: `src/index.ts` — giriş noktası.
- `compatibility_date`: Workers çalışma zamanı sabitlenmiş sürüm.
- `durable_objects.bindings`: `PAIRING_ROOM` → `PairingRoom`,
  `PEER_RENDEZVOUS` → `PeerRendezvous`.
- `migrations`: `PairingRoom` ve `PeerRendezvous` için SQLite-backed sınıf
  migrasyonları.

Şema dosyası yerelde `node_modules/wrangler/config-schema.json` yolundan
okunduğu için `npm install` yapılmadan editör şema doğrulaması yapamaz.

---

## 9. Worker'ın bağımlılıkları

Worker'ın **kendi kaynağında hiçbir üçüncü taraf içe aktarımı yoktur** — tek
satır `import` yoktur. Yalnızca Cloudflare Workers çalışma zamanının global
tiplerini kullanır. `package.json` içindeki `wrangler`, `typescript` ve
`vitest` yalnızca **geliştirme araçlarıdır**; dağıtılan Worker'ın içine
girmezler. Bu, AGPL kapsamındaki sunucunun çalışma zamanında başka bir paket
lisansı devreye sokmadığı anlamına gelir.

---

## 10. Sık karşılaşılan sorunlar

| Belirti | Sebep | Çözüm |
|---|---|---|
| Eşleştirmede "bağlanılamadı" | Kod yanlış veya süresi dolmuş | Yeni kod üretin; 15 dakikalık pencereyi aşmayın |
| Kod "geçersiz" (`400`) | `I O 0 1` içeriyor ya da 13–16 karakter değil | Uygulamanın ürettiği kodu kopyalayın |
| Oda "dolu" (`409`) | İki cihaz zaten bağlı ya da 8 giriş hakkı bitti | 15 dakika bekleyin (alarm sayacı sıfırlar) ya da yeni kod üretin |
| "Eş cihaz sınırı" (`403`) | Bu eşleşmede 2 cihaz zaten var | Üçüncü cihazı ekleyemezsiniz; kaldırıp yeniden ekleyin |
| Bağlantı `4000` ile kapandı | Aynı cihazdan yeni bağlantı açıldı | Normal; yeniden bağlanma eskisini supersede eder |
| Bağlantı `4001` ile kapandı | 30 günlük TTL doldu | Yeni eşleşme kurun |
| Bağlantı `1008` | Zarf şemasına uymayan veri veya hız sınırı | Genellikle eski istemci sürümü; uygulamayı güncelleyin |
| Hile yapıyorsunuz ama Worker yok | `npm install` yapılmamış | `cd cloudflare && npm install` |
| `deploy` kimlik doğrulama hatası | Oturum düştü | `npx wrangler login` |
