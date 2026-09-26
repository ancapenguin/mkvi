# Katkı rehberi

MKVI'ye katkıda bulunmak istediğiniz için teşekkürler. Bu rehber, bu depoda
çalışmak için gerekenleri ve burada geçerli olan birkaç sıkı kuralı toplar.

Katkıdan önce [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)'yi okuyun.

Lisans durumu: uygulama `Apache-2.0 OR MIT`, `cloudflare/` dizini (sinyalleşme
sunucusu) `AGPL-3.0`. Katkınızın hangi lisans altında geleceğini bu ayrımı
bozmadan bilmeniz gerekir: uygulamaya yaptığınız katkı `Apache-2.0 OR MIT`
şubesine, `cloudflare/` altına yaptığınız katkı `AGPL-3.0`'ye girer.

---

## 1. Ön koşullar

| Gereksinim | Sürüm | Neden |
|---|---|---|
| Node.js | **22** | Vite 7 ve Vitest 4 bu hatta göre geliştirildi. Depoda `.nvmrc` **yoktur**; CI daima Node 22 kullanır. |
| Rust | **stable** (`dtolnay/rust-toolchain@stable` ile aynı) | Tauri 2, `ed25519-dalek 2`, `minisign-verify 0.3` |
| Visual Studio Build Tools (yalnızca Windows) | "C++ geliştirme iş yükü" işaretli | `rusqlite` SQLite'i `bundled` özelliğiyle **kaynak koddan derler**; MSVC build araçları olmadan `cargo test` derlenmez |
| WebView2 Runtime (yalnızca Windows) | Evergreen, yüklü | Uygulamanın arayüzü WebView2'de çalışır. Windows 11'de hazırdır; Windows 10'da ayrıca kurulması gerekebilir |
| Flutter | Flutter SDK, `sdk: ^3.12.2` karşılanacak şekilde | Flutter istemcisi (`app/`) Tauri/React istemcisi yerine geçiriliyor. Kurulum: `cd app && flutter pub get` |
| Dart/Flutter tarafı | — | `app/pubspec.yaml` doğrudan bağımlılıkları; `app/pubspec.lock` tam transitif liste |

Ayrıca Cloudflare Worker'ı **çalıştırmak** istiyorsanız: bir Cloudflare hesabı ve
ücretsiz plan. Worker'ın kaynak kodu hiçbir şey kurmadan test edilebilir; bkz.
[`cloudflare/README.md`](cloudflare/README.md).

### Depodaki iki Rust paketi

Rust tarafı **iki ayrı pakettir** ve bilinçli olarak tek bir Cargo workspace'i
*değildir*:

| Paket | Ne |
|---|---|
| `crates/mkvi_core` | Çekirdek: güvenlik, kimlik, şifreli geçmiş, dosya alımı, güncelleme imza doğrulaması. Tauri bağımlılığı **yoktur**; Flutter kabuğu bunu `flutter_rust_bridge` üzerinden çağırır. Kendi `Cargo.lock` dosyası vardır. |
| `src-tauri` | Yalnızca Tauri adaptörü: pencere, IPC komutları, güncelleme eklentisi. `mkvi_core`'u yol bağımlılığı olarak kullanır. |

Bu ayrım sayesinde çekirdek, Tauri'yi yanında taşımadan derlenebilir. Bedeli:
**çekirdeğin testleri `src-tauri` içinde çalışmaz.** §3'e bakın.

### Kurulum

```bash
npm install
(cd cloudflare && npm install)
(cd app && flutter pub get)      # yalnızca Flutter istemcisi üzerinde çalışırsanız
```

`cd` kullanmayan bir kabuk kullanıyorsanız alt komutları çalıştırmak için
`workdir` değiştirin.

---

## 2. Geliştirme

```bash
npm run tauri dev          # masaüstü uygulamasını çalıştırır
npm run dev                # yalnızca ön yüz (tarayıcıda)
(cd cloudflare && npm run dev)   # Worker'ı yerelde çalıştırır
```

Arayüz dili **Türkçe**, kod yorumları **İngilizce**. Bu ayrım istisna değildir.

