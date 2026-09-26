---
name: Hata raporu
about: MKVI'de bir hata, çökme veya beklenmeyen davranış bildirin
title: "[HATA] "
labels: bug
assignees: ''
---

## ⚠️ Önce şunu okuyun

**Güvenlik açığı mı?** O zaman **bu formu kullanmayın.** Herkese açık issue
güvenlik açığını duyurmak demektir. Gizli bildirim kanalını kullanın:
[`SECURITY.md`](../blob/main/SECURITY.md).

**Bilinen bir sorun mu?** Bitirme planı `ROADMAP.md` dosyasındadır. Zaten
listelenmiş bir madde ise (örneğin bilinen kısıtlar, profil fotoğrafı fazı)
lütfen yeni issue açmak yerine yorum bırakın.

## Ne oldu

Kısa, anlaşılır bir cümleyle neyin bozuk olduğunu anlatın.

## Nasıl yeniden üretilir

Adım adım yazın. Mümkün olan en az adım:

1.
2.
3.

## Beklenen davranış

Olması gereken neydi?

## Gerçekleşen davranış

Ne oldu? Ekranda ne yazıyordu? Tam hata metnini yapıştırın.

## Ekran görüntüsü / video

Mümkünse ekran görüntüsü. Ekran görüntüsü alırken sohbet içeriğinizi
**kırpmanız** gerekmez — ama kimlik bilgilerinizi gizleyin.

## Ortam

| | |
|---|---|
| MKVI sürümü | <!-- Hakkında → Hakkında'da yazan sürüm --> |
| İşletim sistemi | <!-- Windows 11 / Windows 10 / Linux / macOS + sürüm --> |
| Kurulum yöntemi | <!-- Sürümümüzün kurulum dosyası / elinizle derleme --> |
| İki cihaz mı tek cihaz mı? | |
| Signaling sunucusu | <!-- Varsayılan, yoksa kendi sunucunuzun adresi --> |
| WebView2 sürümü | <!-- Yalnızca Windows: Edge > Ayarlar > Tarayıcı sürümü --> |

## Tekrarlanabilirlik

- [ ] Her zaman oluyor
- [ ] Ara sıra oluyor
- [ ] Sadece bir kez oldu

## Kontroller

Commit önermeden önce çalıştırılan dört komutun durumu:

```
npx tsc --noEmit                 → ?
npm test                         → ?
cd src-tauri && cargo test       → ?
cd cloudflare && npm run check   → ?
```

## Ek notlar

Ağır bağlantı kurulumu, VPN, güvenlik duvarı, TURN gereksinimi gibi ek bilgi
varsa buraya yazın.
