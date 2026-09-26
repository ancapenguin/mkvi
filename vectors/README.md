# wire-v1 — paylaşılan tel sözleşmesi

Bu klasör, MKVI sinyalleşme katmanının **tek yazılı biçim sözleşmesidir**. İki istemci
( TypeScript ve Dart ) aynı dosyayı okur ve aynı iddiaları çalıştırır. Kod üreteci
yoktur; iki taraf da dosyayı doğrudan JSON olarak okur.

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
| `src/services/signaling-vectors.test.ts` | `import.meta.glob(..., { query: "?raw" })` + `JSON.parse` |
| `app/test/signaling/wire_vectors_test.dart` | `dart:io` `File.readAsStringSync` + `dart:convert` `jsonDecode` |

Her ikisi de `vectors/wire-v1.json` dosyasını çalıştırır; bir kutu eklemek iki
testi de aynı anda değiştirir.

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
- Bir kutu eklerken iki tarafın da çalıştırabildiğinden emin ol. Yalnız bir tarafta
  anlamlı olan bir kutu, sözleşmeyi ikiye böler.

## Bilinen ihlaller

`src/services/rendezvous.ts` bu sözleşmenin **iki maddesini ihlal ediyor**. İkisi de
`src/services/signaling-vectors.test.ts` içinde `it.fails` olarak, tam hata metniyle
kayıtlıdır; kaynak düzeltilince işaretler kaldırılmalıdır:

1. `wss://` ile verilen bir uç nokta `ws://` indirgeniyor (TLS sessizce düşüyor).
2. Geçersiz bir uç nokta, sözleşmenin Türkçe hatası yerine, `connect()`'ten
   **eşzamanlı** olarak ham bir `TypeError: Invalid URL` fırlatıyor; bu yüzden
   `connect(...).catch(...)` hiç çalışmıyor.
