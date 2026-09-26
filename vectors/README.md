# wire-v1 — paylaşılan tel sözleşmesi

Bu klasör, MKVI sinyalleşme katmanının **tek yazılı biçim sözleşmesidir**. 0.1.x
sürümünde iki istemci (TypeScript ve Dart) aynı dosyayı okuyup aynı iddiaları
çalıştırıyordu; TypeScript tarafı 2026-09-26'da emekliye ayrılan Tauri hattıyla
birlikte silindi. **Sözleşme tek taraflıdır ve bu kasıtlıdır** — gerekçesi ve
bedeli "Tüketenler" bölümünde yazılı. Kod üreteci yoktur; taraf dosyayı doğrudan
JSON olarak okur.

## Neden var

Sinyalleşme katmanı iki ayrı üretim hatası kaynağı oldu ve ikisi de **biçim
sözleşmesi** hatasıydı, mantık hatası değil:

1. Rust, kimlik materyalini `STANDARD_NO_PAD` base64 ile gönderiyordu (`+`, `/`),
   Worker'se yalnız base64url kabul ediyordu. 86 karakterlik bir imzada
   `(62/64)^86 ≈ %7` geçtiği için eşleşmelerin **~%93'ü** kimlik alışverişinde sessizce
   öldü.
2. `sendChat`, tireli `crypto.randomUUID()` üretiyordu; alıcının ayrıştırıcısı
   reddediyordu, sonuç: **hiçbir mesaj ulaşmadı**.

İkisinin de ortak noktası, iki tarafın aynı baytları aynı biçimde üretmesi
gereken tek bir yerde yazılı olmamasıydı. Bu dosya o "tek yer"dir.

## Tüketenler

| Tüketici | Nasıl okur |
|---|---|
| `app/test/signaling/wire_vectors_test.dart` | `dart:io` `File.readAsStringSync` + `dart:convert` `jsonDecode` |

**Bu sözleşme artık tek taraflıdır ve bu kasıtlıdır.**

0.1.x sürümünde aynı dosyayı **iki** tüketici koşuyordu: TypeScript istemcisi
(`src/services/signaling-vectors.test.ts`) ve Dart istemcisi
(`app/test/signaling/wire_vectors_test.dart`). Ortak vektörlerin değeri tam olarak
buydü: iki uygulama aynı dosyadan aynı kuralları okuyordu ve 0.1.x'in iki gerçek
kusuru **yalnız bu sayede** yakalandı — base64 alfabesi (`+`/`/` yazma duvarı,
eşleşmelerin ~%93'ü sessizce ölüyordu) ve UUID biçimi (tireli üretilen kimlikler
alıcı tarafta reddediliyordu, **hiçbir mesaj ulaşmıyordu**).

TypeScript tarafı 2026-09-26'da emekliye ayrılan Tauri hattıyla birlikte
silindi. Geriye kalan Dart tarafı vektörleri **hâlâ koşuyor** ve iki kusuru hâlâ
yakalıyor. Yani ortak vektörün *işlevi* ölmedi, *ikili olma özelliği* gitti.

Bunun bir bedeli var ve gizlenmiyor: artık yeni bir dil veya istemci eklenirse
vektör dosyası onu **kendiliğinden** bağlamaz. Bu dosyayı okuyan her yeni
tüketici, vektörü okuduğunu ve kuralı da buna göre değiştirdiğini kayda geçirmeli.
`test/signaling/wire_vectors_test.dart` içindeki 136 vaka silinemez veya
zayıflatılamaz — bunlar artık 0.1.x'in vasiyeti.

**Bir kutu eklemek `app/test/signaling/wire_vectors_test.dart` dosyasını
değiştirir** (yeni vaka) ve `app/lib/core/protocol/` altındaki ayrıştırıcıyı
(uygulama).

## Yapı

```
schema / version      dosya kimliği
kaynaklar             bu sözleşmenin türetildiği kaynak dosyalar
okumaKurallari        iki tarafın da uyması gereken kodlama kuralları
patterns              her doğrulayıcının uyguladığı düzenli ifadeler
errors                kullanıcıya gösterilen Türkçe hata metinleri
forbiddenKeys         zarf'a ASLA eklenemeyecek anahtarlar + gerekçeleri
groups[]              konu alanları
  cases[]             id / kind / aciklama (Türkçe) + girdi + beklenti
```

