# Katkı rehberi

MKVI'ye katkıda bulunmak istediğiniz için teşekkürler. Bu rehber, bu depoda
çalışmak için gerekenleri, burada geçerli birkaç **sert kuralı** ve PR sürecini
toplar.

Katkıdan önce [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)'yi okuyun.

> **Bu proje tek bakımcılıdır ve geliştirme aşamasındadır.** Yayımlanmış bir
> sürüm yok. Katkılarınız için gerçekten teşekkür ederiz, ama PR'ların
> incelenme hızı bir taahhüt değildir. Başlamadan önce bir issue açıp yön
> tartışmak, saatler harcamaktan iyidir.

### Lisans durumu — hangi katkı nereye giriyor

| Yol | Lisans |
|---|---|
| `app/`, `crates/`, `design/`, `vectors/` | **Apache-2.0 OR MIT** (ikili lisans) |
| `cloudflare/` | **AGPL-3.0** |

Uygulamaya yaptığınız katkı `Apache-2.0 OR MIT` şubesine, `cloudflare/` altına
yaptığınız katkı `AGPL-3.0`'ye girer. Bu ayrım bilinçlidir: AGPL'nin ağ sunucusu
kapsamındaki yükümlülüğü, Worker'ın barındırma hizmeti olarak yeniden
satılmasını engeller. Hafifletmek için kaldırmayın.

---

## 1. Geliştirme kurulumu

Sıfırdan bir Windows makinesinde, adım adım:
**[`docs/getting-started.md`](docs/getting-started.md)**. Kısa özet:

| Gereksinim | Sürüm | Neden |
|---|---|---|
| Flutter | 3.44+ (Dart SDK `^3.12.2`) | `app/` |
| Rust | stable | `crates/mkvi_core`, `crates/mkvi_bridge` |
| Visual Studio Build Tools | "C++ geliştirme iş yükü" **şart** | `rusqlite` SQLite'i `bundled` özelliğiyle **kaynak koddan derler**; MSVC olmadan `cargo test` derlenmez |
| Node.js | 22 | yalnızca `cloudflare/` |
| Cloudflare hesabı | ücretsiz plan yeterli | yalnızca Worker'ı **çalıştırmak** istiyorsanız |

İlk kurulum:

```powershell
cd app;                  flutter pub get
cd ../crates/mkvi_core;  cargo build
cd ../crates/mkvi_bridge; cargo build
cd ../../cloudflare;     npm install
cd ../design;            dart pub get
```

### Depodaki Rust paketleri — neden iki ayrı?

Rust tarafı **iki ayrı pakettir** ve bilinçli olarak tek bir Cargo workspace'i
*değildir*:

| Paket | Ne |
|---|---|
| `crates/mkvi_core` | Çekirdek: Ed25519, keyring, şifreli geçmiş, dosya yazımı, güncelleme imza doğrulaması. Flutter'ı bilmez. Kendi `Cargo.lock`'i var. |
| `crates/mkvi_bridge` | `flutter_rust_bridge` yüzeyi. Davranışın hiçbir kısmı burada değildir; sadece kodlama ve hata eşlemesi. `staticlib` + `cdylib`. |

Bedeli: **her paketin testi ayrı ayrı koşar.** `mkvi_core`'un testleri
`mkvi_bridge` içinde çalışmaz ve tersi de doğrudur. Kapı ikisini de koşar.

### Çalıştırma

```powershell
cd app;  flutter run -d windows            # uygulama
cd cloudflare; npm run dev                 # Worker, yerelde (ws://localhost:8787)
```

> **Bugün ne açılacağı:** `app/lib/main.dart` hâlâ `flutter create` şablonudur;
> `flutter run` Flutter'ın örnek sayaç uygulamasını açar. Gerçek ekranlar
> (`app/lib/ui/`) var ve testli, birleştirme sırada. Bu bir hata değil.

---

## 2. Kapı — `.\tool.ps1 gate`

**Yeşil kapı olmadan PR önermeyin.** Bu, projedeki değişmez kuraldır.

