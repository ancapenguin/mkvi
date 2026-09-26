# MKVI — yol haritası

> Bu dosya projenin **kanonik planıdır**. Sıfır bağlamla açılan bir oturum önce
> `docs/adr/` kararlarını, sonra burayı okuyup işaretlenmemiş ilk kutuya devam eder.
> Kutu bitince `[x]` yap ve altına **tek satır kanıt** yaz (komut çıktısı, commit, test).
> Mimari kararlar `docs/adr/`'de, mimari harita `ARCHITECTURE.md`'de.

## Hedef

İki kişinin (sen + kuzenin) hesapsız, sunucuda içerik tutmayan, kurup unutacağın bir
iletişim uygulaması. **"Bitti" tanımı:**

- Windows'ta iki cihaz kurulumdan sonra **bir kez** kod girer, bir daha asla girmez.
- Mesaj, dosya, sesli/görüntülü arama ve ekran paylaşımı gerçekten çalışır.
- Kimlik doğrulaması uçtan uca güvenlidir (aradaki sunucu okuyamaz, **sunucu
  korsanlığı da ifadeyi değiştiremez**).
- Güncellemeler kendiliğinden iner ve imzayla doğrulanır.
- Windows + macOS + Linux çalışır; Android ikinci hedeftir.
- Herkes kendi sinyal sunucusunu kurabilir; MKVI kimseye hizmet vermez.

## Depo düzeni

```
mkvi/
├── app/                 Flutter uygulaması — Windows → macOS/Linux → Android
├── crates/
│   ├── mkvi_core/       Tauri'dan bağımsız çekirdek (Ed25519, keyring, şifreli SQLite, dosya)
│   └── mkvi_bridge/     flutter_rust_bridge yüzeyi (tek crate, iki platform)
├── cloudflare/          Sinyalleşme sunucusu (Worker + 2 Durable Object) — dokunulmaz
├── design/              tokens.json + generator + kontrast testi (tasarımın tek kaynağı)
├── spike/               Hafta 0 go/no-go probu — port bittikten sonra SİLİNİR
├── docs/adr/            Karar günlüğü
├── src/, src-tauri/     0.1.x DONMUŞ hat — 0.2.0'den sonra SİLİNİR
└── tool.ps1             Tek kapı: `.\tool.ps1 gate`
```

**Katman kuralı:** Dart yalnızca `mkvi_bridge` üzerinden Rust'a dokunur. `mkvi_core`
Tauri bilmez. `cloudflare/` hiçbir şeyi bilmez.

## Öğrenilenler — 0.1.4 gerçek cihazlarda denendi

Bu on kusur **canlı testte** bulundu. Kaynak: kullanıcının canlı test raporu + her biri
için dosya/satır düzeyinde kök neden analizi.

> **Durum sütunu dürüsttür: bu on kusurun hiçbirinde regresyon testi YOK.**
> Doğrulandı: `src/services/peer-transport.test.ts` içindeki 27 testin **tamamı**
> ayrıştırıcı/doğrulama (parseControl, safeName, safeMime, randomTransferId).
> Çağrı durum makinesi, medya, müzakere, yeniden bağlanma, isim, bildirim ve kontrast
> için **sıfır** test var. Bu yüzden aşağıdaki maddeler "kilitlendi" değil,
> **taşınacak gerekliliklerdir**; her biri ilgili fazın çıkış koşulunda teste bağlanır.