---

## 3. Tam gate — dört komut

**Dördü de yeşil olmadan commit önermeyin.** Bu, projedeki değişmez kuraldır.

```bash
npx tsc --noEmit                # 1. tip denetimi
npm test                        # 2. vitest (birim testler)
(cd src-tauri && cargo test)    # 3. Rust birim testleri
(cd cloudflare && npm run check)# 4. wrangler deploy --dry-run
```

**CI'daki karşılığı:** [`.github/workflows/ci.yml`](.github/workflows/ci.yml)
bu dört komutu, aynı sırayla, üç işletim sisteminde çalıştırır.

### ⚠️ Üçüncü komutun bilinen bir boşluğu: `mkvi_core` testleri kapsanmıyor

Rust çekirdeği `crates/mkvi_core` paketine taşındığında **testleri de
taşındı.** `cd src-tauri && cargo test` artık `mkvi_core`'u yalnızca bir
*bağımlılık* olarak derler; kendi `#[cfg(test)]` testlerini **çalıştırmaz.**
Yani dört komutluk gate bugün `crates/mkvi_core/src/` içindeki testleri
kapsamıyor.

CI bu boşluğu kapatmak için, dört komuta ek olarak, açıkça etiketlenmiş bir
beşinci adım çalıştırır:

```bash
(cd crates/mkvi_core && cargo test)   # gate'in parçası DEĞİL, ayrı bir adım
```

**Karar sizin:** Bu adımı gate'in resmî beşinci komutu yapmak isterseniz
`ROADMAP.md`'ye ve `CLAUDE.md`'ye de yazılması gerekir; o dosyalar sizin
sahipliğinizde. Şimdilik CI'da duruyor; böylece çekirdeğin testleri en azından
her koşuda çalıştırılmış olur.

### Bu gate'in iki tuzağı

**a) `cargo test`, `npm run build`'den ÖNCE gelmelidir.**
`tauri::generate_context!()` derleme anında `frontendDist` değerini (`../dist`)
okur. `dist/` `.gitignore`'dadır ve depoda bulunmaz; yoksa `cargo test` derleme
hatasıyla düşer — ve hata mesajı konuyu hiç ima etmez. CI'da bu yüzden Rust işi
içinde `npm run build` **önce** çalıştırılır.

> Bu tuzak yalnızca `src-tauri` için geçerlidir. `crates/mkvi_core` Tauri'ye
> bağlı değildir, `frontendDist` okumaz; `npm run build` olmadan test edilir.

**b) Kök `npm test`, Worker'ın testlerini de toplar.**
Kök `vite.config.ts` içinde bir `test` bloğu ve bir `include` globu **yoktur**;
vitest bu yüzden varsayılan globuyla tüm projeyi tarar ve
`cloudflare/src/index.test.ts` dosyasını da çalıştırır. Bu **kasıtlıdır** ve tek
bir test komutuyla iki paketin de test edilmesini sağlar. Kök `vitest`'e bir
`include` globu eklerseniz Worker testleri sessizce düşer; bunu yapmayın.
(`cloudflare/vitest.config.ts` bunun tersidir: yalnızca `src/**/*.test.ts`
kapsar, çünkü vitest aksi halde yukarı yürüyüp React'in yapılandırmasını
yüklerdi.)

### `npm audit` gate'in parçası değildir

Açık bir depoda her CI çalışması canlı bağımlılık çözümlemesi yapar; bu yüzden
`npm audit` **bilgilendirme amaçlı, engelleyici olmayan** bir adımdır
(`continue-on-error: true`). Denetim temiz değilse PR'ı durdurmayın; sonucu
not düşün.

---

## 4. Bu projede iki sert kural

### Kural 1 — Dosya içeriğini **asla** PowerShell ile yazmayın

Türkçe karakterleri ve JSON'u bozar, dosyalara BOM ekler.

```powershell
# YAPMAYIN — Türkçe ANSI'ye çöker, BOM yazar, Tauri derlemesini kırar
Set-Content -Path dosya.md -Value "Türkçe metin"
Out-File -Path dosya.json -Value $json
$x = Get-Content dosya.md -Raw        # BOM'lu okuma da bozar
```

