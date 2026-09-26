# 0001 — Arayüz ve kabuk React + Tauri'dan Flutter'a taşınıyor

**Tarih:** 2026-09-26
**Durum:** **Kabul.** Kararın kendisi değişmedi ve değişmeyecek; **koşulu henüz
doğrulanmadı.** Koşulun 2026-09-26 itibarıyla durumu için aşağıdaki
*"Koşulun durumu"* bölümüne bakın.
**Etki:** `app/`, `crates/mkvi_core`, `crates/mkvi_bridge`, `docs/adr/`, emekliye
ayrılmış `0.1.x` Tauri hattı

> Bu bir **karar kaydıdır**, kullanım kılavuzu değildir. Yazıldığı gün doğru olan
> betimlemeleri tarihsel olarak korur; bugünün durumu için `README.md`,
> `ARCHITECTURE.md` ve `ROADMAP.md`'ye bakın.

## Bağlam

MKVI, Tauri 2 + React + Rust ile yazılmıştı. 0.1.4 gerçek Windows cihazlarda iki kişi
arasında denendi ve **on kök neden** çıktı. Bunların ikisi ürünü kullanılamaz hale
getiriyordu:

1. **Kamera ve ekran paylaşımı hiç çalışmıyordu.** Sebep kod değil platformdu: Tauri
   hiçbir WebView2 izin handler'ı kaydetmiyordu ve wry `--disable-features=msWebOOUI`
   ile izin balonunu da kapatıyor. Tauri 2.11.5'te bu için hazır bir API **yok**
   (`tauri-apps/tauri#14753` hâlâ açık). Çözümü elle COM (`ICoreWebView2_4`)
   yazmaktı.
2. **Yeniden bağlanma çalışmıyordu; uygulama beyaz eşleştirme ekranına düşüyordu.**
   Sebep dört ayrı hata: bootstrap hatasının "ilk kurulum" sanılması, Tauri IPC
   korumasının olmaması, keyring boşken **sessizce yeni kimlik** üretilmesi ve
   kalıcı `return` ile ölen yeniden bağlanma döngüsü.

Ayrıca hedef platformlar değişti: Windows tek hedef olmaktan çıktı, Android ikinci hedeef
olarak eklendi (`ROADMAP.md` Faz 6 zaten Flutter + `flutter_webrtc` öneriyordu, ama
Windows'un Tauri'de kalmasını öngörüyordu).

## Karar

Arayüz ve uygulama kabuğu **Flutter**'a taşınır. **Rust çekirdek korunur** ve Tauri'den
tamamen bağımsız bir crate'e (`crates/mkvi_core`) çıkarılır. Sinyalleşme sunucusu
(`cloudflare/`) **hiç değişmez** — zaten platform bağımsız, sıfır bağımlılıklı bir
TypeScript Worker.

```
app/                    Flutter uygulaması (Windows → macOS/Linux → Android)
crates/mkvi_core/       Arayüzden bağımsız çekirdek: Ed25519, keyring, şifreli SQLite, dosya yazımı
crates/mkvi_bridge/     flutter_rust_bridge yüzeyi (tek crate, iki platform)
cloudflare/             Sinyalleşme sunucusu — dokunulmaz
design/tokens.json      Tasarımın tek kaynağı (kontrast testiyle kilitli)
src/, src-tauri/        0.1.x donmuş hat (bugün: emekli); 0.2.0 yayımlandıktan sonra silinir
```

## Kanıt

**Flutter lehine:**

- `flutter build windows --release` bu depoda **143 saniyede** `mkvi_spike.exe` üretti;
  `libwebrtc.m150.7871.02` otomatik indi. Bkz. `docs/manual-test.md` (gün 1-2;
  bu kayıt `spike/README.md`'den kurtarılmıştır, o dosya 2026-09-26'da silindi).
- WebView2 izin duvarı **tamamen ortadan kalkıyor**: `flutter_webrtc` tarayıcı değil,
  native C++ plugin (MF/WASAPI/DXGI). Yani 1 numaralı kök neden taşımayla kendiliğinden
  çözülüyor — elle COM yazmaya gerek kalmıyor.
- `flutter_webrtc` 1.6.2+hotfix.3: 306k indirme, 4.5k yıldız, doğrulanmış yayıncı,
  son 12 ayda Windows'a özel düzeltmeler. Platformlar arası tek WebRTC yığını.

**Flutter aleyhine (kabul edilen riskler):**

- **Windows çalışma anında hiç test edilmiyor.** Plugin her push'ta Windows derliyor ama
  `flutter test` yalnızca Linux'ta koşuyor; 116 açık Windows issue'ı, son 12 günde üç
  çökme düzeltmesi.
- **#2137:** ekran paylaşımı `getDisplayMedia` **başarılı** dönüyor ama track asla kare
  üretmiyor — SDP sağlıklı, ICE `succeeded`, `framesEncoded` hep 0, **hiç hata atmıyor**.
  Dart tarafından tespit edilemiyor. MKVI ekran paylaşımını arama sırasında
  `replaceTrack` ile başlattığı için tam olarak bu yol tetikleniyor.
