//! Incoming file transfer primitives. No UI framework, no transport.
use std::fs::File;
use std::path::{Path, PathBuf};

/// Upper bound mirrored from `src/domain/peer-transport.ts` (MAX_FILE_BYTES).
pub const MAX_FILE_BYTES: u64 = 512 * 1024 * 1024;

/// An in-progress incoming transfer being streamed straight to disk.
pub struct FileSink {
    pub handle: File,
    pub path: PathBuf,
    pub written: u64,
}

/// Transfer ids are the 16-byte hex ids minted by `peer-transport.ts`.
pub fn valid_transfer_id(id: &str) -> bool {
    id.len() == 32 && id.bytes().all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

/// Strips path separators and control characters so a peer cannot pick the target path.
pub fn sanitize_file_name(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .map(|character| {
            if character.is_control() || matches!(character, '\\' | '/' | ':' | '*' | '?' | '"' | '<' | '>' | '|') {
                '_'
            } else {
                character
            }
        })
        .collect();
    let trimmed = cleaned.trim().trim_matches('.').trim();
    let bounded: String = trimmed.chars().take(160).collect();
    if bounded.is_empty() {
        "dosya".to_string()
    } else {
        bounded
    }
}

/// Never overwrites: appends " (1)", " (2)", … until the name is free.
pub fn unique_path(directory: &Path, name: &str) -> PathBuf {
    let candidate = directory.join(name);
    if !candidate.exists() {
        return candidate;
    }
    let (stem, extension) = match name.rsplit_once('.') {
        Some((stem, extension)) if !stem.is_empty() => (stem, format!(".{extension}")),
        _ => (name, String::new()),
    };
    for index in 1..10_000 {
        let candidate = directory.join(format!("{stem} ({index}){extension}"));
        if !candidate.exists() {
            return candidate;
        }
    }
    directory.join(format!("{stem} ({}){extension}", std::process::id()))
}

#[cfg(test)]
mod tests {
    use super::{sanitize_file_name, unique_path, valid_transfer_id};

    #[test]
    fn transfer_ids_must_be_lowercase_hex_of_16_bytes() {
        assert!(valid_transfer_id(&"a".repeat(32)));
        assert!(!valid_transfer_id(&"A".repeat(32)));
        assert!(!valid_transfer_id(&"a".repeat(31)));
        assert!(!valid_transfer_id("../../etc/passwd"));
    }

    #[test]
    fn file_names_lose_traversal_and_control_characters() {
        // Separators become underscores and the leading dots are trimmed away.
        assert_eq!(sanitize_file_name("../../gizli.txt"), "_.._gizli.txt");
        assert_eq!(sanitize_file_name("C:\\Windows\\a.exe"), "C__Windows_a.exe");
        assert_eq!(sanitize_file_name("   ...   "), "dosya");
        assert_eq!(sanitize_file_name("rapor\u{0}.pdf"), "rapor_.pdf");
        assert_eq!(sanitize_file_name(&"x".repeat(300)).chars().count(), 160);
    }

    #[test]
    fn existing_files_are_never_overwritten() {
        let directory = std::env::temp_dir().join(format!("mkvi-sink-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let first = unique_path(&directory, "rapor.pdf");
        assert_eq!(first, directory.join("rapor.pdf"));
        std::fs::write(&first, b"x").unwrap();
        assert_eq!(unique_path(&directory, "rapor.pdf"), directory.join("rapor (1).pdf"));
        std::fs::remove_dir_all(&directory).unwrap();
    }
}