Kullanın: editör aracınız, `apply_patch`, ya da Node'un `fs` API'si.

**Kurtarma:** `git checkout -- <dosya>` (dosyayı depodaki haline döndürür).

**BOM sonrası bozulması:** Derleme hatası Tauri/TypeScript tarafında "Türkçe
karakterler tanınmıyor" gibi görünür; kök neden BOM'dur.

### Kural 2 — Türkçe stringler UTF-8 ve BOM'suz; kod yorumları İngilizce

- Kullanıcıya görünen **her** metin Türkçedir (arayüz, hata mesajları, loglar).
- Kod yorumları, commit dışındaki teknik notlar ve dokümantasyon İngilizcedir.
  Bu deponun dokümantasyonu (`CONTRIBUTING.md`, `SECURITY.md`, `README.md`
  çevirileri) Türkçedir; Rust/TypeScript kaynak içi yorumlar İngilizcedir.
- Türkçe içeren bir dosyayı düzenledikten sonra **mutlaka** kontrol edin.
  Aranan şey, UTF-8 baytlarının Latin-1/Windows-1254 üzerinden okunmasından
  doğan bozuk Türkçedir. Tipik izler şu kod noktası dizileridir:
  `U+00C3`, `U+00C5`, `U+00C4` ve `U+00E2 U+20AC`.
  **Bu karakterleri buraya harfi harfine yazmıyoruz** — çünkü kontrolü yapacak
  olan dosya (yani bu dosya) kendi kendini kirletmiş olurdu. Onun yerine kod
  noktası kaçışlarını kullanın:

```bash
# Linux/macOS (veya WSL) — grep'in PCRE desteğiyle
grep -nP '[\x{00c3}\x{00c5}\x{00c4}\x{00e2}\x{20ac}]' <dosya>   # çıktı boş olmalı

# Windows PowerShell — dosyayı OKUMAK güvenlidir, yazmak değil
Select-String -Path <dosya> -Pattern '[\u00c3\u00c5\u00c4\u00e2]'
```

Bu depoda Türkçe metin bir kez mojibake'e uğradı ve düzeltmesi ayrı bir iş
oldu. Boş çıktı, `0` eşleşme demektir. Aynı kontrol `CLAUDE.md` ve `ROADMAP.md`
içinde de yazılıdır; orada örnek desen harfi harfine verilmiştir.

Ayrıca: **görünmez karakter içeren regex'i `Edit` ile yazmayın.** Normal ifade
yazarken eşleşmeyi kod noktası karşılaştırmasıyla yapın (bkz. `safeDisplayName`,
`src/services/peer-transport.ts`).

---

## 5. Fork alıyorsanız: değiştirmeniz gereken dört string

MKVI'yi fork'lup kendi adınızla yayımlıyorsanız, aşağıdaki **dört** değeri
mutlaka değiştirin. Değiştirmezseniz sessizce resmi uygulamayla çakışırsınız —
derleme hatası vermez, kullanıcı da farkında olmaz.

| # | Dosya | Değiştirilecek değer (şu an) | Neden zorunlu |
|---|---|---|---|
| 1 | `src-tauri/tauri.conf.json` | `productName`: `"MKVI"` | NSIS kurulum paketi adı, uninstall kaydı ve kısayol adı buradan gelir. Aynı isim iki uygulamanın kayıtlarını ve kaldırma kayıtlarını çakıştırır: birini kaldırmak diğerinin kaydını da bozar. |
| 2 | `src-tauri/tauri.conf.json` | `identifier`: `"com.mkvi.desktop"` | Uygulama veri dizini, `localStorage` ve **paylaşılan WebView2 profili** bu kimlikten türer. Aynı kimlik = aynı yerelStorage = iki uygulama birbirinin durumunu görür. |
| 3 | `crates/mkvi_core/src/security.rs` | `const SERVICE: &str = "app.mkvi.desktop"` | İşletim sistemi anahtar kasasındaki kayıt adı. Değiştirmezseniz **aynı kasada aynı kayıt** kullanılır; cihaz kimliği ve veritabanı anahtarı paylaşılır, yani fork'unuz resmi kurulumun kimliğini sessizce devralır. Kullanıcı iki uygulamayı "farklı uygulama" sanar. |
| 4 | `src-tauri/tauri.conf.json` | `plugins.updater.pubkey` | Güncelleme doğrulama kök anahtarı. Aynı kalırsa fork'unuz **resmi sürüm imzalarını da kabul eder** (güven köprüsü) — ya da tersi, kendi imzalı güncellemelerinizi reddeder. Kendi imza anahtarınızı üretip buraya koymalısınız. |

