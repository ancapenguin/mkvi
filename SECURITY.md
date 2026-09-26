# Güvenlik Politikası

MKVI, hesapsız ve sunucuda içerik tutmayan, iki kişi arasında doğrudan (P2P)
iletişim için tasarlanmış bir masaüstü uygulamasıdır. Güvenlik, bu projenin en
önemli özelliğidir; bu dosya o alandaki durumu **olduğu gibi** anlatır.

**Bu bir denizaltı projesidir ve tek bir bakımcısı vardır.** Aşağıdaki yanıt
süreleri gerçekçi bir tek kişilik bakım için seçilmiştir, garanti değildir.

---

## Desteklenen sürümler

| Sürüm | Durum | Destek |
|---|---|---|
| **0.2.x** (Flutter hattı) | Geliştirme aşamasında, **yayımlanmamış** | Evet — açıklar bu hatta bildirilir |
| **0.1.x** (Tauri hattı) | **Emekliye ayrıldı** ve kodu depodan silindi | Hayır — güvenlik düzeltmesi yayımlanmayacak |

> **Yayımlanmış bir sürüm şu an yok.** Depodaki `VERSION` değeri `0.2.0` olsa da
> GitHub Releases boştur ve indirilebilir bir kurulum dosyası yoktur. 0.1.x'in
> güncelleme adresi de 404 döndüğü için 0.1.x **kendini güncelleyemiyor**. Bu
> tablo 0.2.0 yayımlandığında güncellenecektir.

**0.1.x neden emekli?** Kamera ve ekran paylaşımı hiç çalışmıyordu (sebep kod
değil platformdu) ve yeniden bağlanma çalışmıyordu. Kanıt ve tam kök neden listesi:
`ROADMAP.md` → "0.1.4 gerçek cihazlarda denendi".

### Güncelleme ve imza doğrulama

0.2.0'ın güncelleme akışı hazırlanıyor: `mkvi_core::update` bir yayın dosyasının
imzasını `minisign-verify` ile **saf olarak** doğrular (ağ yok, asenkron yok;
indirme işi çağıranın). Flutter tarafındaki istemci ve güven zinciri
`app/lib/update/` altında.

**Bugün otomatik güncelleme çalışmıyor ve hiç çalışmadı.** İki ayrı sebep var ve
ikisi de ölçülmüştür:

1. **Ölü feed.** 0.1.x'in besleme adresi (`ancapenguin/mkvi-updates`) **404**
   dönüyor. Bu adres 2026-09-26'da canlı olarak doğrulanmıştır. 0.1.x'i durduran
   şey anahtar değil, bu ölü adrestir.
2. **Emekti imza biçimi.** Yayın anahtarı minisign'in eski `Ed` biçimindedir.
   Katı doğrulayıcı her `ED` imzasını reddeder. `mkvi_core::update` bunu sessizce
   "dosya değiştirilmiş olabilir" diye değil, **`LegacyKey` hatası olarak adıyla**
   bildirir.

Sonuç: **sürüm geçişinde iki cihazın da yeni sürümü elle kurması gerekir.**

Güncelleme beslemesi GitHub Releases'e taşındığında ve prehashed bir yayın
anahtarı üretildiğinde bu bölüm güncellenecektir.

---

## Nasıl bildirilir — özel kanal

**Güvenlik açıklarını herkese açık bir issue, PR, tartışma veya sosyal medya
postası olarak bildirmeyin.** Bu, size iyi niyetle yardım etmek isteyen kişiler
için de risk oluşturur; siz de kendinizi riske atarsınız.

### Birincil kanal — GitHub'ın özel güvenlik bildirimi

1. Depo sayfasında **Security** sekmesine gidin.
2. **Report a vulnerability** bağlantısını tıklayın.
   Doğrudan adres:
   <https://github.com/ancapenguin/mkvi/security/advisories/new>
3. Formu doldurun ve gönderin.

Bu bağlantı, deponun **"Private vulnerability reporting"** özelliği açıksa
görünür ve çalışır. Gönderim yalnızca bakımcı tarafından görülebilir; herkese açık
bir issue oluşturulmaz ve konu repo geçmişine girmez.