- **#2205:** HDR ekranda renk bozuk (WGC arka ucu yok). 100% tekrarlanabilir.
- **Rollback** (perfect negotiation) C++ karşılığısız; upstream ister 2021'den beri açık.
- **Çift makineli, doğrulanmış bir Windows örneği yok.** Plugin'in örneği loopback (tek
  süreç) ve CI'da yalnızca derleniyor; resmi demo 19 aydır ölü.

**Tauri'ya karşı (terk etme bedeli):**

- Tauri güncelleme plugin'i ölüyor. Ama **feed'i geçerli kalıyor**: `latest.json` zaten
  resmen doğru şemada ve minisign imzalı, yalnızca istemci değişecek (~150-200 satır Rust,
  `mkvi_core::update`). `updater_flutter`, `flutter_auto_update` ve Sparkle'ın Dart
  karşılıkları pub.dev'de **404** ya da ölü; `self_update` yanlış biçim (Flutter'un
  `flutter_windows.dll`'si süreç boyunca kilitli = dokümanın "rollback" şartı);
  `desktop_updater` Inno istiyor ve Windows kanıtı "candidate-only".
- `keyring` **Android'de hiç yok** — bellek içi mock'a düşüyor, yani daha önce ödenen
  `c411f48` hatasının aynısı. Çözüm: `SecretStore` trait'i (`security.rs:40-43`) zaten
  doğru dikiş; Android'de `flutter_secure_storage`'a beslenen bir implementasyon.
  **Kullanıcı parolası kabul edilmedi** — "kur, bir kez kod gir, bir daha asla" sözünü
  kırardı.

## Sonuçlar

**Kazanılan:** Android ve diğer masaüstü platformları tek kod tabanından; kamera/ekran
izin sorunuunun tamamının bitmesi; Tauri'de iki kez ödenen "izin katmanı" ve "shell
güncelleme" karmaşasının tek tasarımda toplanması.

**Kaybedilen:** Çalışan tek ürün (0.1.x) bir süre daha yan yolda duracak. Bu yüzden
0.1.x **donduruldu, silinmedi.** Silme koşulu ADR'nin sonunda bağlıdır.

> **Güncelleme (2026-09-26):** 0.1.x artık yalnız "dondurulmuş" değil,
> **emekliye ayrılmış** bir hat olarak anılıyor. Üretim düzeltmesi ve yayın
> almayacak.

**Emekti 0.1.x hattı ne zaman silinir:** Flutter 0.2.0 yayınlandıktan ve iki
cihazda gerçek arama + dosya aktarımı geçtikten **sonra**, tek commit'te. Bekleme
süresince `src/` dosyaları Dart portunun **spesifikasyon kaynağı** olarak duruyor
(`src/services/peer-transport.ts` taşınacak mimarinin şeması).

> ⚠️ **Bu iki koşul birbirine bağlıdır ve sıra önemlidir.** "Gerçek arama + dosya
> aktarımı geçti" ifadesi, aşağıdaki koşulun **düz port** sonucuna bağlıdır;
> yani 0.1.x hattının silinmesi kararın koşulunun doğrulanmasına bağlıydı.
>
> **Kayıt (2026-09-26):** koşul doğrulanmadıği hâlde 0.1.x hattı
> (`src/`, `src-tauri/`, kök Vite/TypeScript yapılandırması, `spike/`) **silindi.**
> Bu, "spesifikasyon kaynağı" gerekçesinin artık taşınmadığı anlamına gelir; o
> hatta ait her bilginin nereye yazıldığı `docs/legacy-tauri-line.md`'de
> madde madde kayıtlıdır. **Kararın koşulu bundan etkilenmez** — koşul
> `docs/manual-test.md` ile ölçülecek ve gerektiğinde vendor fork ya da NO-GO
> sonucu doğuracaktır.

## Tersine çevirme koşulu

Bu karar **koşullu** kabul edildi. Karar kuralı, denemeden **önce**
`spike/README.md` içinde sabitlendi ve sonradan oynanmayacak. O dosya
2026-09-26'da silindi; **kuralın ve beş sorunun bugün yaşayan kopyası
`docs/manual-test.md`'dir** ve kelimesi kelimesine korunmuştur.

