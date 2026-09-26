# Güvenlik Politikası

MKVI, hesapsız ve sunucuda içerik tutmayan, iki kişi arasında doğrudan (P2P)
iletişim için tasarlanmış bir masaüstü uygulamasıdır. Güvenlik, bu projenin
en önemli özelliğidir; bu dosya o alandaki durumu olduğu gibi anlatır.

**Bu bir denizaltı projesidir ve tek bir bakımcısı vardır.** Aşağıdaki yanıt
süreleri gerçekçi bir tek kişilik bakım için seçilmiştir, garanti değildir.

---

## Desteklenen sürümler

| Sürüm | Durum |
|---|---|
| 0.1.x | Destekleniyor |

Güncelleme imzaları `minisign` ile doğrulanır ve yalnızca depodaki
`plugins.updater.pubkey` ile imzalanmış sürümler kabul edilir. Kurulum dosyasını
bu kanaldan almak, açık bir kurulum ekranından indirip kurmaktan güvenlidir.

---

## Nasıl bildirilir — gizli kanal

**Güvenlik açıklarını herkese açık bir issue, PR, tartışma veya sosyal medya
postası olarak bildirmeyin.** Bu, size iyi niyetle yardım etmek isteyen
kişiler için de risk oluşturur.

Gizli bildirim için **GitHub'ın özel güvenlik bildirimi kanalını** kullanın:

1. Depo sayfasında **Security** sekmesine gidin.
2. **Report a vulnerability** bağlantısını tıklayın. Bu bağlantı, deponun
   "Private vulnerability reporting" özelliği açıksa görünür.
3. Formu doldurun ve gönderin.

Gönderim yalnızca bakımcı tarafından görülebilir; herkese açık bir issue
oluşturulmaz ve konu repo geçmişine girmez.

> **E-posta adresi kullanmıyoruz.** Bu projede uydurma bir iletişim adresi
> yayımlamak, bildirimin sessizce kaybolmasına yol açardı. GitHub'ın gizli
> bildirim kanalı gerçek bir kanaldır, bakımcıdan bağımsız çalışır ve arşiv
> oluşturur; bu yüzden tercih edilmiştir. Bakımcı ileride gerçek bir adres
> eklemek isterse bu bölüm güncellenecektir.

### Bildiriminize ekleyin

- **Ne olduğu:** etkilenmiş bileşen (`src-tauri/`, `src/`, `cloudflare/` veya
  güncelleme hattı) ve sürüm.
- **Nasıl yeniden üretilir:** adım adım. Mümkünse ekran görüntüsü, kayıt
  (`%LOCALAPPDATA%` altındaki uygulama günlükleri) veya bir `wrangler tail`
  çıktısı.
- **Etki:** saldırganın neyi başarabildiği. Somut olmayan "teorik" etkileri
  tercih etmeyin; kanıtınız varsa belirtin.
- **Zararın kapsamı:** başka bir kullanıcıyı etkileyip etkilemediği, kimlik ya da
  içerik sızıntısı olup olmadığı.
- **Düzeltme öneriniz** varsa memnuniyetle değerlendirilir, ancak şart değildir.

### Ne bildirmeye çalışın, neyi gizleyin

**Evet:** kimlik doğrulama veya doğrulama hataları, şifreleme kullanımı ve
anahtar yönetimi hataları, WebRTC/DataChannel protokolü kusurları, Worker'ın
içerik taşıdığı ya da beyaz listeyi atlatarak tünel olarak kullanıldığı durumlar,
güncelleme imza doğrulamasını atlatma, yerel veri şifrelemesini atlatma, kimlik
bilgisi veya gizli veri sızıntısı, Worker'da kaynak tüketimi (DoS) yoluyla
sınırsız maliyet yaratma.

**Hayır:** MKVI'nin mimarisinden kaynaklanan ve bilinen sınırlar (aşağıda
listeli). Bunlar zaten açıkça belgelenmiştir; "yeni bir açık" olarak
bildirilmemeleri gerekir.

---

## Yanıt süresi

| Aşama | Süre |
|---|---|
| Bildirimin alındığının onayı | **7 gün** içinde |
| İlk değerlendirme (geçerlilik + aciliyet) | **14 gün** içinde |
| Düzeltme veya azaltma için plan | değerlendirmeden sonra, açıkça bildirilir |
| Kullanıcılara duyurulmuş düzeltme | aciliyete göre, acil olanlarda ölçülebilir bir tarih verilir |

Açıklamanın tamamı 14 günü aşarsa bunu size söyleriz ve yeni bir tarih veririz;
sessiz kalmayız.

---

## Bilinen güvenlik sınırlar (dürüstlük için açıkça yazıldı)

Bu bölüm bilerek yayımlanıyor. Sessizce eksik bırakmak daha kötü olurdu.