> Bu özellik depoda açılmamışsa bağlantı çalışmaz. O durumda **aşağıdaki yedek
> yolu** kullanın — bu, özelliğin kapalı olduğu anlamına gelir, açık olduğu
> anlamına gelmez.

### Yedek kanal — özel iletişim kanalı isteyin

**Zafiyetin kendisini yazmadan** bir issue açın:

> "Bu bir güvenlik bildirimi için özel bir iletişim kanalı arıyorum. Ayrıntıyı
> issue'da paylaşmayacağım; kanaldan sonra göndereceğim."

Bakımcı yanıtlar. Kanalı aldıktan sonra ayrıntıyı o kanaldan gönderin ve o issue'yi
kapatın. **Açıklayıcı hiçbir ayrıntıyı ilk issue'ya yazmayın** — issue herkese
açıktır.

Bu yol e-posta kullanmaz; bakımcının GitHub üzerinden özel bir iletişim yolu
kurmasını ister. Depoda şu an **doğrulanmış bir e-posta adresi yayımlanmamıştır**;
uydurma bir adres yayımlamak bildirimin sessizce kaybolmasına yol açardı. Bakımcı
gerçek bir adres eklediğinde bu bölüm güncellenecektir.

### Bildiriminize ekleyin

- **Ne olduğu:** etkilenen bileşen (`app/`, `crates/mkvi_core`,
  `crates/mkvi_bridge`, `cloudflare/` veya güncelleme hattı) ve sürüm.
- **Nasıl yeniden üretilir:** adım adım. Mümkünse ekran görüntüsü, uygulama
  günlüğü veya bir `wrangler tail` çıktısı.
- **Etki:** saldırganın **ne yapabildiği.** Somut olmayan "teorik" etkileri tercih
  etmeyin; kanıtınız varsa belirtin.
- **Zararın kapsamı:** başka bir kullanıcıyı etkileyip etkilemediği, kimlik ya da
  içerik sızıntısı olup olmadığı.
- **Düzeltme öneriniz** varsa memnuniyetle değerlendirilir, ancak şart değildir.

### Neyi bildirmek istersiniz, neyi gizleyin

**Evet:** kimlik doğrulama veya doğrulama hataları, şifreleme kullanımı ve anahtar
yönetimi hataları, WebRTC/DataChannel protokolü kusurları, Worker'ın içerik taşıdığı
ya da beyaz listeyi atlatarak tünel olarak kullanıldığı durumlar, güncelleme imza
doğrulamasını atlatma, yerel veri şifrelemesini atlatma, kimlik bilgisi veya gizli
veri sızıntısı, `isSignalPayload` beyaz listesinin atlatılması, Worker'da kaynak
tüketimi (DoS) yoluyla sınırsız maliyet yaratma.

**Hayır:** MKVI'nin mimarisinden kaynaklanan ve aşağıda listeli bilinen sınırlar.
Bunlar zaten açıkça belgelenmiştir; "yeni bir açık" olarak bildirilmemeleri gerekir —
ama bir *farklı* etki bulduğunuzu düşünüyorsanız yine de bildirin.

---

## Yanıt süresi

| Aşama | Süre |
|---|---|
| Bildirimin alındığının onayı | **7 gün** içinde |
| İlk değerlendirme (geçerlilik + aciliyet) | **14 gün** içinde |
| Düzeltme veya azaltma için plan | değerlendirmeden sonra, açıkça bildirilir |
| Kullanıcılara duyurulmuş düzeltme | aciliyete göre; acil olanlarda ölçülebilir bir tarih verilir |

Açıklamanın tamamı 14 günü aşarsa bunu size söyleriz ve yeni bir tarih veririz;
sessiz kalmayız.

---

## Güvenlik modeli

### Sunucu içerik taşımaz

`cloudflare/` altındaki Worker yalnızca dört zarf türünü iletir: `identity`
(cihaz açık anahtarı ve imzası), `offer` / `answer` (SDP) ve `ice` (adaylar).
Mesaj, dosya, ses, video ve ekran içeriğinin **hiçbiri** bu sunucudan geçmez.

