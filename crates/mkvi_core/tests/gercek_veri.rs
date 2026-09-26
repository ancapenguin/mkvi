//! Gerçek kurulumun verisini okuyan TEK SEFERLIK kanıt testi.
//!
//! Bu test varsayilan olarak **calismaz** (`#[ignore]`); kapıya girmez, CI'da
//! calismaz. Amaci: gelistirme sirasinda uretilen bir anahtarin, kullanilinin
//! gercek sifreli veritabanini acmaya devam edip etmedigini kanitlamak.
//!
//! Calistirma:
//!
//! ```text
//! cd crates/mkvi_core
//! MKVI_REAL_DATA=1 cargo test --test gercek_veri -- --ignored --nocapture
//! ```
//!
//! `MKVI_REAL_DATA` verilmezse test kendini atlar. Veri dizini varsayilan olarak
//! Tauri 0.1.x'in kullandigi yoldur; `MKVI_DATA_DIR` ile degistirilebilir.
//!
//! Bu test **okur, yazmaz**: `EncryptedHistory::open` yalnizca dosyayi acar ve
//! anahtari zaten var olan bir kasadan okur. `peers()` cagrisi sifre cozme
//! dener ve **hata halinde hata doner** — sessizce bos liste donmez. Bu yuzden
//! "kayit yok" ile "sifre cozulemiyor" birbirinden ayrilir.

use mkvi_core::{EncryptedHistory, OsSecretStore};

/// 0.1.x'in veri yolu. Tauri `app_data_dir()` kullanir, bu da
/// `%APPDATA%\<identifier>` demektir.
fn real_data_dir() -> Option<std::path::PathBuf> {
    if std::env::var("MKVI_REAL_DATA").ok().as_deref() != Some("1") {
        return None;
    }
    if let Ok(explicit) = std::env::var("MKVI_DATA_DIR") {
        return Some(std::path::PathBuf::from(explicit));
    }
    let appdata = std::env::var("APPDATA").ok()?;
    Some(
        std::path::PathBuf::from(appdata)
            .join("com.mkvi.desktop")
            .join("history.sqlite3"),
    )
}

// `#[ignore]` 2026-09-26'da eklendi. Dosya bunu daha once yaziyordu ama nitelik
// yoktu: `cargo test --test gercek_veri -- --ignored` HICBIR TESTLE eslesmiyor,
// hicbir sey kosmadan yesil geciyordu; `cargo test` (kapi) ise testi kosuyor ve
// o da sessizce `return` ediyordu. Yani kapida olmayan bir test, kapida olan
// ama hicbir sey olcmeyen bir test. Artik belgelenen komut gercekten bu testi
// kosuyor ve kapi bunu atliyor.
#[test]
#[ignore = "gercek kurulumun verisini okur; MKVI_REAL_DATA=1 ile elle kosulur"]
fn gercek_kurulum_verisi_aciliyor_mu() {
    let Some(path) = real_data_dir() else {
        eprintln!("atlandi: MKVI_REAL_DATA=1 verilmedi");
        return;
    };

    if !path.exists() {
        eprintln!("atlandi: {} yok", path.display());
        return;
    }
    let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
    println!("veri dosyasi: {} ({} bayt)", path.display(), size);

    let store = OsSecretStore;
    let history = match EncryptedHistory::open(&path, &store) {
        Ok(history) => history,
        Err(error) => {
            // Bu, anahtarin degismis oldugunun kanitidir ve duzeltilmesi
            // gerekir: eski anahtri geri koymak ya da veritabanini yedekten
            // dondurmek gerekir. SESSIZCE devam etmiyoruz.
            panic!(
                "KRITIK: {} acilamadi: {}. Anahtar kasadakiyle eslesmiyor \
                 (dosya var, anahtar yanlis).",
                path.display(),
                error
            );
        }
    };

    match history.peers() {
        Ok(peers) => {
            println!("acildi. es sayisi: {}", peers.len());
            for peer in &peers {
                println!("  es: {}", peer.public_key);
                // Gorunur adi yaziyoruz ama gizli bir sey degil; kullanici
                // bunu zaten arayuzunde goruyor.
                println!("     kayitli ad: {}", peer.display_name);
            }
        }
        Err(error) => {
            panic!(
                "KRITIK: dosya acildi ama esler COZULEMEDI: {}. Anahtar \
                 dosyaya ait degil.",
                error
            );
        }
    }
}
