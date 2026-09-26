# mkvi_bridge

`mkvi_core`'i Flutter tarafına `flutter_rust_bridge` ile açar. Davranışın hiçbir
kısmı burada değil: her garanti çekirdekte yazılı ve testli, bu crate sadece
kodlama, hata eşlemesi ve imzalar.

## Düzen

```
crates/mkvi_bridge/
├── Cargo.toml                 staticlib + cdylib, mkvi_core'e yol bağımlılığı
├── flutter_rust_bridge.yaml   codegen yapılandırması
├── src/
│   ├── lib.rs                 modüller
│   ├── api.rs                 Dart'a açılan yüzey + testler
│   ├── error.rs               SecurityError/CoreError -> Dart birleşimleri
│   └── frb_generated.rs       ÜRETİLEN. Elle dokunulmaz.
├── dart/                      Dart paketi (aşağıya bak)
│   ├── pubspec.yaml
│   ├── lib/src/rust/          ÜRETİLEN: api, error, frb_generated, *.freezed
│   └── bin/round_trip.dart    Gidiş-dönüş kanıtı
└── README.md
```

Uygulama `crates/mkvi_bridge/dart` dizinini yol bağımlılığı olarak alır ve
`package:mkvi_bridge/src/rust/api.dart` içinden çağırır. **Bağlantıları uygulama
yeniden üretmez.**

## Yeniden üretme

```bash
# Bir kez, Rust tarafı. Sürüm pubspec.yaml ve Cargo.toml'daki "=2.13.0" ile aynı olmalı.
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked

cd crates/mkvi_bridge
flutter_rust_bridge_codegen generate
```

`generate` Rust glue'u, Dart bağlantılarını ve `build_runner` üzerinden
`*.freezed.dart` dosyalarını üretir. Hepsi depoda tutulur, böylece temiz bir klon
üreteç çalıştırmadan derlenir. `api.rs` ya da `error.rs` değiştiyse
`generate` tekrar çalıştırılmalıdır; üretilmiş dosyalar elle düzenlenmez.

İki sürümü birlikte güncelle. Dart tarafı üretilen glue'un sürümünü çalışma
anında karşılaştırır ve uyuşmazlıkta başlamayı reddeder; bu yüzden `Cargo.toml`
`flutter_rust_bridge = "=2.13.0"` diye tam sabitler.

## Yüzey

Yedi alan çağrısı ve bir kurucu. Hepsi Dart tarafında `Future` döner.

| Rust | Dart |
| --- | --- |
| `open_core(data_dir: String) -> Result<Core, CoreFailure>` | `openCore({required String dataDir}) -> Future<Core>` |
| `device_public_key(core: &Core) -> String` | `devicePublicKey({required Core core}) -> Future<String>` |
| `sign(core: &Core, message: Vec<u8>) -> Result<String, CoreFailure>` | `sign({required Core core, required List<int> message})` |
| `verify(public_key: String, message: Vec<u8>, signature: String) -> bool` | `verify({required String publicKey, required List<int> message, required String signature}) -> Future<bool>` |
| `append_history(core: &Core, message: HistoryMessage) -> Result<(), CoreFailure>` | `appendHistory({required Core core, required HistoryMessage message})` |
| `list_history(core: &Core, limit: u32) -> Result<Vec<HistoryMessage>, CoreFailure>` | `listHistory({required Core core, required int limit})` |
| `remember_peer(core: &Core, peer: KnownPeer) -> Result<(), CoreFailure>` | `rememberPeer({required Core core, required KnownPeer peer})` |
| `list_peers(core: &Core) -> Result<Vec<KnownPeer>, CoreFailure>` | `listPeers({required Core core})` |

`open_core` kurucudur, alan çağrısı değildir: varlık nedeni sadece yedi çağrının
aldığı `&Core` elini vermektir.

### `open_core` ne garanti eder

1. Veri dizini var olur.
2. **Şifreli geçmiş önce açılır.** Böylece bir eşin kayıtlı olduğu kurulum,
   kimlik geri yüklenmeden *önce* bilinir; eksik bir güvenli depo kaydı üstüne
   yeni bir anahtar yazılmak yerine `CoreFailure::Security` /
   `KeyringEntryMissing` olarak bildirilir. Bu, MKVI'nin eşini unutup yeniden
   eşleme kodu istemesine yol açan hatanın kendisidir.
