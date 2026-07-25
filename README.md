# MKVI

Hesapsız, iki cihaz arasında doğrudan kişisel iletişim uygulaması.

## Mevcut özellikler

- Süreli kısa kodla iki cihaz eşleştirme, 64-bit doğrulama ifadesi onayı ve sonrasında otomatik cihaz keşfi.
- Cloudflare Worker + Durable Object ile yalnızca signaling/rendezvous.
- WebRTC DataChannel ile P2P mesajlaşma ve kabul-onaylı dosya aktarımı.
- Yerel cihaz kimliği: Ed25519 anahtarı Windows güvenli deposunda saklanır.
- Yerel mesaj geçmişi: XChaCha20-Poly1305 ile şifrelenmiş SQLite.
- Türkçe sohbet, ses/video arama ve ekran paylaşımı arayüzü.

## Güvenlik modeli

Cloudflare Worker yalnızca kısa eşleştirme kanalı, online durum ve SDP/ICE/kimlik signaling zarflarını iletir. İçerik, dosya ve medya P2P WebRTC bağlantısından akar. Worker iki cihaz ve 15 dakika ile sınırlıdır; kısa kod iki kabulden sonra tekrar kullanılamaz ve signaling hızı sınırlandırılır.

Varsayılan STUN sunucusu Cloudflare'dir. Bu, yalnızca doğrudan bağlantı adaylarını keşfetmeye yardım eder; TURN/medya relay etkin değildir.

## Geliştirme

```powershell
npm install
npm run tauri dev
```

Kontroller:

```powershell
npm test
npm run build
cd src-tauri; cargo test
cd ..\cloudflare; npm run check
```

## Windows kurulumu

Üretilen kurulum dosyası:

`src-tauri/target/release/bundle/nsis/MKVI_0.1.0_x64-setup.exe`

Cloudflare signaling Worker adresi varsayılan olarak `https://mkvi-signal.12orgcom09.workers.dev` kullanır.
