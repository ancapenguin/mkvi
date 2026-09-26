---
name: Özellik isteği
about: MKVI'ye yeni bir özellik veya iyileştirme önerin
title: "[ÖZELLİK] "
labels: enhancement
assignees: ''
---

## ⚠️ Önce şunu okuyun

**Güvenlik açığı mı?** O zaman bu formu kullanmayın; gizli bildirim kanalını
kullanın: [`SECURITY.md`](../blob/main/SECURITY.md).

**Bu istek zaten planlanmış mı?** Bitirme planı ve verilmiş kararlar
`ROADMAP.md` dosyasındadır. Bir madde "verilmiş karar" olarak işaretliyse lütfen
onu yeniden açmayın — gerekçesi orada yazılıdır ve yeniden tartışma kararın
sonucunu değiştirmez.

## Ne öneriyorsunuz

Tek cümleyle.

## Hangi sorunu çözüyor

Mevcut hangi eksiklik, kısıtlama veya zahmetli durum bu öneriyi gerekçelendiriyor?
"Şu daha iyi olur" yetmez; **hangi durumda, neden rahatsız edici** yazın.

## Önerilen çözüm

Nasıl çalışmasını istiyorsunuz? Daha önce bir çözüm önerdiniz mi?

## Alternatifler

Düşündüğünüz ama beğenmediğiniz çözümler.

## Kapsam ve maliyet

- [ ] Yalnızca arayüz (Rust tarafına dokunulmaz)
- [ ] Rust tarafı de değişir
- [ ] Sinyalleşme Worker'ı de değişir (`cloudflare/`) — AGPL kapsamı
- [ ] Yeni bir bağımlılık ekler
- [ ] Protokolü değiştirir (uyumluluk kırılması olabilir)

> Protokolü daraltmak kırıcıdır: bir signaling alanını kaldırmak, hâlâ o alanı
> gönderen eski istemcileri düşürür. Protokol değişikliği öneriyorsanız bunu
> bilin.

## MKVI'nin sınırlarıyla uyum

MKVI bilinçli olarak küçük tutuluyor. Öneriniz aşağıdakilerden birini gerektiriyorsa
bunu belirtin:

- Hesap / giriş / kimlik doğrulama
- Sunucuda içerik saklama
- TURN (masaüstünde bilinçli olarak kapalı)
- Harici bir kütüphane (UI kütüphanesi, WebRTC sarmalayıcısı, i18n kütüphanesi)

## Ek bağlam

Ekran görüntüsü, bağlantı, referans bağlantısı.