| # | Kusur | Kök neden | Durum |
|---|---|---|---|
| 1 | Kamera ve ekran paylaşımı hiç çalışmıyor | Tauri hiçbir WebView2 izin handler'ı kaydetmiyor; wry `msWebOOUI`'yi kapatıyor. Tauri 2.11.5'te API yok | Kök neden Flutter'a geçişle **ortadan kalkıyor**; spike kanıtlıyor (bkz. `spike/`) |
| 2 | Görüntülü arama isteği sessizce sesliye düşüyor | İzin reddi `getUserMedia` zincirinde sessizce yutuluyordu | Kodda kısmen düzeltildi (`e567276`), **testi yok** |
| 3 | Cevap ekranı yok, arama direkt açılıyor | 0.1.4'te otomatik kabul vardı; cevap ekranı hiç yayımlanmamıştı | Kod **var** (`e567276`) ama kullanıcı hiç görmedi, **testi yok** |
| 4 | Yazılar okunmuyor | 17 WCAG ihlali; en kötüsü video placeholder ışık temada **1.17:1**, odak halkası vurguyla aynı (**1.00**) | **Testi yok** — `design/` kontrast testi yazılıyor |
| 5 | Ana sahne kendi kamerana sabit, karşı taraf 126 px'de | Kaynak seçimi `local-camera`'ya sabitlenmiş, uzak kamera gelince geçiş yok | Kodda kısmen düzeltildi, **testi yok** |
| 6 | Sesliyken kamera açılamıyor, kaleyen kamerasını açamıyor | Hata Türkçe olmayan ham `DOMException` metniydi; `acceptCall` medyadan sonra geliyordu | Kodda kısmen düzeltildi, **testi yok** |
| 7 | Takma ad, karşı tarafın gerçek adını eziyor | `App.tsx:119` → `peerAlias \|\| peerAnnouncedName`; ayrıca `ChatCallWorkspace.tsx:490` `aliasIsSet` tuzağı | **AÇIK** — bu satırlar hâlâ aynı, düzeltilmedi |
| 8 | Sağ alt bildirimi gitmiyor, gönder tuşunu kapatıyor | 6 yerden ~saniyede bir yeniden yazılıyor, sayaç hiç dolmuyor; `z-index:100` yazarın üstünde | **AÇIK** — sayaç eklendi ama döngü yeniden yazmaya devam ediyor |
| 9 | Kapat-aç geri bağlanmıyor, beyaz ekrana düşüyor | Bootstrap hatası "ilk kurulum" sanılıyor; Tauri IPC koruması yok; **keyring boşken sessizce yeni kimlik** üretiliyor | **AÇIK** — sessiz kimlik üretimi şu an `mkvi_core`'da kapatılıyor |
| 10 | Güncelleme hiç çalışmıyor | `ancapenguin/mkvi-updates` deposu **404** veriyor (canlı doğrulandı) | **AÇIK** — Faz 7 |


## Verilmiş kararlar

- [x] **Arayüz Flutter.** Tauri 0.1.x donduruldu. Kanıt ve riskler: `docs/adr/0001`.
- [x] **Rust çekirdek korunur**, Tauri'den ayrılıp `mkvi_core` olur. Sinyalleşme
      sunucusu **hiç değişmez**.
- [x] **Lisans:** uygulama `Apache-2.0 OR MIT`; `cloudflare/` **AGPL-3.0** — kimse
      bedava kamu sunucusu işletip markalı hizmet satamaz.
- [x] **Varsayılan sunucu gömülmez.** Herkes kendi Worker'ını kurar; adresi ayarlara
      yazar. Sebep: ücretsiz katmanda bir eşleşme ~115 GB-s DO süresi yiyor
      (~110 eşleşme/gün), sonrası herkes için ölü; ayrıca keyfi kodla DO şişirme
      mümkün ve **kimseye hizmet vermiyoruz**.
- [x] **Tasarımın tek kaynağı `design/tokens.json`.** Kontrast testiyle kilitli;
      özel vurgu rengi, sistem teması, yüksek kontrast, hareket azaltma desteklenir.
- [x] **Güncelleme feed'i korunur** (resmi `latest.json` şeması + minisign imzası).
      Yalnızca istemci değişir: indirme Dart'ta, **doğrulama Rust'ta**.
- [x] **WebRTC sarmalayıcısı alınmaz.** simple-peer/PeerJS/werift bu projedeki
      dört hatayı engellemedi; WebView2 zaten WebRTC içeriyordu. Flutter tarafında da
      `flutter_webrtc` doğrudan kullanılır.
- [x] **UI kütüphanesi, i18n, durum yönetimi alınmaz.** El yazması tema + `ChangeNotifier`.
- [x] **Kullanıcı parolası yok.** "Kur, bir kez kod gir, bir daha asla" sözü korunur;
      Android'de anahtar platform kasasında (`flutter_secure_storage`).