```powershell
.\tool.ps1 gate              # hepsi
.\tool.ps1 gate-quick        # yalnız hızlı adımlar (analyze)
.\tool.ps1 build             # uygulamanın release derlemesi
.\tool.ps1 resources         # ağır derlemeden önce sadece kaynak ölç
.\tool.ps1 version           # sürüm kaynaklarını karşılaştır
.\tool.ps1 clean             # üretim girdilerini sil
```

`gate` sırasıyla: sistem kaynakları → sürüm kaynakları → `cargo test`
(`mkvi_core`, `mkvi_bridge`) → `wrangler deploy --dry-run` + `vitest` (Worker) →
`dart analyze` + `dart test` (`design/`) → `flutter analyze` + `flutter test`
(`app/`) → kodlama denetimi. Sonunda tek özet verir.

Ayrı adımları tek tek koşmak isterseniz:

```powershell
cd app;                   flutter analyze;  flutter test
cd crates/mkvi_core;      cargo test
cd crates/mkvi_bridge;    cargo test
cd design;                dart analyze;  dart test
cd cloudflare;            npm run check;  npx vitest run
```

> **`dart test` `app/` içinde çalışmaz.** `app` bir Flutter paketidir ve
> `package:test` bağımlılık grafiğinde yoktur; orada `flutter test` kullanılır.

### Kapının iki tuzağı

**a) Adım `ATLANDI` demek `KALDI` demek değildir.**
`tool.ps1` bir bileşen depoda yoksa onu `ATLANDI` ile atlar ve bunu ayrıca
yazar. Bu, "o şeyi test etmedik" demektir, "geçti" demek değildir. Özet satırı
`KAPI YESIL: <geçen> gecti, <atlanan> atlandi` biçimindedir; **ikinci sayı sıfır
değilse o kadar bileşen doğrulanmamıştır.** Kaç adımın geçtiğini siz saymayın;
`ATLANDI` geçen adımları yukarıda listeleyin.

**b) Sürüm kaynakları kapıdır, yazdırma değil.**
Sürümün kaynakları **dört tanedir ve eşleşmek zorundadır**: `VERSION`,
`app/pubspec.yaml`, `crates/mkvi_core/Cargo.toml`,
`crates/mkvi_bridge/Cargo.toml`. Sürümü değiştiriyorsanız dördünü birden
değiştirin; ayrışma `KALDI` verir. Yayın hattı sürümü etiketten okur, yani
etiket ile dosya ayrışırsa yayın yanlış sürümle başlar — bunu betik ayrıca
kırmızı yazar.

> Bu kural 2026-09-26'da ölçülmüş bir hatayı kapatıyor: `VERSION` 0.2.0 ve
> `app/pubspec.yaml` 0.2.0 idi ama Rust crate'ler 0.1.4'te kalmıştı. Yayın hattı
> etiketten okuduğu için `v0.2.0` etiketiyle tetiklense bile 0.1.4 yayımlanıyordu.

### `npm audit` kapının parçası değildir

Açık bir depoda her CI çalışması canlı bağımlılık çözümlemesi yapar; bu yüzden
`npm audit` **bilgilendirme amaçlı, engelleyici olmayan** bir adımdır. Denetim
temiz değilse PR'ı durdurmayın.

---

## 3. Bu projede üç sert kural

### Kural 1 — Kod yorumları **İngilizce**, kullanıcıya görünen her metin **Türkçe**

Bu ayrım istisna değildir ve pazarlık konusu değildir.

