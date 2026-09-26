# Yayın imzası — anahtar üretimi, saklama ve doğrulama

> **Bu belge bir kullanım kılavuzudur ve bir karar kaydıdır.** Yazan ajan
> değil, lead engineer; ajanın ürettiği kanıt (`app/test/update/sign_compat_test.dart`,
> 12 test) ve ölçümler temel alındı.

## Durum: yayın imzası çalışmıyor, ve nedeni ölçülmüş

0.2.0'ın doğrulaması **katı**: `crates/mkvi_core/src/update.rs:116` `allow_legacy`'i
sabit `false` yapıyor, `:103-105` legacy anahtarı doğrulamadan **önce** reddediyor.

Depodaki anahtar `Ed` (emekli) biçiminde. Bayt düzeyinde doğrulandı:
`0x45 0x64` = `Ed`. Yani **bu anahtarın ürettiği her imza reddedilir.**

Bu bir engeldir, ama 0.1.x'i engellemiyordu. Ölçüldü:
`tauri-plugin-updater` 2.10.1 `src/updater.rs:1461`'de
`public_key.verify(data, &signature, true)` çağırıyor, yani `allow_legacy = true`;
`minisign-verify` 0.3.0 her iki etiketi de kabul ediyor (`lib.rs:296-299`).
**0.1.x'i öldüren şey legacy anahtar değil, ölü feed'di** (404). Anahtar ters yönde
engel: 0.2.0'ı engelliyor.

## Uyumluluk kanıtlandı (testli)

`app/test/update/sign_compat_test.dart` — resmî minisign fixture'ı üzerinde:

- `.sig` dosyası formatın istediği dört satırı taşıyor.
- İmza `ED` etiketli — MKVI'nin kabul ettiği **tek** biçim.
- Genel anahtar 42 bayt ve `Ed` etiketli, **formatın dediği gibi**.
- İmzadaki key id, anahtardaki key id ile aynı.
- MKVI'nin okuyucu kuralları resmî baytlara uygulandığında: imza okunuyor ve
  algoritma kabul ediliyor; iki anahtar biçimi de farklı dallardan çözülüyor;
  kanonik base64 dolgusu taşıyıcı, süs değil.
- **Kayıt altına alındı:** `update.rs:129` resmî anahtarı "legacy" diye adlandırıyor
  ve **etiket iki biçim arasındaki tek fark**.

Yani: MKVI'nin doğrulayıcısı resmî minisign çıktısını **anlıyor**. Sorun okuyucuda
değil, depodaki anahtarda.

## Anahtar üretimi — SENİN KONTROLÜNDE, BU BELGE ÇALIŞTIRMAZ

> **Bu turda gerçek anahtar üretilmedi.** Üretmek ve saklamak ayrı, kullanıcının
> kontrolünde bir adımdır.

**1. Prehashed üret.** `minisign` CLI'nın `-W` (prehash) seçeneğiyle ya da
Tauri signer ile. Doğrulama şart: üretilen `.pub` dosyasının 2. satırının ilk 2
baytı `45 44` (`ED`) olmalı. `45 64` (`Ed`) ise emekli biçimdir ve reddedilir.

```
minisign -W -s mkvi-release -c "MKVI yayın anahtarı"
# veya
npx tauri signer generate -w mkvi-release
```

**2. Saklama — üç yer, üç kural.**

| Varlık | Nerede | Kural |
|---|---|---|
| Genel anahtar (`.pub`) | Depoda, `app/` derlemesine `--dart-define=MKVI_UPDATE_KEY_B64` ile gömülür | Gizli **değildir** — istemci imzayı doğrulamak için gömmek zorunda. Ama **elle değiştirilemez** olmalı |
| Özel anahtar (`.key`) | Yalnız senin makinende, `.secrets/` altında | **Depoya girmez, CI'a girmez.** `.gitignore` bunu zaten koruyor (`*.key`, `*.secrets/`) — ölçüldü, sır taraması temiz |
| Yedek | Ayrı bir yerde, şifreli | Kimlik kaybı = imzasız her sürüm; anahtar sızıntısı = her sürümü imzalayabilen biri |

`TAURI_SIGNING_PRIVATE_KEY` ve `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` GitHub secret
olarak **yalnız imzalama adımına** konur. Derlemeye değil, `release.yml`'in imzalama
adımına.

**3. Derlemeye verme.** `update_config.dart:78-82` bu değeri `String.fromEnvironment`
ile okuyor ve **varsayılanı yok** — bilinçli. Yer tutucu bir anahtar
`isConfigured` için "tamam" görünür ama hiçbir şey doğrulamazdı.

```
flutter build windows --release \
  --dart-define=MKVI_VERSION=0.2.0 \
  --dart-define=MKVI_UPDATE_KEY_B64=<genel anahtarın base64'ü>
```

**4. Yerelde doğrula, sonra yayınla.** `tools/verify-signature.ps1` indirilen
artefaktı Rust çekirdeğin kendi doğrulayıcısıyla sınar. Yayınlamadan önce
`tools/mkvi-sign.ps1` çıktısının `.sig` dosyasını doğrula.

## İki yaklaşımın karşılaştırması

| | Resmî `minisign` CLI | `update.rs:373-402`'deki test imzalayıcısını üretime çıkarmak |
|---|---|---|
| Güvenlik yüzeyi | Bağımsız uygulama, kendi test kapsamı var | Bizim kodumuz; hata bizim hatamız |
| Bakım | Sürüm/politika bize bağlı, `Cargo.lock` ile sabitlenmez | `Cargo.lock` ile sabitlenir, `ed25519-dalek` zaten onaylı |
| Denetlenebilirlik | Referans implementasyon | `update.rs:415-418` zaten `verify_artifact`'a geri besleyip geçiyor |
| Yayın otomasyonu | CI'da binary kurmak gerekir | `cargo run` — zaten toolchain var |

**Karar henüz verilmedi.** Tavsiye: önce CLI'yi dene, çalışmıyorsa (kurulum/
platform sorunu) test imzalayıcısını üretime taşı. İkisi de `minisign-verify` ile
aynı baytları üretiyor — uyumluluk testi zaten bunu kanıtlıyor.

## Bu turda yapılmayanlar

- Gerçek anahtar üretilmedi
- GitHub secret'ı yazılmadı
- `release.yml`'e imzalama adımı eklenmedi (dosyada `TODO` olarak duruyor, gerekçesi
  yazılı)
- `docs/adr/0003-library-decisions.md` §"karar gerektirenler"de `sha2` maddesi duruyor