> **Karar kuralı (aynen):**
>
> - `rollback` çalışıyor mu, SDP parmak izi `getStats` ile aynı mı ve soak'ta
>   çökme var mı — **üçü de olumlu** **ve** 3. soruda **≥8/10 ekran paylaşımı
>   senaryosu** geçiyorsa → **Düz port.**
> - `rollback` bozuksa **ya da** sessiz ekran paylaşımı başarısızlığı
>   (`flutter-webrtc` #2137) tespit edilemiyorsa **ya da** 10 senaryodan
>   **4'ten fazlası** başarısızsa → **Vendor fork**: `flutter_webrtc` path
>   dependency olur, `flutter_screen_capture.cc` içinde `Start()` dönüş değeri
>   yayınlanır, `OnError` iletilir, HDR için WGC arka ucu eklenir.
> - Soak'ta çökme varsa **ya da** dosya aktarımı Tauri'ye göre **%30** geriliyorsa
>   → **Windows'ta NO-GO.** Tauri 0.1.x donmuş hat olarak kalır ve Android
>   atlanır.

> **Not (2026-09-26):** son dal artık **güncel değil** — 0.1.x hattı silindi.
> Bu dal bugün yalnızca şunu demektir: *Windows'ta Flutter'a geçme, Android fazını
> atla ve mimariyi yeniden düşün.* Kararın yönü, eşikleri ve ölçütleri aynen
> geçerlidir. Aynı not `docs/manual-test.md`'de de durur.

### Düzeltme (2026-09-26): "18 senaryo" değil, **10 senaryo**

Bu ADR'nin önceki hâli koşulu *"18 ekran paylaşımı senaryosundan kaçı geçiyor"*
diye yazıyordu. **Bu yanlıştı ve düzeltildi.** Karar kuralı **10** senaryo üzerinden
yazılmıştı: eşik `≥8/10`, vendor fork eşiği "4'ten fazlası başarısız".

Doğrulama ve gerekçe:

- Karar tablosu `spike/README.md:130` ve `:136-140` — *"10 ekran paylaşımı
  senaryosundan kaçı geçti, kaçı sessizce başarısızlıktı?"*, *"3'te ≥8/10
  senaryo geçiyorsa"* ve *"4'ten fazla senaryo başarısızsa"*. Bu satırlar bugün
  `docs/manual-test.md` "Gün 7 · Karar" bölümünde aynen duruyor.
- **18 nereden geldi:** `spike/README.md`'nin gün 3 ve gün 4 satırları protokolü
  18 senaryoya kadar genişletmişti. Yani **18, kararın girdisi değil, protokolün
  son hâlidir**; karar kuralı yazıldığında ölçüt 10 idi ve ölçülecek olan da
  buydu.
- **Neden 10 sayısı korunuyor:** Karar kuralı denemeden **önce** sabitlendi ve
  bunu değiştirmenin kendisi kararı geçersiz kılardı — deneme sonucu görüldükten
  sonra eşiği gevşetmek, eşiği hiç koymamakla aynı şeydir. 18'e yükseltmek de
  aynı hatayı taşır: sonradan oynanan bir eşik, eşik değildir. 10 senaryo
  ayrıca "geçerse" eşiğinin (≥8) anlamlı olduğu tek sayıdır; 18'de ≥8/18
  eşiği ancak ciddi bir başarısızlıkta anlamlı hale gelirdi.

**Sonuç:** koşulun metni 18 → **10** düzeltildi. Kararın kendisi, kanıtı ve
sonuçları değişmedi.

## Koşulun durumu (2026-09-26)

**Koşul hâlâ doğrulanmadı.** `spike/` protokolü bir kez de tam olarak
yürütülmedi; yani "düz port" / "vendor fork" / "NO-GO" üçünden hangisinin doğru
olduğu **bilinmiyor.** Bu, kararın yanlış olduğu anlamına gelmez — karar,
koşulu yerine getirilene kadar **koşullu** olarak durur.

| | Durum |
|---|---|
| Kararın kendisi | **Değişmedi.** Flutter + `flutter_rust_bridge` + korunmuş Rust çekirdek. |
| `spike/` iskeleti | **SİLİNDİ** (2026-09-26). `spike/` altında yalnız README vardı; ölçümler orada yaşıyordu. `.\tool.ps1 spike` artık yalnız prosedürün yerini söyler. |
| **Prosedür** | **Yaşıyor.** `spike/README.md` → `docs/manual-test.md` olarak kurtarıldı; kararın beş sorusu ve karar kuralı orada kelimesi kelimesine duruyor. |
| Ölçüm sayısı | **Sıfır.** Beş sorunun hiçbirine ölçülmüş cevap yok. |

Protokolün taşınma gerekçesi: `spike/` bir **go/no-go probu iskeletiydi** ve
silinecekti; kararın kendisi ise **yaşamaya devam etmelidir** — çünkü koşul
taşınır değil, yerine getirilir. Bir kararın kendisi bir iskeletten daha kalıcıdır.
Bu yüzden iki şey ayrıldı: iskelet silindi, prosedür `docs/manual-test.md` adıyla
yaşamaya devam ediyor.

Taşınan protokol, 0.2.0'ın gerçek yüzeyine göre uyarlandı:

- Soru 1 (`rollback`) ve soru 2 (SDP parmak izi ≡ `getStats` parmak izi) aynen
  kaldı; bunlar doğrudan Faz 4'teki SAS/DTLS işine beslenir.
- Soru 3'ün ölçütü **10 senaryodur** (yukarıdaki düzeltme).
- Soru 4 (dosya aktarımı) ve Soru 5 (soak) aynen kaldı.
- Yeni olarak: **0.2.0'ın köprü gidiş-dönüşü gerçek iki cihazda doğrulanmalıdır**
  — Rust çekirdek geçmişi ve eşi gerçekten açıp yazabiliyor mu. Bunu hiçbir
  otomatik test kanıtlayamaz.