Zarf şeması `isSignalPayload` ile **anahtar bazında beyaz listelidir**; şemaya
uymayan her zarf `1008` ile reddedilir. Worker, taşıdığı verinin *ne olduğunu*
doğrulayan bir katmandır — keyfî bir içerik taşıyıcısı olamaz.

**Worker'ın durumunda ne tutulur (iki şey, ikisi de sayı ve süre):**

| Nerede | Ne | Süre |
|---|---|---|
| `PairingRoom` | `admitted` sayacı (bir tamsayı) ve alarm zamanı | 15 dakika; sonra sayacı silinir |
| `PeerRendezvous` | en fazla 2 opak cihaz tutamacı ve `expiresAt` | 30 gün (kayan) |

Cihaz tutamakları adres değildir: 32 rastgele baytın base64url gösterimi,
üretildiği tarafta saklanan bir yetenek değeridir. Adınızı, IP'nizi veya cihaz
kimliğinizi tutmaz.

**Geçici olarak *görülebilir* (saklanmaz):** Workers bir bulut geçididir, dolayısıyla
Worker'ın belleğinden geçen paketleri işleten kişi teorik olarak görebilir —
açık anahtarları, SDP'yi ve **her iki tarafın** ICE adaylarını (yani IP adresleri
ve portları). Bu, içerik gizliliğini bozmaz; kimlik doğruluğu tarafında aşağıdaki
bilinen açığın kaynağıdır.

### Cihaz kimliği — Ed25519

Her cihazın Ed25519 anahtar çifti vardır. **Özel anahtar işletim sistemi güvenli
deposunda durur** (Windows: Credential Manager; macOS: Keychain; Linux: Secret
Service) ve uygulama arayüzüne asla çıkmaz. Dart tarafı ham anahtarı hiçbir
zaman görmez; imzalama ve çözme çekirdektedir.

**Sessiz sır üretimi yasaktır.** Keyring'de kayıt yoksa ama diskte bir şey varsa
yeni anahtar üretilmez; `KeyringEntryMissing` hatası verilir. Yazma sonrası okuma
doğrulanır, çünkü `keyring` 3 arka ucuz kaldığında bellek içi bir sahte depoya
düşüyor — bu, 0.1.x'te her açılışta yeni bir kimlik üretilmesine yol açmıştı.

**Özel kripto yazılmaz**; yalnızca denetimli kütüphaneler kullanılır
(`ed25519-dalek`, `chacha20poly1305`).

### Yerel geçmiş — XChaCha20-Poly1305

Mesaj geçmişi SQLite'ta tutulur ve **uygulama katmanında** XChaCha20-Poly1305
ile şifrelenir; anahtar işletim sistemi kasasında durur. Diske düz metin yazılmaz.

> **Bilinen sınır:** şifreleme satırların *gövdesini* kapsar; SQLite'ın WAL ve
> journal sayfaları bu şifrelemenin dışındadır. **SQLCipher etkin değil.**
> `ROADMAP.md` Faz 4'te izleniyor. Sütun sırası ve zaman damgaları da düz
> metindir.

### DTLS parmak izi doğrulaması — **bağlanmadı**

Bu, projenin en önemli bilinen açığıdır ve **gizlenmiyor**.

**Karşılaştırma ifadesi (SAS) şu anda DTLS sertifika parmak izlerine bağlanmıyor.**

0.1.x'te kullanıcıya gösterilen ifade, **yalnızca eşleştirme kodu ve sıralanmış
cihaz açık anahtarlarından** türetiliyordu. 0.2.0'da ise bu ifade henüz **hiç
bağlanmadı** — ne Rust çekirdekte ne de Dart tarafında `dtls` ya da parmak izi
kodu vardır. Bu madde, `ROADMAP.md`'de *"Faz 1 güvenlik açığı"* diye adlandırılan ve
**Faz 4**'te açık bir iş kalemidir.