### Adı değiştirdikten sonra yapmanız gerekenler

- `src/App.tsx` içindeki `localStorage` anahtarları (`mkvi.iceServers` vb.)
  sizin `identifier`'ınızla çakışmasın diye gözden geçirilmeli.
- AAD (ilişkili veri) sabitleri `crates/mkvi_core/src/security.rs` içinde
  (`HISTORY_AAD`) fork'a özgü olmalı; aksi halde eski kayıtlarınız yeni sürümde
  açılamaz.
- `wrangler.jsonc` içindeki `"name": "mkvi-signal"` Worker adını değiştirin;
  aksi halde aynı Worker adına deploy edersiniz.
- Kökteki `VERSION` dosyası tek sürüm kaynağıdır; `app/pubspec.yaml` içindeki
  `version:` alanıyla eşleşmelidir.

---

## 6. Commit ve PR kuralları

- **Commit başlığı Türkçe olur.** Bu deponun geçmişi Türkçe commit'lerden
  oluşuyor; yeni İngilizce başlık geçmişi böler.
- **Tek bir mantıksal değişiklik = tek commit.** Refactor ile davranış
  değişikliğini aynı commit'te birleştirmeyin. Bir commit'te iki bağımsız
  düzeltme varsa, `git reset` ile ayırın.
- Commit'lerde satır 70'i geçmeyin; birinci satır emir kipinde özet, gerekiyorsa
  gövdede **neden** açıklanır.
- **Push kararı bakımcınındır.** Yeşil bir gate'te commit *önerin*; push
  etmeyin. Push, bakımcının onayıyla yapılır.
- PR açarken [PR şablonunu](.github/PULL_REQUEST_TEMPLATE.md) doldurun ve
  **dört komutun çıktısını** ekleyin. "Yeşil" demek yetmez, kanıt istenir.
- CI yeşil değilse PR'da neyi denediğinizi yazın; kapatmayın, düzeltin.

---

## 7. Güvenlik bulguları

PR veya herkese açık issue üzerinden güvenlik açığı bildirmeyin. Bunun yerine
[`SECURITY.md`](SECURITY.md)'deki gizli bildirim kanalını kullanın. Bildirilen
bir zafiyet, düzeltilip yayımlanana kadar herkese açık konuşulmaz.

---

## 8. Sinyalleşme sunucusuna (`cloudflare/`) katkı

`cloudflare/` dizini **AGPL-3.0** altındadır ve bu dizine yaptığınız her katkı
AGPL-3.0 ile dağıtılmış sayılır. Bu, sunucunun barındırma hizmeti olarak
yeniden satılmasını engellemek için seçilmiş bir tasarım kararıdır; hafifletmek
için kaldırmayın.

Bu dizinde değişiklik yapmadan önce [`cloudflare/README.md`](cloudflare/README.md)'yi
okuyun. Özellikle Worker'ın **içerik taşımadığı** ve `isSignalPayload`
beyaz listesinin daraltılmasının kırıcı olduğu kuralına dikkat edin.

---

## 9. Başka bir şey mi arıyorsunuz?

- Ne yapıldığı ve mimari kararlar: `README.md`, `ARCHITECTURE.md`
- Projenin bitirme planı, verilmiş kararlar ve tuzaklar: `ROADMAP.md`
- Sinyalleşme sunucunu kendi hesabınıza kurma: `cloudflare/README.md`
- Güvenlik bildirimi: `SECURITY.md`
