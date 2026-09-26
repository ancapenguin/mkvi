<!--
  Türkçe PR şablonu. GitHub bu dosyayı PR gövdesine olduğu gibi yerleştirir.
  Uyum kuralları: Türkçe stringler UTF-8 ve BOM'suz, kod yorumları İngilizce.
-->

## Ne değiştirdiniz

<!-- Tek cümle, emir kipi. -->

## Neden

<!-- Hangi sorunu çözüyor. "İyileştirme" demek yetmez; hangi durumda, neden
     rahatsız edici olduğunu yazın. -->

## İlgili issue

<!-- Closes #12 gibi bir bağlantı. Yoksa "Yok" yazın. -->

## Gate — dört komut

<!-- Commit önermeden önce dördü de yeşil olmalı. Çıktıyı yapıştırın, "yeşil"
     demek kanıt değildir. -->

```
npx tsc --noEmit                 → ?
npm test                         → ?
cd src-tauri && cargo test       → ?
cd cloudflare && npm run check   → ?
```

## Değişiklik türü

- [ ] Yalnızca arayüz (`src/`)
- [ ] Rust tarafı (`src-tauri/`)
- [ ] Sinyalleşme Worker'ı (`cloudflare/` — **AGPL-3.0** kapsamında)
- [ ] Bağımlılık / `Cargo.lock` / `package-lock.json`
- [ ] Dokümantasyon
- [ ] CI, Dependabot, şablonlar
- [ ] Lisans veya bildirim dosyaları (`LICENSE-*`, `NOTICE`, `THIRD-PARTY-NOTICES.md`)

## Kontrol listesi

- [ ] Kullanıcıya görünen her yeni metin **Türkçe** ve **BOM'suz**
- [ ] Kod yorumları **İngilizce**
- [ ] Yeni bağımlılık eklendiyse `THIRD-PARTY-NOTICES.md` güncellendi
- [ ] Lisans değişikliği yapıldıysa `NOTICE` ve `cloudflare/LICENSE` gözden geçirildi
- [ ] `cloudflare/` altındaysa: Worker hâlâ **içerik taşımıyor**,
      `isSignalPayload` beyaz listesi keyfiyetle genişletilmedi
- [ ] Protokol daraltması yok (daraltmak eski istemcileri düşürür)
- [ ] Sürüm numarası (`package.json`, `src-tauri/tauri.conf.json`, `Cargo.toml`) gerekirse güncellendi
- [ ] Türkçe içeren dosyalar mojibake kontrolünden geçti
- [ ] Commit başlıkları Türkçe ve her commit tek bir mantıksal değişiklik

## Ekran görüntüsü (arayüz değişikliği ise)

<!-- Gerekli değilse bu bölümü silin. -->