**Somut sonuç:** Sinyalleşme sunucusunu kontrol eden (sunucuyu işleten veya ağ
üzerinde onun yerine geçen) bir saldırgan, araya girip **her iki tarafa da aynı
ifadeyi** gösterebilir. Kullanıcılar ifadelerin eşleştiğini görüp onayladığında,
saldırgan iki tarafın da trafiğini okuyup değiştirebiliyor olabilir.

**Kapsam:** Mimari gereği sunucu içeriği taşımaz; bu açık **gizliliği değil kimlik
doğruluğunu (integrity)** etkiler. Anahtar değişimi, şifreleme ve yerel anahtar
kasası etkilenmez. Ancak **bu açık kapanana kadar uygulama, ciddi bir karşı taraf
(MITM) saldırısına karşı güvenli sayılmaz.**

**Zayıflatmayı ne sağlar (ve ne sağlamaz):**

- Eşleştirme kodu 13 karakter, 32 sembol → **65 bit**, pratikte tahmin edilemez;
  `I O 0 1` karakterleri alfabede yoktur.
- Oda 15 dakika yaşar ve en çok 8 girişe izin verir (`MAX_ADMISSIONS`), üstelik
  **tek kullanımlık değildir**: uygulama yeniden başlatıldığında veya soket
  düştüğünde giriş yeniden sayılır. Kodun tahmin edilemezliği güvenlik açısından
  belirleyicidir, tek kullanımlılığı değil.
- Cihaz imzaları yerel olarak doğrulanır.

**Ancak yalnızca bu açığa güvenerek karar vermeyin.** Parmak izinin ifadeye
bağlanması, sahte bir eşle karşılaştırıldığında ifadelerin **farklı** çıkmasını
ve ifadenin yalnızca parmak izler belli olduktan sonra gösterilmesini sağlar.

### Kendi sunucunu kurma ilkesi

**MKVI kimseye hizmet vermez.** Depoda gömülü bir sunucu yoktur ve uygulamanın
sinyal adresi varsayılan olarak **boştur** — `ConnectionSettings` boş bir adresi
hem "henüz yapılandırılmadı" durumu olarak kabul eder hem de kullanıcının
yazdığı bir değer olarak reddeder.

İki kişi, ikisinin de bildiği bir Worker kurar. Veri kendi Cloudflare hesabında
kalır. Bu, hem gizlilik hem de **ücretsiz katmanın dayanabilirliği** açısından
zorunludur: ücretsiz planda Durable Object süre kotası 13.000 GB-s/gündür ve bir
15 dakikalık eşleşme kabaca 115 GB-s tutar, yani bir günde ~110 eşleşmeden sonra
kota tükenir. Gömülü bir sunucu, bir noktadan sonra herkes için ölü olurdu.
Ayrıntı ve ölçüm/tahmin ayrımı: `cloudflare/README.md` §4.

`cloudflare/` **AGPL-3.0** altındadır; Worker'ı barındırma hizmeti olarak yeniden
satmak lisansın şartlarına aykırıdır. Kendi hesabınızda kendiniz kullanmak
serbesttir.

### Worker'ın kötüye kullanım yüzeyi

Worker'ın önünde **kimlik doğrulama yoktur, yalnızca biçim doğrulaması vardır.**
Bilinçli bir tasarımdır (kurulum gerektirmesin diye) ve şu sonucu doğurur:

> Herhangi bir anonim istemci, biçimsel olarak geçerli rastgele bir kod üreterek bir
> Durable Object örneği **oluşturabilir.** Eşleşme sayısı sınırı vardır ama **istek
> sayısı sınırı yoktur.**

Yani Worker'ı internete açtığınızda, hesabınızın kotasını tüketmek isteyen tek bir
kişi bile onu tüketebilir. Worker'ın kendi içinde bir hız sınırı **yoktur**
(WebSocket *zarf* hızı sınırlıdır, bağlantı açma istekleri sınırsızdır).

**Kendiniz okumalısınız:** `cloudflare/README.md` §5. Paylaşılacak bir instance
açacaksanız kenarda (edge) bir hız sınırı koyun ve açık bir instance'ta asla
kimlik doğrulama beklemeyin — eşleştirme kodları birer *bearer* yetenek
değeridir.

---