3. Kimlik geri yüklenir; yalnızca gerçekten ilk çalıştırmada yeni üretilir.

Yarı açık bir çekirdek asla dönmez.

### `device_public_key`

`open_core`'in geri yüklediği, çalıştırmalar arasında bayt bayt sabit olan
Ed25519 anahtarı. Biçim: **dolgusuz standart base64** (RFC 4648 §5, `=` yok).
`Core::public_key_base64` ve Tauri kabuğunun `device_public_key` komutu tam olarak
bunu üretir; eş protokolü Flutter taşımasıyla değiştirilemez. Tohum hiçbir
biçimde dışarı çıkmaz.

### `sign`

`message` baytlarının tamamı üzerinde, `device_public_key`'in yayınladığı anahtarla
Ed25519 imzası. Biçim: **dolgusuz standart base64**, `device_public_key` ile
aynı (`sign_pairing` komutunun zaten kullandığı biçim). Bugün başarısız olamaz;
`Result` ileride hazırlık gerektiren bir anahtar için yer bırakıyor, Dart imzasını
değiştirmeden.

### `verify`

Yalnızca `signature`, `public_key`'in `message` üzerindeki geçerli Ed25519
imzasıysa `true`. Çekirdek `verify_strict` kullanır, yani daha zayıf bir Ed25519
varyantıyla üretilmiş imza reddedilir.

**Hatalı kodlanmış anahtar veya imza hata fırlatmaz, `false` döner.** Bilinçli
seçim: hata fırlatsaydı bir eş "bu anahtar çözülemiyor" ile "bu imza yanlış"ı
ayırt edip farkı sonda kullanabilirdi. İkisi de sadece "doğrulanmadı"dır.

### `append_history`

`Ok` durumunda mesaj SQLite'a işlenmiş ve geçmiş anahtarıyla
XChaCha20-Poly1305 ile mühürlenmiştir; diske düz metin yazılmaz. **Yinelenen
`id` hata verir, üzerine yazmaz** — yeniden gönderilen bir teslimat sessizce
geçmişi değiştiremez. Boş veya 128 bayttan uzun `id` herhangi bir G/Ç öncesinde
`InvalidMessageId` olarak reddedilir.

### `list_history`

Sonuç `sent_at_ms`'e göre yeniden eskiye sıralıdır ve en fazla `limit` kayıt
içerir; çekirdek `limit`'i kendisi 500'e kırpar, yani bir milyon isteyen çağıran
500 satır alır. Her satır çözülür ve doğrulanır; **bir satırın doğrulaması
kalkarsa tüm çağrı `Crypto` ile başarısız olur, satır atlanmaz** — kısmi bir
liste kayıp geçmiş gibi görünürdü. Boş sonuç geçmişin gerçekten boş olduğu
anlamına gelir, okunamadığı anlamına değil.

### `remember_peer` / `list_peers`

`remember_peer`: `Ok` durumunda eş şifreli depoda saklanır ve `list_peers` ile
geri gelir. Aynı `public_key` yeniden yazılırsa satır değiştirilir; yeniden
eşleme böyle ifade edilir. Alan biçimleri **herhangi bir şey yazılmadan önce**
denetlenir: boş veya 128 bayttan uzuk `public_key`, tam 43 karakter olmayan
`discovery_id`, 80 karakteri aşan `display_name` reddedilir. 43 karakterlik
`discovery_id`, rendezvous protokolünün ürettiği biçimdir (32 rastgele bayt,
dolgusuz base64).

`list_peers`: her kayıt döndürülmeden önce çözülür ve doğrulanır; bir kaydın
doğrulaması kalkarsa tüm çağrı başarısız olur. Sağlıklı bir kurulum 0 veya 1
elemana döner; liste biçimi depoda tutulan biçimdir.

### Uyarı: dosya aktarımı bilinçli olarak ertelendi

`open_sink` / `write_sink` / `close_sink` / `abort_sink` çekirdekte hazır ama
köprüye **eklenmedi**. Bugün dosya taşıma katmanı P2P taşımanın üstünde Dart'ta
yaşıyor ve bu dört çağrıyı gerektiren bir Dart tarafı yok. Yüzeyi büyütmek
yerine ertelendi. Dosya taşıma Dart tarafına geldiğinde `api.rs`'e `Core`'in
zaten var olan dört yöntemi çevrim içi eklemek yeterlidir; `Core` zaten
dosya tutamaçlarını kendi `Mutex`'i içinde tutuyor, köprüde başka bir şey
gerekmez.

