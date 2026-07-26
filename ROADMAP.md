# MKVI — bitirme yol haritası

> Bu dosya **kararların kalıcı kaydıdır**. Sıfır bağlamla açılan bir oturum, `CLAUDE.md`'deki
> handoff'u okuduktan sonra buraya bakıp sıradaki kutuyu işaretleyerek devam edebilmelidir.
> Bir madde bittiğinde `[ ]` → `[x]` yap ve altına tek satır kanıt yaz (komut çıktısı, commit).

## Hedef (goal)

İki kişinin (sen + kuzenin) hesapsız, sunucuda içerik tutmayan, kurup unutacağı bir
iletişim uygulaması. **"Bitti" tanımı:**

- Windows'ta iki cihaz kurulumdan sonra **bir kez** kod girer, bir daha asla girmez.
- Mesaj, dosya, sesli/görüntülü arama ve ekran paylaşımı çalışır.
- Kimlik doğrulaması gerçekten uçtan uca güvenlidir (aradaki sunucu okuyamaz).
- Güncellemeler kendiliğinden iner.
- Android kararı verilmiş ve gerekçesi yazılmıştır.

## Durum (2026-07-27)

Sürüm 0.1.4, 4 commit yerelde, **push edilmedi**. Gate yeşil: `tsc` · 58 test · cargo 6/6 ·
worker dry-run. **İndirilebilir tek sürüm hâlâ 0.1.2 ve onda sohbet çalışmıyor.**

---

## Faz 0 — Yayın (her şeyin önünde)

- [ ] **0.1.4'ü yayınla.** `git push` + `git tag v0.1.4 && git push origin v0.1.4`.
      Kabul: `gh run list --limit 1` yeşil, ve
      `https://raw.githubusercontent.com/ancapenguin/mkvi-updates/main/windows-x86_64/MKVI_0.1.4_x64-setup.exe`
      200 + `MZ` başlığı döndürüyor. **Bu düzeltilmiş workflow CI'da hiç çalışmadı; ilk yeşil
      derleme onu doğrulayacak.**
- [ ] **Kuzenle canlı dene ve sonucu yaz.** Tek teşhis verisi hangi ekranda takıldıkları.
      Özellikle: uygulamayı kapat-aç, kod istemeden bağlanıyor mu? (keyring düzeltmesinin
      gerçek testi budur.)
- [ ] **Arayüzü gerçek pencerede gör.** İlerleme çubuğu, "Sen: <ad>" rozeti, arama sırasında
      sohbetin yan panel olması. Tarayıcıda test edilemez (`loadDeviceIdentity` Tauri komutu).

## Faz 1 — Güvenlik açığını kapat (Android'den önce zorunlu)

- [ ] **SAS'i DTLS parmak izine bağla.** Şu an ifade yalnızca
      `transcript | sıralı açık anahtarlar` özeti (`src/App.tsx`, `handleIdentity`); SDP'yi ve
      DTLS sertifika parmak izlerini kapsamıyor. Sinyalleşme sunucusunu kontrol eden biri araya
      girip iki tarafa da **aynı ifadeyi** gösterebilir.
      Yapılacak: `RTCPeerConnection.getStats()`'ten yerel/uzak DTLS parmak izlerini al, SAS
      girdisine ekle, ve ifadeyi ancak parmak izleri belli olduktan sonra göster.
      Kabul: parmak izi değiştirilmiş sahte bir eş ile ifadelerin **farklı** çıktığını gösteren
      birim testi.
- [ ] **Alternatif değerlendirildi mi:** `snow` (Noise) ile el sıkışıp SAS'i el sıkışma
      özetinden türetmek daha temiz ama daha büyük iş. Önce yukarıdaki minimal bağlama yapılsın.

## Faz 2 — Sinyalleşme protokolünü sağlamlaştır

Dört üretim hatasının üçü buradaydı. Kütüphane yok; alınacak olan **Magic Wormhole'un tasarımı**.

- [ ] **Kiralama (lease) modeline geç.** `cloudflare/src/index.ts:102` `disconnect()` `admitted`
      sayacını azaltmıyor; `MAX_ADMISSIONS = 8` çözüm değil erteleme. Aynı fonksiyonda
      `setAlarm` her girişte sıfırlandığı için "15 dakikalık tek kullanımlık kod" aslında
      **kayan pencere**. Kabul: kapanan bağlantı yerini bırakıyor + kod oluşturulduktan
      15 dk sonra kesin ölüyor, testle kilitlendi.
- [ ] **Zarflara sıra numarası + onay (ack) ekle.** `src/services/rendezvous.ts`'te mesaj
      kimliği, ack veya tekrar oynatma yok; iki taraf da "bağlı" görünürken kaybolan bir sinyal
      hâlâ el sıkışmayı kilitleyebilir. Kabul: kaybolan zarfı simüle eden test.