Her `case`in `kind` alanı, iki testin de `switch`lediği tek ayrım noktasıdır:

| `kind` | Neyi doğrular |
|---|---|
| `pairingCodeShape` | üretilen kodun alfabesi ve uzunluğu |
| `normalizePairingCode` | kullanıcının yazdığı kodun temizlenmesi |
| `pairingCodeAccepted` | Worker'ın `/v1/rendezvous` kabul testi |
| `opaqueIdShape` | `pair` / `device` / `session` kimliklerinin biçimi |
| `transferIdShape` | kontrol mesajı kimliğinin biçimi |
| `transferId` | kabul edilen ve reddedilen transfer id örnekleri |
| `payload` | `isSignalPayload` beyaz listesi |
| `relayEnvelope` | `isRelayEnvelope` zarfı |
| `incoming` | ham baytın istemci tarafındaki karşılığı (1003, yok sayma, presence) |
| `url` | uç noktadan URL kurulumu, hata sözleşmesi dahil |
| `queryEncoding` | tek bir sorgu değerinin tel üzerindeki kodlanmış hâli |
| `relayOutbound` | istemcinin gönderdiği baytın TAM metni (anahtar sırası dahil) |
| `forbiddenKey` | yasak anahtar eklenmiş zarf reddedilmeli |

## Kurallar

- Kod yorumları İngilizce, kullanıcıya görünen her metin Türkçedir.
- Dosya UTF-8 **BOM'suz**dur. Türkçe düzenlemeden sonra mojibake işaretlerini arayın:
  çift kodlamadan kalan **U+00C3**, **U+00C5**, **U+00C4** ve **U+00E2 U+20AC**
  dizileri. Çıktı boş olmalı. (Bu README bu dizileri kendisi içermez; grep
  komutunu burada yazmıyoruz çünkü otomatik kontrol onu yanlış pozitif sayardı.)
- Tüm dize örnekleri ASCII'dir; iki uygulamanın JSON kaçış davranışı ölçülmez.
- `incoming` ve `relayOutbound` türlerinde `null`, "olay TETİKLENMEDİ" demektir.
- Bir kutu eklerken **Dart tarafının** çalıştırabildiğinden emin ol. Yalnız tek bir
  tarafta anlamlı olan bir kutu, sözleşmeyi böler.

## 0.1.x'te bulunan ve Dart tarafında DÜZELTİLMİŞ iki ihlal

Bu iki madde 0.1.x'in TypeScript istemcisini (`src/services/rendezvous.ts`)
ihlal ediyordu. İkisi de `src/services/signaling-vectors.test.ts` içinde
`it.fails` olarak sabitlenmişti — yani kaynak düzeltilene kadar kural ihlali
gerçekken bile suite yeşil kalıyordu. **O dosya 2026-09-26'da silindi**, ama iki
maddenin kaydı burada kalıyor çünkü Dart tarafı ikisini de düzeltmiştir ve
`app/test/signaling/rendezvous_client_test.dart` her birini ayrı testle ölçüyor:

1. **`wss://` sessizce `ws://` indirgeniyordu** (TLS düşüyordu; kimlik imzaları
   ve SDP açıkta gidiyordu). Dart istemcisi şemayı koruyor.
2. **Geçersiz uç nokta sözleşmenin Türkçe hatası yerine `connect()`'ten
   eşzamanlı ham bir `TypeError: Invalid URL` fırlatıyordu** — `new URL()` promise'in
   dışında olduğu için `connect(...).catch(...)` hiç çalışmıyordu. Dart istemcisi
   hatayı değere çeviriyor.

> Bu kayıt 0.1.x'in vasiyetidir: kural hâlâ geçerli, ihlal eden taraf yok.
> Silinse, aynı hatanın yeniden yazılması "bilinmeyen bir hata" gibi görünür.