## Bilinen güvenlik sınırlar (dürüstlük için açıkça yazıldı)

Bu bölüm bilerek yayımlanıyor. Sessizce eksik bırakmak daha kötü olurdu.

### 1. SAS, DTLS parmak izine bağlı değil — **açık, kapatılıyor**

Yukarıda ayrıntılı anlatıldı. Özetle: bu açık kapatılana kadar ciddi bir MITM
saldırısına karşı uygulama güvenli sayılmaz. İzlenen yer: `ROADMAP.md` Faz 4.

### 2. SQLite'ın WAL/journal sayfaları şifreli değil

Mesaj gövdesi XChaCha20-Poly1305 ile şifrelenir, ancak veritabanı dosyasının
WAL/journal sayfaları bu şifrelemenin dışındadır. SQLCipher etkin değil. Yalnız
cihazınıza fiziksel erişimi olan biri bu sayfalardan satır sırasını, zaman
damgalarını ve boyutu görebilir. İzlenen yer: `ROADMAP.md` Faz 4.

### 3. Windows kurulum dosyası imzasızdır

Üretilen `.exe` **kod imzalı değildir.** Bu bilinçli bir karar ve mimari bir
sınırdır; imza sertifikası maliyeti kararı bakımcıya bırakılmıştır
(`ROADMAP.md` Faz 7).

Kullanıcı için ne anlama geldiği:

- Windows SmartScreen **"Windows, korunan bilgisayarınızda güvenilmeyen bir uygulama
  başlatmak istedi"** uyarısı gösterebilir. Bu **normaldir** ve MKVI'ye özgü
  değildir.
- Windows 11'de **Smart App Control** açıksa imzasız ikili dosyaları **doğrudan
  engelleyebilir**; bu durumda kurulum başlamadan durur. Bu da bir güvenlik
  ayarının sonucudur, uygulamanın hatası değil.
- Windows'un kendi uyarısını atlamak yerine dosyanın **kaynağını** doğrulamanızı
  öneririz.

### 4. Otomatik güncelleme çalışmıyor

Yukarıdaki "Güncelleme ve imza doğrulama" bölümüne bakın. Kısa özet: feed adresi
404 döndüğü ve yayın anahtarı emekli biçimde olduğu için **sürüm geçişinde iki
cihazın da yeni sürümü elle kurması gerekiyor.** İlk Flutter sürümünden önce
prehashed bir yayın anahtarı üretilmeli.

### 5. Sinyalleşme sunucusu küçük bir ücretsiz kotadır

Yukarıdaki "Kendi sunucunu kurma ilkesi" bölümüne bakın. Kendi Worker'ınızı
kendi hesabınıza deploy ediyorsanız, onu kimseye ücretsiz bir hizmet olarak
sunmamaya dikkat edin; bu Worker'ın kaynak kodu AGPL-3.0'dir ve asıl nedeni de
budur.

### 6. Yalnız Windows

Uygulama masaüstü (özellikle Windows) için test edilmiştir. Android ve mobil için
karar verilmemiştir; `keyring` 3'ün bir Android arka ucu yoktur ve `mkvi_core`
bugün Android hedefi **derlenmez** (`crates/mkvi_bridge/README.md`, "Android ve
gizli depo" bölümüne bakın).

### 7. 0.1.x emekli

0.1.x hattı güvenlik güncellemesi almayacaktır ve kodu 2026-09-26'da depodan
silinmiştir. Üzerinde çalışan biri kendi riskini taşır; geriye dönük uyumluluk
yapılmadı ve migration yoktur. O hattın güvenlik açısından ne olduğu ve nereye
taşındığı: `docs/legacy-tauri-line.md`.

---

## Desteklenmeyen sürümler

Bu depoda tek canlı hat vardır. `main` dışındaki dallar, `0.1.x` emekli hattı ve
0.2.0 öncesi herhangi bir sürüm güvenlik açısından desteklenmez.

---

## Teşekkürler

Bir açığı sorumlu şekilde bildirdiğiniz için teşekkürler. Zafiyeti kamuya açıklamadan
önce düzeltme için makul bir süre tanımanız bizim için değerlidir.