- [x] **Kendi adını kullanıcı belirler**, `profile` mesajıyla karşıya gider. Takma ad
      yalnız yerelde kalır ve asla gerçek adın yerini almaz.

---

## Faz 0 — Karar kapısı (Hafta 0)

- [x] **Flutter spike derlemesi yeşil.** `flutter_webrtc 1.6.2+hotfix.3`,
      `flutter build windows --release` → `mkvi_spike.exe`, **143 sn**,
      libwebrtc `m150.7871.02` otomatik indi. Kanıt: `spike/README.md`.
- [x] **Repo hijyeni.** `.gitattributes` (tek satır sonu kuralı), `.gitignore`
      (Flutter + beyin katmanı), 15 MB ölü feed klonu silindi.
- [x] **Karar günlüğü.** `docs/adr/0001-flutter-migration.md`.
- [ ] **Spike gün 3-7: iki makinede gerçek arama.** Protokol ve **önceden sabitlenmiş
      karar kuralı** `spike/README.md`'de. Sonuç buraya yazılacak.
      *İnsan katılımı gerekiyor: iki cihazda elle deneme.*
- [ ] **Avenox beyin kurulumu** (`avenoxai/avenoxbeyin` v3): `AGENTS.md` + skill'ler.
      Beyin **çalışma hafızası**; bu dosya **kalıcı kararlar**. İkisi karışmaz.

**Çıkış koşulu:** spike karar kuralı "düz port" ya da "vendor fork" demezse Faz 1 başlamaz.

## Faz 1 — Çekirdek ve iskelet

- [ ] **`crates/mkvi_core`:** `security.rs` Tauri'den ayrılır, sıfır Tauri bağımlılığı.
- [ ] **Sessiz sır üretimi kapatılır.** Keyring boşsa ama diskte bir şey varsa **hata**
      verir (`KeyringEntryMissing`), yeni kimlik üretmez. Yazma-okuma `debug_assert`.