| Ne | Dil |
|---|---|
| Kod yorumları (`//`, `///`, `/* */`, `/// dartdoc`) | **İngilizce** |
| Kullanıcıya görünen **her** metin: arayüz, hata mesajları, bildirimler | **Türkçe** |
| Bu depodaki dokümantasyon (`README.md`, `SECURITY.md`, `CONTRIBUTING.md`, ADR'ler) | **Türkçe** |
| Kullanıcıya görünmeyen log satırları | Tercihen Türkçe; kullanıcıya yansıyorsa Türkçe olmalı |

Gerekçe: yorumlar kodun parçasıdır ve kod tabanının ortak dilindedir; görünen
metin ise üründür ve ürün Türkçedir. MKVI'nin depodaki her Dart barrel'ı bu
ayrımı kendi başına tekrarlar — örneğin `app/lib/session/session.dart` ilk
satırında.

Yeni bir katman yazarken: **kullanıcıya gösterilecek her cümle
`settings/`, `update/`, `chat/` içindeki bir `*_messages.dart` / `*_strings.dart`
sınıfına gider, kodun içine gömülmez.**

### Kural 2 — Türkçe metin UTF-8 ve **BOM'suz**; dosyayı PowerShell ile yazma

```powershell
# YAPMAYIN — Türkçe ANSI'ye çöker, BOM yazar, derlemeyi kırır
Set-Content -Path dosya.md -Value "Türkçe metin"
Out-File -Path dosya.json -Value $json
$x = Get-Content dosya.md -Raw          # BOM'lu okuma da bozar
```

Kullanın: editörünüzü, `apply_patch`'i ya da Node'un `fs` API'sini.

**Kurtarma:** `git checkout -- <dosya>`.

Bir dosyayı düzenledikten sonra denetimi koştur:

```powershell
# BOM, bozuk Türkçe metin ve ham NUL baytı — hepsi birden
.\tool.ps1 gate
```

Denetimi tek başına koşturmak isterseniz (çıktı **boş** olmalı):

```powershell
# Linux/macOS (veya WSL) — grep'in PCRE desteğiyle
grep -rnP '[\x{00c3}\x{00c5}\x{00c4}\x{00e2}\x{20ac}]' <klasör>

# Windows PowerShell — dosyayı OKUMAK güvenlidir, yazmak değil
Get-ChildItem <klasör> -Recurse -File -Include *.dart,*.ts,*.rs,*.md,*.json,*.yaml,*.toml |
  Where-Object { [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($_.FullName)) -match '[\u00C3\u00C5\u00C4]|[\u00E2][\u20AC]' } |
  Select-Object -ExpandProperty FullName
```

> Bu depoda Türkçe metin bir kez mojibake'e uğradı ve düzeltmesi ayrı bir iş
> oldu. Boş çıktı `0` eşleşme demektir. `Get-Content` ekrana bozuk gösterebilir —
> **dosya bozuk değildir, ekran kodlamasıdır.** Doğrulama daima bayt seviyesinde
> yapılır.

Tek istisna: `tool.ps1` dosyasının **başında BOM vardır** ve bu kasıtlıdır
(PowerShell 5.1'in Türkçe okuması için gerekir). `.ps1` dışında hiçbir dosyada BOM
olmamalıdır.

### Kural 3 — Katkıda **tek sahiplik**; aynı dosyaya iki kişi yazmaz

Bu kural özellikle otomatik ajanlarla çalışırken ölümcüldür: iki ajan aynı dosyaya
yazarsa işi birbirine ezer ve kimse hangi sürümün kazandığını bilemez.

- Bir dosyada çalışacaksanız önce **o dosyayı ilan edin** veya bir issue ile
  sahiplik alın. İlan edilmemiş bir dosyada çalışmayın.
- PR'da değiştirdiğiniz dosyaları **açıkça listeleyin.** "Bazı dosyaları da
  düzelttim" kabul edilmez.
- Başkasının sahipliğindeki bir dosyada **biçimlendirme, yorum, import sırası**
  gibi dokunulmamış değişiklikler yapmayın. Bu, kayıp düzeltmeleri üretir.

---

## 4. Mimari sınırlar — dokunmadan önce bilin

Bu sınırlar kırıldığında güvenlik modeli de kırılır. Katkı alanken göz önünde
bulundurun:

| Sınır | Kötüye kullanıldığında |
|---|---|
| **Worker içerik taşımaz.** `isSignalPayload` anahtar bazında beyaz listelidir; yeni alan eklemek Worker'ı içerik tüneline çevirir. | Sunucu içerik taşıyıcısına dönüşür |
| **Protokolü daraltmak kırıcıdır.** `isSignalPayload`'dan alan çıkarmak, o alanı hâlâ gönderen eski istemcileri `close(1008)` ile düşürür. | Sessizce uyumsuz istemciler |
| **Dart yalnız `mkvi_bridge` üzerinden Rust'a dokunur.** `mkvi_core` Flutter'ı bilmez. | Katman sınırı çöker, çekirdek test edilemez hale gelir |
| **Özel kripto yazma.** Yalnız denetimli crate'ler (`ed25519-dalek`, `chacha20poly1305`). Yeni şema gerekiyorsa önce bir issue açın. | Denetlenmemiş kripto |
| **Sessiz sır üretimi yasaktır.** Keyring boşsa ama diskte bir şey varsa yeni anahtar üretme; `KeyringEntryMissing` ver. | Her açılışta yeni kimlik — kayıtlı eş ölür |
| **Tasarım tek kaynağı `design/tokens.json`.** Uygulamada hiçbir renk/yay/radius/süre sabiti yazılmaz. | Okunmayan arayüz geri gelir (0.1.x'te 17 kontrast ihlali vardı) |
| **`vectors/wire-v1.json`** Dart ve TypeScript'in ortak sözleşmesidir; iki taraf da bu dosyaya bağlıdır. | İki uygulama sessizce ayrışır (0.1.x'te base64 ve UUID hatası böyle çıktı) |

`cloudflare/` hakkında değiştirmeden önce mutlaka
[`cloudflare/README.md`](cloudflare/README.md)'yi okuyun.

---

## 5. Commit düzeni

- **Commit başlığı Türkçe olur.** Deponun geçmişi Türkçe commit'lerden oluşuyor;
  İngilizce bir başlık geçmişi böler.
- **Tek bir mantıksal değişiklik = tek commit.** Refactor ile davranış
  değişikliğini aynı commit'te birleştirmeyin. Bir commit'te iki bağımsız
  düzeltme varsa `git reset` ile ayırın.
- Birinci satır emir kipinde özet, gerekiyorsa gövdede **neden** açıklanır.
- Üretilmiş dosyalar (`design/lib/generated/tokens.g.dart`,
  `crates/mkvi_bridge/src/frb_generated.rs`, `crates/mkvi_bridge/dart/lib/src/rust/*`,
  `app/windows/flutter/generated_plugin_registrant.cc`) **elle düzenlenmez.**
  Üreticileri değiştirip yeniden üretin ve değişikliği kaydedin.
- Bir sürümü yükseltiyorsanız dört kaynağı **tek commit'te** güncelleyin
  (bkz. §2, sürüm kapısı).
- **`CLAUDE.md` üretilmiş bir dosyadır.** Tek yazılı kaynak `AGENTS.md`'dir;
  `.\tool.ps1 docs` ikisini de yeniden üretir. `CLAUDE.md`'yi elle düzenlemeyin —
  değişikliği `AGENTS.md`'de yapın, sonra komutu koşturun.

## 6. PR süreci

1. **Önce bir issue açın** (yoksa). Büyük bir değişiklik "sen de bunu
   düşünmüş müydün" diye iki kat iş demektir.
2. **Bir dal açın.** Konuyla ilgili bir isim kullanın.
3. **`.\tool.ps1 gate` yeşil olmadan PR açmayın.**
4. PR açarken:
   - **Neyi ve neden** değiştirdiğinizi yazın.
   - **Değiştirdiğiniz dosyaları listeleyin** (Kural 3).
   - **Kapının çıktısını ekleyin.** "Yeşil" demek yetmez, kanıt istenir.
   - İlgili bir ADR gerekiyorsa `docs/adr/` altına yeni bir numara ile ekleyin;
     mevcut bir ADR'yi geriye dönük değiştirmek yerine yeni bir karar yazın.
5. CI yeşil değilse PR'da **neyi denediğinizi** yazın; kapatmayın, düzeltin.
6. **Push kararı bakımcının.** Yeşil bir kapıda commit *önerin*; PR'ı siz
   açabilirsiniz, açamayabilirsiniz.

## 7. Güvenlik bulguları

PR, issue veya tartışma üzerinden güvenlik açığı bildirmeyin. Bunun yerine
[`SECURITY.md`](SECURITY.md)'deki **özel** bildirim kanalını kullanın. Bildirilen
bir zafiyet, düzeltilip yayımlanana kadar herkese açık konuşulmaz.

Bu madde, bir PR'da fark ettiğiniz bir güvenlik sorununu "küçük bir düzeltme,
nasılsa görünür" diye hemen göndermenizi engeller. Önce kanaldan geçin.

## 8. Fork alıyorsanız: değiştirmeniz gereken değerler

MKVI'yi fork'lup kendi adınızla yayımlıyorsanız, aşağıdaki değerleri mutlaka
değiştirin. Değiştirmezseniz **sessizce** resmi uygulamayla çakışırsınız —
derleme hatası vermez, kullanıcı da farkında olmaz.

| # | Dosya | Değiştirilecek değer (şu an) | Neden zorunlu |
|---|---|---|---|
| 1 | `crates/mkvi_core/src/security.rs` | `const SERVICE: &str = "app.mkvi.desktop"` | İşletim sistemi anahtar kasasındaki kayıt adı. Değiştirmezseniz **aynı kasada aynı kayıt** kullanılır: cihaz kimliği ve veritabanı anahtarı paylaşılır, yani fork'unuz resmi kurulumun kimliğini sessizce devralır. Kullanıcı iki uygulamayı "farklı uygulama" sanar. |
| 2 | `app/windows/runner/Runner.rc` | `ProductName`, `FileDescription`, `OriginalFilename` (`mkvi.exe`) | Windows kurulum paketi adı ve kaldırma kaydı buradan gelir. Aynı ad iki uygulamanın kayıtlarını çakıştırır: birini kaldırmak diğerini de bozar. |
| 3 | `app/pubspec.yaml` | `name: mkvi` | Uygulama kimliği ve paket adı. Aynı kimlik = aynı yerel veri dizini. |
| 4 | `cloudflare/wrangler.jsonc` | `"name": "mkvi-signal"` | Worker adı. Değiştirmezseniz aynı Worker adına deploy edersiniz; iki Worker'a aynı adı veremezsiniz. |

Ek olarak gözden geçirin:

- AAD (ilişkili veri) sabitleri `crates/mkvi_core/src/security.rs` içinde
  fork'a özgü olmalı; aksi halde eski kayıtlarınız yeni sürümde açılamaz.
- `app/pubspec.yaml` içindeki `mkvi_design` yol bağımlılığı `../design` —
  fork'unuzda bu dizini de tutun ya da bağımlılığı kaldırın.
- Sürümü **dört** kaynaktan birlikte yükseltin (§2). `crates/mkvi_bridge/dart/
  pubspec.yaml` içindeki `version:` alanı kapı tarafından karşılaştırılmaz ama
  tutarlı tutun.
- 0.1.x Tauri hattı silindiği için `com.mkvi.desktop` **Tauri** kimliğiyle
  çakışmıyor artık; yine de `Runner.rc` ile `crates/mkvi_core/src/security.rs`
  içindeki isimler birbirinden bağımsızdır. Biriyle diğerini değiştirmeyin.

---

## 9. Başka bir şey mi arıyorsunuz?

| Ne | Nerede |
|---|---|
| Sıfırdan kurulum, adım adım | [`docs/getting-started.md`](docs/getting-started.md) |
| İki cihazla elle test | [`docs/manual-test.md`](docs/manual-test.md) |
| 0.1.x hattının miras kaydı (emekli) | [`docs/legacy-tauri-line.md`](docs/legacy-tauri-line.md) |
| Ne yapıldığı, mimari haritası, güvenlik sınırları | [`ARCHITECTURE.md`](ARCHITECTURE.md), `README.md` |
| Mimari kararlar | [`docs/adr/`](docs/adr/) |
| Plan, verilmiş kararlar, tuzaklar | `ROADMAP.md` |
| Sinyalleşme sunucunu kendi hesabına kurma | [`cloudflare/README.md`](cloudflare/README.md) |
| Güvenlik bildirimi, güvenlik modeli, bilinen açıklar | [`SECURITY.md`](SECURITY.md) |
| Üçüncü taraf bağımlılıklar ve gerekçeleri | [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) |
