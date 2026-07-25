# MKVI mimari kararı ve yol haritası

## Karar

İlk ürün **Tauri 2 + React + TypeScript + Rust** ile geliştirilecek. Arayüz sistem WebView'inde çalışır; Windows'ta bu WebView2'dir. Gerçek zamanlı medya ve dosya aktarımı tarayıcının olgun WebRTC uygulamasını (`RTCPeerConnection`, `MediaDevices`, `RTCDataChannel`) kullanır. Rust, yerel sırlar, şifreli kalıcı veri ve işletim sistemi izinleri için küçük bir güvenlik sınırı olur.

Bu seçim Windows v1'ini hızlı ve küçük bir paketle teslim etmeye yöneliktir. Tauri 2 Android/iOS hedeflerini destekler; ortak TypeScript iletişim protokolü ve Rust çekirdeği korunacaktır. Android ekran paylaşımı gerekirse MediaProjection kullanan bir Kotlin Tauri eklentisi eklenir.

Flutter bu aşamada seçilmedi: mobil taşıma avantajı güçlü olsa da mevcut Windows teslimini geciktirir ve WebRTC yüzeyinde ek bir eklenti katmanı getirir. Android için erken bir uyumluluk denemesi bu kararı doğrulayacaktır.

## Güvenlik sınırları

```text
MKVI cihaz A  -- DTLS/SRTP ve DataChannel -->  MKVI cihaz B
     |                                                    |
     +------ WSS: yalnızca offer/answer/ICE -------------+
                         Cloudflare Worker + Durable Object
```

- Worker; kısa kodla açılan geçici oturum, online durum ve signaling zarfını yönetir. Mesaj, dosya veya medya içeriğini kaydetmez ya da aktarmaya çalışmaz.
- Pairing kodu tek kullanımlık, kısa ömürlüdür. Her iki taraf aynı SAS (short authentication string) ifadesini görüp onaylamadan kalıcı eş kabul edilmez.
- Cihaz için Ed25519 anahtar çifti üretilecek; özel anahtar Windows DPAPI / macOS Keychain / Android Keystore üzerinden saklanacaktır. Özel kripto algoritması yazılmayacaktır.
- Yerel geçmiş normal SQLite içinde uygulama katmanında XChaCha20-Poly1305 ile şifrelenir; şifreleme anahtarı işletim sistemi güvenli deposunda tutulur.
- Tauri capability listesi en az yetkiyle tutulur. Frontend hiçbir zaman ham anahtar veya veritabanı parolası görmez.

## Uygulama katmanları

- `src/domain`: platformdan bağımsız pairing ve signaling tipleri.
- `src/services`: WebSocket signaling ve ileride WebRTC oturumu.
- `src/components`: Türkçe kullanıcı arayüzü.
- `src-tauri`: yalnızca güvenilir yerel komutlar / anahtar deposu / şifreli geçmiş.
- `cloudflare`: ayrı dağıtılan, yalnızca rendezvous Worker'ı.

## Yol haritası

1. **Temel (bu değişiklik):** Tauri kabuğu, Türkçe pairing ekranı, tipli signaling protokolü, TTL'li Durable Object Worker ve derleme doğrulaması.
2. **Eşleştirme:** OS güvenli depoda cihaz anahtarı, imzalı ephemeral anahtar değişimi ve SAS onayı; eş kaydının şifreli yerel depoya yazılması.
3. **P2P mesajlaşma:** WebRTC DataChannel, sıralı mesajlar, şifreli SQLite geçmişi ve yeniden bağlanma.
4. **Dosya:** parça-kimlikleri, akış geri basıncı, bütünlük kontrolü ve devam ettirme metadatası.
5. **Arama:** ses, görüntü, cihaz seçimi, bağlantı istatistikleri ve ekran paylaşımı.
6. **Android denemesi:** pairing, DataChannel, kamera/mikrofon izni; gerekirse ekran paylaşımı eklentisi. Başarısızlıkta Flutter'a geçiş kararı burada yeniden ele alınır.
7. **Sertleştirme:** bağımsız güvenlik incelemesi, rate-limit testleri, paket imzalama ve yedekleme olmayan geri yükleme stratejisi.

## Çalıştırma

```powershell
npm run build
npm run tauri dev
```

Worker için `cloudflare` klasöründe `npm install`, ardından `npx wrangler login` ve `npx wrangler deploy` çalıştırılır. Dağıtım URL'si MKVI'nin Ayarlar ekranına yazılır.