- [ ] **`crates/mkvi_bridge`:** `flutter_rust_bridge` yüzeyi, yedi işlev.
- [ ] **`app/`** Flutter iskeleti, köprü tur testi (Windows'ta).
- [ ] **Tek kapı:** `.\tool.ps1 gate` → `flutter analyze` · `dart test` ·
      `cargo test` · `tsc` · `vitest` · `wrangler --dry-run`.
- [ ] **CI** (`ci.yml`) bu kapıyı PR'da koşsun.

**Çıkış koşulu:** `app/` açılıyor, Rust'tan bir değer okuyup Dart'ta gösteriyor, kapı yeşil.

## Faz 2 — Tasarım sistemi ve kabuk

- [x] **`design/tokens.json`** → generator → `tokens.g.dart`. 4 tema × 4 vurgu, 29 rol,
      816 ölçülmüş kontrast oranı, 17 test. Ölçülen en kötü oranlar:
      video placeholder 1.17:1 → **17.11:1**, odak halkası 1.00:1 → **3.28:1**,
      ayırıcı 1.6–2.3:1 → **3.59:1**, ilerleme izi 1.24:1 → **3.59:1**,
      zaman damgası 4.47:1 → **4.99:1**, devre dışı metin 3.20:1 → **4.87:1**.
- [x] **Kapı kırılabilir olduğu kanıtlandı:** iki negatif kontrol yapıldı — odak
      halkası vurguya eşitlenince ve sahne rengi açık yapılınca test kırmızıya
      düştü. Hata mesajı hangi tarihsel kusuru geri getirdiğini adıyla söylüyor.
- [ ] **Vurgu dolu düğme, yükseltilmiş yüzeyde `borderStrong` kenarı alacak.**
      Bu bir token kuralı değil, arayüz kuralı: token testi bunu ölçemez,
      vurgu dolu her düğme `bg`/`surface` üzerinde durmalı, `surfaceRaised`/
      `surfaceSoft` üzerinde ise kenarı olmalı. Kod yazarken uygulanacak.
- [ ] **Sahne kutuplaşması testle korunuyor** (`stage` koyu, `textOnStage` açık,
      her temada) — 0.1.x'teki 1.17:1 sınıfının yapısal olarak geri dönmesini
      engelleyen şey bu.
- [ ] **Ölçek/yoğunluk her yerde** (0.1.x'te `fontScale` ilk ekranlarda etkisizdi).
- [ ] **Üç ekran:** eşleştirme, çalışma alanı, arama.

**Çıkış koşulu:** `dart test` kontrast testleri yeşil; üç ekran tema/vurgu/ölçek
kombinasyonlarında bozulmadan.

## Faz 3 — Sinyalleşme

- [ ] **`rendezvous` Dart'a taşınır**, zarf doğrulama ve ayrışma bildirimiyle.
- [ ] **Ortak golden vector:** TS ve Dart aynı dosyadan aynı testi koşar. 0.1.x'teki
      base64 alfabesi ve UUID biçimi hataları tam olarak bu eksiklikten doğdu.
- [ ] **Worker sözleşme testleri** CI'da.

## Faz 4 — Kimlik, eşleştirme, geri bağlanma

- [ ] **Faz 1 güvenlik açığı kapatılır:** SAS ifadesi DTLS parmak izine bağlanır
      (SDP'den veya `getStats`'ten — spike gün 3 hangisini verirse). Sinyal
      sunucusunu kontrol eden biri artık iki tarafa da aynı ifadeyi gösteremez.
- [ ] **`SetupState`:** ilkKurulum / yenidenBağlanıyor / bozuk. **Beyaz ekran yalnız ilk
      kurulumda.**
- [ ] **Keyring hataları yüzeye çıkar**, sessizce yeni kimleme düşmez.
- [ ] **İsimler:** ilan edilen ad yetkili, takma ad ikincil ve yalnız yerelde;
      yeniden eşleşmede "Kişi"ye düşme yok.

## Faz 5 — Arama

- [ ] **Cevap / Reddet** ekranı; **iki tarafta da** 45 sn zil zaman aşımı; cevapsız
      arama kaydı; `call-declined` işlenir.
- [ ] **Kabul medyadan önce** — diyalogun verdiği sözün tutulması.
- [ ] **Kamera/mikrofon/ekran:** cihaz değiştirme, hata sınıflandırması (Türkçe),
      **arama sırasında kamerayı açma**, sesli→görüntülü yükseltme.
- [ ] **Ekran paylaşımı için "ilk kare bekleniyor" durumu.** Plugin sessizce boş
      track verebiliyor (`#2137`); `outbound-rtp.framesEncoded` izlenmeli.
- [ ] **PiP kendi görüntü + tam ekran**, uzak kamera gelince otomatik geçiş.

## Faz 6 — Sohbet ve dosya

- [ ] Mesaj listesi + geçmiş (şifreli SQLite), gönderme durumu.
- [ ] Dosya aktarımı çekirdek üzerinden akışlı yazım, ilerleme, iptal, çakışma yok.

## Faz 7 — Güncelleme, dağıtım, açık kaynak

- [ ] **Yayın anahtarı yeniden üretilmeli (prehashed).** Doğrulandı: `tauri.conf.json`
      içindeki anahtar minisign'in **eski `Ed`** biçiminde. Katı doğrulayıcı her
      `ED` imzasını kabul eder, ama bu anahtar yalnız `Ed` imzası üretebilir — yani
      doğrulama sessizce her şeyi reddederdi. `mkvi_core::update` artık bunu
      `LegacyKey` hatası olarak **adıyla** söyler (testli), ama kök çözüm yeni bir
      `tauri signer generate` ile prehashed anahtar + `TAURI_SIGNING_PRIVATE_KEY`
      secret'ının yenilenmesidir.
      **Sonuç:** 0.1.x istemcileri kendini güncelleyemez (zaten ölü feed yüzünden
      edemiyorlardı) — ilk Flutter sürümü elle kurulur.
- [ ] **`mkvi_core::update`:** `latest.json` oku → sürüm karşılaştır → indir →
      **imzayı doğrula** → kur. Doğrulama indirilen baytın **tamamı** üzerinde,
      bayt bayt kontrolsüz geçilemez. *(Çekirdek kısmı yazıldı: 24 test.)*
- [ ] **`release.yml`:** etiketle tetiklenir, taslak yayın, sürüm üç dosyada eşleşmeli.
- [ ] **Feed GitHub Releases'e taşınır** → `mkvi-updates` deposu ve deploy anahtarı
      emekli. `ancapenguin/mkvi` **public** olunca updater endpoint'i
      `releases/latest/download/latest.json` olur (resmi Tauri yöntemi).
- [ ] **Public'a çıkış:** lisanslar, `SECURITY.md` (özel bildirim kanalıyla),
      `CONTRIBUTING`, `CODE_OF_CONDUCT`, `THIRD-PARTY-NOTICES`, `cloudflare/README.md`.
- [ ] **Yanlış iddialar düzeltilir:** README "tek kullanımlık kod" diyor (aslında kayan
      pencere, `MAX_ADMISSIONS = 8`); CLAUDE "CSP daraltıldı" diyor (aslında `https:`
      jokeri *genişletilmiş*); "0.1.4 indirilebilir" diyor (link ölü).

**Çıkış koşulu:** 0.2.0 yayında, iki cihazda kendiliğinden güncelleniyor.

## Faz 8 — Ölü kodun temizliği

- [ ] **`spike/` silinir** (port bittikten sonra).
- [ ] **`src/`, `src-tauri/` silinir** — 0.2.0 yayınlandı ve iki cihazda gerçek arama
      + dosya aktarımı geçtikten **sonra**, tek commit'te. O güne kadar bunlar Dart
      portunun **spesifikasyon kaynağıdır**; silinmez.
- [ ] `index.html`, `vite.config.ts`, `tsconfig*`, `package.json` (kök) Tauri ile birlikte gider.

## Faz 9 — Android

- [ ] `keyring` Android'de yok → `flutter_secure_storage` beslemeli `SecretStore`.
- [ ] Ekran paylaşımı **MediaProjection** ister; `getDisplayMedia` Android WebView
      eşdeğeri değildir.
- [ ] Kamera/mikrofon izin akışı ve kalıcı izin iptali.

---

## Çalışma kuralları (acıyla öğrenildi)

- **Tam kapı yeşil olmadan commit önerme:** `.\tool.ps1 gate`.
- **DOSYA İÇERİĞİNİ ASLA PowerShell İLE YAZMA.** `Get-Content -Raw` Türkçeyi bozar,
  `Set-Content -Encoding utf8` BOM yazar ve derlemeyi kırar. Kurtarma:
  `git checkout -- <dosya>`. Bayt seviyesinde yamalar (ör. ham NUL → `\0`) istisnadır,
  çünkü yeniden kodlama yapmaz.
- **Türkçe metin UTF-8, BOM'suz.** Bir dosyayı düzenledikten sonra
  `grep -n 'Ã\|Å\|Ä' <dosya>` çalıştır; çıktı boş olmalı.
- **Kod yorumları İngilizce**, kullanıcıya görünen her string Türkçe.
- **Worker içerik taşımaz.** `isSignalPayload` anahtar bazında beyaz liste kullanır.
  Yeni alan eklemek Worker'ı içerik tüneline çevirir; gerekçesiz genişletme.
- **Protokol daraltmak kırıcıdır.** `isSignalPayload`'dan alan çıkarmak, o alanı hâlâ
  gönderen eski istemcileri `close(1008)` ile düşürür.
- **Özel kripto yazma.** Yalnız denetimli crate'ler (`ed25519-dalek`,
  `chacha20poly1305`). Yeni şema gerekiyorsa önce sor.
- **Ajanlar commit atmaz, push atmaz.** Her dosyanın tek sahibi olur; sahiplik
  çakışması iki ajanın işini birbirine ezdirir. Commit'i lead engineer yapar.
- **Lane/ajan raporu iddiadır, kanıt değil.** Her iddia kodda veya resmî dokümanda
  doğrulanır.