- [ ] **Tek kanonik tel sözleşmesi.** Rust, tarayıcı TS ve Worker aynı golden vector
      dosyasından geçsin. Base64 alfabesi ve UUID formatı hataları tam olarak bunun
      yokluğundan doğdu. Kabul: üç tarafta da çalışan ortak vektör dosyası.

## Faz 3 — Profil fotoğrafı (onaylandı)

- [ ] **Yerel seçim + küçültme.** `createImageBitmap` (EXIF yönünü kendi çözer) → canvas ile
      256×256 merkez kırpma → **WebP** (JPEG geri dönüşlü). Yeniden kodlama EXIF/GPS'i
      kendiliğinden siler; gizlilik gereği budur, ayrı EXIF kütüphanesi **alma**.
- [ ] **Aktarım.** `profile` kontrol mesajı 32 KB sınırına takılır → `FILE_FRAME` desenine
      benzer ayrı bir ikili nesne çerçevesi. `parseControl`'e ham base64 **gömme**.
- [ ] **Saklama.** Şifreli SQLite'ta BLOB. Sunucuya hiçbir şey gitmez.

## Faz 4 — Yerel veri sertleştirme

- [ ] **SQLCipher'a geç.** `rusqlite`'ın bundled SQLCipher özelliği var. Şu anki uygulama
      katmanı şifrelemesi journal/WAL verisini korumuyor. Anahtar OS kasasında kalır.
      **Geçmiş şeması büyümeden yap.** Kabul: eski veritabanından geçiş yolu + test.

## Faz 5 — Test altyapısı

- [ ] **Playwright duman testi.** jsdom CSS grid geometrisini yakalayamaz — 0.1.3'teki bozuk
      iki panelli düzeni ancak gerçek tarayıcı görürdü. Kabul: iki panelli düzen ve sayfa
      kaymaması test ediliyor.
- [ ] **Türkçe stringler için tipli katalog.** i18n kütüphanesi **alma**; tek dil için tipli
      bir sabit nesne yeterli, ikinci dil gerekirse yeniden yazım gerektirmez.

## Faz 6 — Android

- [ ] **Kararı ver ve yaz.** Araştırmanın önerisi: **Android için Flutter + `flutter_webrtc` +
      `flutter_rust_bridge`; Windows Tauri'de kalır; Rust çekirdeği çerçeveden bağımsız bir
      crate'e çıkarılır.** Gerekçe: Android WebView'da `getDisplayMedia()` yok, ekran paylaşımı
      MediaProjection ister ve native pikselleri WebView'ın `RTCPeerConnection`'ına bağlamanın
      standart yolu yok — "küçük bir Kotlin eklentisi" ikinci bir WebRTC yığınına dönüşür.
      Maliyet: TypeScript'in %0'ı taşınır, Rust mantığının ~%80-90'ı yaşar.
      **Ucuz alternatif:** yalnızca ön planda çalışan, ekran paylaşımsız bir Tauri Android
      denemesi 3-7 gün. Önce bu yapılıp gerçek cihazda görülebilir.
- [ ] **Rust çekirdeğini crate'e çıkar** (karardan bağımsız olarak faydalı):
      `load_identity` / `sign` / `open_history` / `store_message` / dosya yazımı Tauri
      tiplerinden arındırılsın. `src-tauri/src/lib.rs` şu an `AppHandle` ile bağlı.
- [ ] **TURN'ü yeniden değerlendir — yalnız bu fazda.** Mobilde CGNAT, simetrik NAT ve UDP
      engelli kurumsal Wi-Fi yüzünden TURN pratikte zorunlu hale gelir. Masaüstü kararı
      değişmedi. **Masaüstü için bu konuyu açma.**

## Faz 7 — Dağıtım

- [ ] **SmartScreen kararı.** Azure Artifact Signing ~9,99 USD/ay (5.000 imza).
      **SignPath Foundation ücretsiz ama gerçek açık kaynak şartı var — repo private olduğu
      için uygun değiliz.** sigstore SmartScreen'i değiştirmez. Karar kullanıcının.

---

## Verilmiş kararlar (yeniden tartışma)

- [x] **WebRTC sarmalayıcısı ALINMAYACAK.** simple-peer / PeerJS / libdatachannel / werift
      bu projede çıkan dört hatanın hiçbirini engellemezdi. WebView2 WebRTC'yi zaten içeriyor.
- [x] **iroh ALINMAYACAK** (şimdilik). Uç nokta kimliği takasını yine bize bırakıyor,
      çevrimdışı posta kutusu yok, medya WebRTC'de kalacağı için iki ayrı taşıma demek.
      `iroh-blobs` yalnızca "dosya kaldığı yerden devam etsin" gerçek gereksinim olursa.