## Hata sınırı: metin değil veri

Tauri kabuğu her komuttan `String` döndürüyordu ve ön yüz o metni atıyordu;
"güvenli depo bir kaydı kaybetti" ile "SQLite meşgul" ikisi de isimsiz bir
toast satırı olarak geliyordu. flutter_rust_bridge bir hatayı **ancak
`anyhow::Error` ise** metne düzleştirir; hata bir enum ise gerçek bir Dart
sınıfı olarak taşınır. Bu yüzden:

* `Result<_, CoreFailure>` — `CoreFailure`, `CoreError`'in her çeşidini birebir
  karşılayan bir enum. Dart'ta `implements FrbException` olan bir `sealed`
  sınıftır, yani `catch` edilebilir **ve** çeşidi örneklenebilir.
* `CoreFailure::Security { failure }` — çekirdeğin kendi iç içeliği korunur,
  içindeki `SecurityFailure` hâlâ erişilebilir. `KeyringEntryMissing` yalnızca
  bir `Database` hatasıyla aynı sepette değildir.
* Her çeşitide `message` alanı vardır ve bu alan **çekirdeğin kendi `Display`
  çıktısıdır**, hata değeri elde olduğu anda alınır. Türkçe metin
  `mkvi_core`'den gelir; köprüde ikinci bir yerden söylenmez, `error.rs` sadece
  makine tarafından okunabilir bir çeşit ekler.

Böylece Dart'ta şöyle dallanılır:

```dart
try {
  await listHistory(core: core, limit: 100);
} on CoreFailure_Security catch (failure) {
  if (failure.failure is SecurityFailure_KeyringEntryMissing) {
    // Bu kurulum onarılamaz: yeni anahtar üretmek kayıtlı eşi ölü kılardı.
  }
}
```

`src/error.rs` içindeki testler bunu Rust tarafında sabitler: eksik kaydın adı
`device-signing-key-v1` olarak korunur ve metin çekirdeğinkiyle birebir aynıdır.

## İş parçacığı notu

`api.rs` içindeki hiçbir fonksiyon `#[frb(sync)]` **taşımaz** ve
`flutter_rust_bridge.yaml` içinde `default_dart_async: true` yazılıdır. Yani
Rust tarafı eş zamanlı, Dart tarafı `Future` döner ve gövde flutter_rust_bridge'in
iş parçacığı havuzunda çalışır. Bunun nedeni: `append_history` ve
`list_history` bloklayan SQLite yazmalarıdır; UI isolate'ine düşerlerse Flutter
arayüzü titrer. `default_dart_async: false` yapmak ya da bir fonksiyona
`#[frb(sync)]` eklemek aynı çağrıyı UI iş parçacığına taşır.

## Android ve gizli depo — çözülmedi, kayıt altına alındı

`keyring` 3'ün Android arka ucu **yoktur**. `mkvi_core` yalnızca
`cfg(windows)`, `cfg(target_os = "macos")` ve `cfg(target_os = "linux")` için
`keyring` bağımlılığı tanımlar, bu yüzden bugün Android hedefi **hiç derlenmez**:
`security.rs` içindeki `OsSecretStore` `keyring::` adını hiçbir `cfg` koruması
olmadan kullanıyor ve Android'de o isim çözümlenemiyor.

Doğrulama (bu makinede ölçüldü, tahmin edilmedi):

```
cd crates/mkvi_core
cargo tree -e normal                          # keyring v3.6.3 görünür
cargo tree --target aarch64-linux-android -e normal   # keyring YOK
```

`keyring` Android bağımlılık grafiğinde hiç yok. Bu yüzden Android'e girildiğinde
`security.rs` derlenemez. Doğrudan `cargo check --target aarch64-linux-android`
denendi ve **çalıştırılamadı**: bu makinede Android NDK'sı yok, `cc-rs`
`aarch64-linux-android-clang` bulamadı ve `libsqlite3-sys` (bundled SQLite)
derlenmeden önce başarısız oldu. Yani iddia çözümleyici düzeyinde kanıtlı,
derleme düzeyinde bu makinede kanıtlanamadı.

Bu, sessiz bir belirsizlikten iyidir ama bir çözüm değildir.