### 1. SAS doğrulama ifadesi DTLS parmak izlerini bağlamıyor — **düzeltiliyor**

Eşleştirme sırasında kullanıcıya gösterilen karşılaştırma ifadesi (SAS),
şu anda **yalnızca eşleştirme kodu ve sıralanmış cihaz açık anahtarlarından**
türetiliyor. **DTLS sertifika parmak izlerini içermiyor.**

**Somut sonuç:** Sinyalleşme sunucusunu kontrol eden (sunucuyu işleten veya
ağ üzerinde onun yerine geçen) bir saldırgan, araya girip **her iki tarafa da
aynı ifadeyi** gösterebilir. Kullanıcılar ifadelerin eşleştiğini görüp
onayladığında, saldırgan iki tarafın da trafiğini okuyup değiştirebiliyor olabilir.

**Kapsam:** Uygulamanın mimarisi gereği sunucu içeriği taşımaz; bu açık
**gizliliği** değil **kimlik doğruluğunu** (integrity) etkiler. Anahtar
değişimi, şifreleme ve yerel anahtar kasası etkilenmez.

**Azaltma:** Parmak izi değiştirilmiş sahte bir eşle karşılaştırıldığında
ifadelerin **farklı** çıkması, ve ifadenin yalnızca parmak izler belli olduktan
sonra gösterilmesi.

**Durum:** **Düzeltme geliştiriliyor ve `ROADMAP.md` içinde izleniyor
(Faz 1).** Bu açık kapatılmadan ciddi bir karşı taraf (MITM) saldırısına
karşı uygulama güvenli sayılmaz. Kısa kodun kendisi tahmin edilemez
(13–16 karakterlik bir yetenek/bearer değeri) ve cihaz imzaları yerel olarak
doğrulanır; ancak **kısa kodun gizliliğine ve yalnızca bu açığa** güvenerek
karar vermeyin.

### 2. Windows kurulum dosyası imzasızdır

Üretilen `.exe` **kod imzalı değildir.** Bu bilinçli bir karar ve mimari bir
sınırdır; imza sertifikası maliyeti kararı bakımcıya bırakılmıştır
(`ROADMAP.md`, Faz 7).

Kullanıcı için ne anlama geldiği:

- Windows SmartScreen **"Windows, korunan bilgisayarınızda güvenilmeyen bir uygulama
  başlatmak istedi"** uyarısı gösterebilir. Bu **normaldir** ve MKVI'ye özgü
  değildir.
- Windows 11'de **Smart App Control** açıksa imzasız ikili dosyaları **doğrudan
  engelleyebilir**; bu durumda kurulum başlamadan durur. Bu da bir güvenlik
  ayarının sonucudur, uygulamanın hatası değil.
- Kurulum dosyasını **bu depodaki `mkvi-updates` güncelleme beslemesinden**
  alıyorsanız dosya `minisign` imzasıyla doğrulanır. Bu, yayımlayan kimliği
  doğrular; **kod imzası yerine geçmez.**
- Windows'un kendi uyarısını atlamak yerine dosyanın kaynağını doğrulamanızı
  öneririz.

Bu, Windows dışı platformlar için geçerli değildir; uygulama şu anda
**Windows önceliklidir**.

### 3. Uygulama Windows önceliklidir

Android ve mobil için karar verilmemiştir. Kurulum, platform desteği ve davranış
bugün masaüstü (özellikle Windows) için test edilmiştir.

### 4. Sinyalleşme sunucusu küçük bir ücretsiz kotadır

`cloudflare/` altındaki Worker iki Durable Object kullanır ve bir eşleşme
kabulünün Cloudflare ücretsiz planına ölçülebilir bir maliyeti vardır. Ayrıntılı
sınırlar ve "kendi sunucunu kendin kur" talimatı için
[`cloudflare/README.md`](cloudflare/README.md) dosyasına bakın. Kendi Worker'ınızı
kendi hesabınıza deploy ediyorsanız, onu kimseye ücretsiz bir hizmet olarak
sunmamaya dikkat edin; bu Worker'ın kaynak kodu AGPL-3.0'dir ve asıl nedeni de
budur.

### 5. Otomatik güncelleme feed'i halka açıktır

Güncelleme adresi ve `latest.json` herkese açıktır; imza doğrulaması zorunludur.
Bu, feed'in okunabilir olması içindir — feed'in *içeriği* değil, *değiştirilemez
liği* korunur.

---

## Desteklenmeyen sürümler

Bu bir sürüm numarası taşımayan tek dallı projedir; `main`/`master` dışındaki
dallar güvenlik açısından desteklenmez.

---

## Teşekkürler

Bir açığı sorumlu şekilde bildirdiğiniz için teşekkürler. Zafiyeti kamuya açıklamadan
önce düzeltme için makul bir süre tanımanız bizim için değerlidir.
