# 0001 — Arayüz ve kabuk React + Tauri'dan Flutter'a taşınıyor

**Tarih:** 2026-09-26
**Durum:** Kabul (koşullu: `spike/` geçişi doğrular)
**Etki:** `app/`, `crates/mkvi_core`, `crates/mkvi_bridge`, `docs/adr/`, donmuş `0.1.x` hat

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
crates/mkvi_core/       Tauri'dan bağımsız çekirdek: Ed25519, keyring, şifreli SQLite, dosya yazımı
crates/mkvi_bridge/     flutter_rust_bridge yüzeyi (tek crate, iki platform)
cloudflare/             Sinyalleşme sunucusu — dokunulmaz
design/tokens.json      Tasarımın tek kaynağı (kontrast testiyle kilitli)
src/, src-tauri/        0.1.x donmuş hat; Flutter 0.2.0 yayınlandıktan sonra silinir
```

## Kanıt

**Flutter lehine:**

- `flutter build windows --release` bu depoda **143 saniyede** `mkvi_spike.exe` üretti;
  `libwebrtc.m150.7871.02` otomatik indi. Bkz. `spike/README.md`.
- WebView2 izin duvarı **tamamen ortadan kalkıyor**: `flutter_webrtc` tarayıcı değil,
  native C++ plugin (MF/WASAPI/DXGI). Yani 1 numaralı kök neden taşımayla kendiliğinden
  çözülüyor — elle COM yazmaya gerek kalmıyor.
- `flutter_webrtc` 1.6.2+hotfix.3: 306k indirme, 4.5k yıldız, doğrulanmış yayıncı,
  son 12 ayda Windows'a özel düzeltmeler. Platformlar arası tek WebRTC yığını.
- **Bu karar yeni değil.** Aynı fikrin önceki denemesi olan `oxide`'de (Rust/axum sunucu)
  istemci zaten Flutter olarak planlanmıştı. Yani Flutter'a geçiş, bu makinede en az iki
  kez denenmiş bir karar. Bkz. `beyin/knowledge/mkvi-kapsam-karari.md`.

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
0.1.x **donduruldu, silinmedi** — kuzen onu kullanmaya devam ediyor. Silme koşulu
ADR'nin sonunda bağlıdır.

**Dondurulan 0.1.x hattı ne zaman silinir:** Flutter 0.2.0 yayınlandıktan ve iki
cihazda gerçek arama + dosya aktarımı geçtikten **sonra**, tek commit'te. Bekleme
süresince `src/` dosyaları Dart portunun **spesifikasyon kaynağı** olarak duruyor
(`src/services/peer-transport.ts` taşınacak mimarinin şeması).

## Tersine çevirme koşulu

Bu karar **koşullu**. `spike/README.md` içindeki 7 günlük protokol ve **karar
kuralı** (önceden sabitlendi, sonradan oynanmayacak) şunları arıyor: `rollback`
çalışıyor mu, SDP parmak izi `getStats` ile aynı mı, 18 ekran paylaşımı senaryosundan
kaçı geçiyor, dosya aktarımı Tauri'ye göre ne durumda, soak'ta çökme var mı.

`rollback` bozuksa veya sessiz ekran paylaşımı başarısızlığı tespit edilemiyorsa
→ `flutter_webrtc` **vendor** edilir (path dependency + C++ yaması).
Soak'ta çökme varsa veya aktarım %30 geriliyorsa → **Windows'ta NO-GO**, Tauri 0.1.x
dondurulmuş hat olarak kalır ve Android atlanır.