- [x] **Matrix / Tailscale / libp2p / Veilid / Waku: hayır.** İlk ikisi hesap veya tailnet
      ister, "hesapsız" premisini siler; diğerleri iki cihaz için fazla ağır.
- [x] **UI kütüphanesi ALINMAYACAK.** Radix / shadcn / Mantine / i18next / Zustand — iki ekran
      için hepsi gereksiz. El yazması CSS ve yerel HTML kontrolleri kalıyor.
- [x] **TURN masaüstünde kapalı.** Yalnızca "ifade ekranı geldi ama bağlanmadı" gerçek
      denemesiyle veya Android fazında açılır.
- [x] **`mkvi-updates` deposu olduğu gibi kalacak** (her sürümde ~3,8 MB büyür).
      `mkvi` public yapılmayacak, PAT eklenmeyecek.
- [x] **Profil fotoğrafı yapılacak** (Faz 3).
- [x] **Kendi adını kullanıcı belirler**, karşı tarafa `profile` mesajıyla gider; takma ad
      yerelde kalır ve onu ezer.

## Bitmiş işler

- [x] **Yeniden bağlanma el sıkışması varlık olayına bağlandı** (`150cc6e`) — oda posta kutusu
      tutmuyor, çevrimdışı tarafa atılan zarf çöpe gidiyordu.
- [x] **Kimlik doğrulanmadan gelen sinyaller kuyruğa alınıyor** (`150cc6e`) — eskiden atılıyordu.
- [x] **Cihaz anahtarı gerçek OS kasasına bağlandı** (`c411f48`) — `keyring 3` varsayılan
      özelliksiz bellek içi mock store kullanıyordu; kimlik ve DB anahtarı hiç kalıcı değildi.
- [x] **WebView2 "Suggestions" kapatıldı** (`c411f48`) — `generalAutofillEnabled: false`;
      `autocomplete="off"` tek başına yetmiyor (Tauri şeması bunu açıkça yazıyor).
- [x] **Dosya aktarımı ilerleme çubuğu** (`150cc6e`).
- [x] **Mikrofonsuz cihazda arama düşmüyor** (`150cc6e`) — yalnız-video'ya geriliyor.
- [x] **Yayın workflow'u onarıldı** (`150cc6e`) — `$env:VERSION` tanımsızdı, installer feed
      reposuna hiç kopyalanmıyordu.
- [x] **Worker'a ilk testler** (`150cc6e`) — 12 test, base64 alfabesi ve daraltma koruması.

---

## Çalışma kuralları (bu projede acı çekilerek öğrenildi)

- **Codex `sol` modeli yalnızca fikir alışverişi/araştırma içindir.** Mekanik kod lane'lerinde
  `gpt-5.6-terra`, önemsiz işlerde `gpt-5.6-luna` kullan.
- **Codex bu makinede MEVCUT DOSYAYI DÜZENLEYEMİYOR.** `apply_patch` Windows PowerShell
  tırnaklamasında bozulup `Invalid patch: The last line of the patch must be '*** End Patch'`
  veriyor. **Ama sıfırdan yeni dosya oluşturabiliyor.** Lane'lere yalnızca "yeni dosya yaz"
  işi ver; mevcut dosya düzenlemesini Edit ile kendin yap. Sandbox'ı kapatmak bunu çözmez.
- **Arka planda `codex exec` çalıştırırken `< /dev/null` şart**, yoksa stdin'de asılır.
  `--full-auto` deprecated; `--sandbox workspace-write` veya `--sandbox read-only` kullan.
- **Read-only araştırma lane'leri sorunsuz çalışıyor** ve web araması yapabiliyorlar.
- **DOSYA İÇERİĞİNİ ASLA PowerShell İLE YAZMA — sadece Edit.** `Get-Content -Raw` Türkçeyi
  ANSI okuyup mojibake yapar; `Set-Content -Encoding utf8` JSON'a BOM yazıp Tauri derlemesini
  kırar. Kurtarma: `git checkout -- <dosya>`.
- **Görünmez karakter içeren regex'i Edit ile yazma** — kod noktası karşılaştırması kullan
  (bkz. `safeDisplayName`, `src/services/peer-transport.ts`).
- **Lane raporu iddiadır, kanıt değil.** Bu oturumda üç lane'in üç iddiası da doğrulandı ama
  daha önce bir lane sessizce yanlış kod üretmişti. Her iddiayı kodda veya resmî dokümanda
  doğrula.
- **Türkçe dosya düzenledikten sonra** `grep -n 'Ã\|Å\|Ä' <dosya>` çalıştır; çıktı boş olmalı.
- **Tam gate:** `npx tsc --noEmit` · `npm test` · `cd src-tauri && cargo test` ·
  `cd cloudflare && npm run check`. Dördü yeşil olmadan commit önerme.