Tehlike, bunu "düzeltirken" yapılacak olan: `keyring`'i Android için de ekleyip
arka uç özelliği seçmemek. `keyring` 3 varsayılan özellik taşımaz ve hiçbiri
derlenmediğinde **bellek içi bir sahte depoya** düşer. O durumda `write` başarı
döner, sonraki açılışta değer kaybolur ve **her açılışta yeni bir cihaz kimliği
ile yeni bir veritabanı anahtarı üretilir** — yani MKVI'nin bir kez ödediği hata
tam olarak tekrarlanır.

`mkvi_core` bunu sessizce geçirmiyor: `SecurityError::SecretStoreMissing`
("yazılan değer geri okunamadı") ve `SecurityError::KeyringEntryMissing` ayrı
hallerdir ve `SecretOrigin` ilk çalıştırmayı "bu gizli mevcut olmalı" durumundan
ayırır. Yani hata **loud** olur. Ama bu yalnızca hatayı görünür kılar, kötü
durumu düzeltmez.

Android için gereken: platform kasasından beslenen bir `SecretStore`
uygulaması, ve `open_core`'in onu `keyring`'den **üretmek yerine geçmesi**.
Somut olarak:

* `open_core_with_store(data_dir, store: &dyn SecretStore)` bu yüzden
  `#[frb(ignore)]` ile var: `&dyn SecretStore` FFI sınırından geçemez, bu bir
  Rust tarafı kararıdır.
* Android'de `store` bir `flutter_secure_storage` arkasındaki platform kasasından
  beslenmelidir (`app/pubspec.yaml` bu paketi zaten içeriyor). Bir trait nesnesi
  Dart'tan gelemeyeceği için ya Rust tarafında bir Android `SecretStore` yazılır,
  ya da Dart'a bir FFI geri çağrısı (`#[frb(dart_fn)]`) eklenir. İkincisi daha
  az kod, ama her anahtar okuması/yazması FFI'ya düşer.
* `open_core` bugün `OsSecretStore`'u seçiyor; Android hedefi eklenirken **tek
  değişecek yer** burasıdır. O değişiklik yapılmadan Android'e girilmemeli.

## Gidiş-dönüş kanıtı

İki kanıt var ve ikisi de çalışıyor.

**1. Rust testleri** (`cargo test`, 15 test). `api.rs` içindeki testler, köprünün
dışa açtığı fonksiyonların *aynısını* çağırır — `open_core_with_store` ile bir
`Core` kurup yedi çağrıyı da üzerinden yürür. Geçici dizin ve bellek içi bir
`SecretStore` kullanırlar, yani testler gerçek Credential Manager'a dokunmaz.
Kapsananlar: imza/doğrulama gidiş-dönüşü, geçmiş ve eş gidiş-dönüşü, yeniden
açılışta kimliğin korunması, silinmiş `device-signing-key-v1` kaydının
`KeyringEntryMissing` olarak **adıyla** gelmesi, yinelenen `id`'nin geçmişi
değiştirmemesi.

**2. Dart betiği** (`dart/bin/round_trip.dart`). Üretilmiş API'yi gerçekten
çağırır ve bir değer basar.

```bash
cd crates/mkvi_bridge
cargo build --release
cd dart
dart pub get
dart run bin/round_trip.dart
```

`open_core` tek Dart'tan çağrılabilir kurucu olduğu için bu betik **gerçek** bir
cihaz kimliği üretir ve Windows Credential Manager'a `app.mkvi.desktop` altında
`device-signing-key-v1` ve `history-key-v1` kayıtlarını yazar. Bu kasıtlı
değil ama kaçınılmaz: köprüde bellek içi depo kullanan bir kurucu yoktur, çünkü
depoların seçimi Rust'ta. Betik ikinci kez çalıştığında aynı anahtarı bulur, yani
tekrar tekrar yeni kimlik üretmez. Kimlik silinmemelidir: silmek, kayıtlı bir eşi
öksüz bırakmanın ta kendisidir.

## Bağımlılıklar

* `mkvi_core` (yol) — davranışın tamamı.
* `flutter_rust_bridge = "=2.13.0"` — sürüm üreticiyle aynı olmalı.
* `base64` — imza tel biçimi, çekirdeğin `STANDARD_NO_PAD` ile aynı.

Dart tarafında `flutter_rust_bridge`, `freezed_annotation` ve üretici için
`build_runner` + `freezed` vardır. Başka hiçbir şey eklenmedi; özellikle Tauri'nin
`unstable` özelliği hiçbir yerde açılmadı ve bu crate Tauri'ye bağımlı değil.
