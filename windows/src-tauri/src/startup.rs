//! Windows yonganda o'zi ishga tushadigan dasturlar.
//! O'chirish/yoqish Vazifalar menejeri (Task Manager) bilan bir xil usulda — StartupApproved kaliti orqali,
//! shuning uchun istalgan payt qaytarish mumkin.

use crate::util::*;
use serde::Serialize;
use std::path::PathBuf;

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub command: String,
    /// "user" | "machine"
    pub scope: String,
    /// "registry" | "folder"
    pub kind: String,
    pub enabled: bool,
}

const RUN: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
const APPROVED: &str = r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved";

fn user_folder() -> PathBuf {
    roaming().join(r"Microsoft\Windows\Start Menu\Programs\Startup")
}

fn common_folder() -> PathBuf {
    program_data().join(r"Microsoft\Windows\Start Menu\Programs\StartUp")
}

#[cfg(windows)]
mod imp {
    use super::*;
    use winreg::enums::*;
    use winreg::{RegKey, RegValue};

    /// (manba, kalit, Run yo'li uchun flaglar, StartupApproved ostidagi bo'lim, foydalanuvchimi)
    fn reg_sources() -> Vec<(&'static str, RegKey, u32, &'static str, bool)> {
        vec![
            ("hkcu-run", RegKey::predef(HKEY_CURRENT_USER), KEY_READ, "Run", true),
            ("hklm-run", RegKey::predef(HKEY_LOCAL_MACHINE), KEY_READ | KEY_WOW64_64KEY, "Run", false),
            ("hklm-run32", RegKey::predef(HKEY_LOCAL_MACHINE), KEY_READ | KEY_WOW64_32KEY, "Run32", false),
        ]
    }

    fn approved_key(user: bool) -> RegKey {
        RegKey::predef(if user { HKEY_CURRENT_USER } else { HKEY_LOCAL_MACHINE })
    }

    fn is_enabled(user: bool, section: &str, name: &str) -> bool {
        approved_key(user)
            .open_subkey(format!("{}\\{}", APPROVED, section))
            .and_then(|k| k.get_raw_value(name))
            .map(|v| v.bytes.first().map(|b| b & 1 == 0).unwrap_or(true))
            .unwrap_or(true)
    }

    pub fn list() -> Vec<Entry> {
        let mut out = vec![];
        for (src, hive, flags, section, user) in reg_sources() {
            let Ok(k) = hive.open_subkey_with_flags(RUN, flags) else { continue };
            for (name, value) in k.enum_values().flatten() {
                let command = value.to_string().trim_matches('"').to_string();
                out.push(Entry {
                    id: format!("{}|{}", src, name),
                    enabled: is_enabled(user, section, &name),
                    name,
                    command,
                    scope: if user { "user".into() } else { "machine".into() },
                    kind: "registry".into(),
                });
            }
        }
        for (src, dir, user) in [("user-folder", user_folder(), true), ("common-folder", common_folder(), false)] {
            let Ok(rd) = std::fs::read_dir(&dir) else { continue };
            for e in rd.flatten() {
                let file = e.file_name().to_string_lossy().to_string();
                if file.eq_ignore_ascii_case("desktop.ini") || e.path().is_dir() {
                    continue;
                }
                let name = e.path().file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or(file.clone());
                out.push(Entry {
                    id: format!("{}|{}", src, file),
                    enabled: is_enabled(user, "StartupFolder", &file),
                    name,
                    command: pretty(&e.path()),
                    scope: if user { "user".into() } else { "machine".into() },
                    kind: "folder".into(),
                });
            }
        }
        out.sort_by_key(|e| e.name.to_lowercase());
        out
    }

    fn parse(id: &str) -> Option<(&str, &str, &'static str, bool)> {
        let (src, name) = id.split_once('|')?;
        let (section, user) = match src {
            "hkcu-run" => ("Run", true),
            "hklm-run" => ("Run", false),
            "hklm-run32" => ("Run32", false),
            "user-folder" => ("StartupFolder", true),
            "common-folder" => ("StartupFolder", false),
            _ => return None,
        };
        Some((src, name, section, user))
    }

    fn err(e: std::io::Error) -> String {
        if e.kind() == std::io::ErrorKind::PermissionDenied { "admin".into() } else { e.to_string() }
    }

    pub fn set_enabled(id: &str, on: bool) -> Result<(), String> {
        let (_, name, section, user) = parse(id).ok_or("bad-id")?;
        let (k, _) = approved_key(user).create_subkey(format!("{}\\{}", APPROVED, section)).map_err(err)?;
        // 12 bayt: birinchisi 02 — yoqilgan, 03 — o'chirilgan; qolgani o'chirilgan vaqt (FILETIME).
        let mut bytes = vec![if on { 2u8 } else { 3u8 }, 0, 0, 0];
        let ft: u64 = if on { 0 } else { (now() + 11_644_473_600) * 10_000_000 };
        bytes.extend_from_slice(&ft.to_le_bytes());
        k.set_raw_value(name, &RegValue { bytes, vtype: REG_BINARY }).map_err(err)
    }

    pub fn remove(id: &str) -> Result<(), String> {
        let (src, name, section, user) = parse(id).ok_or("bad-id")?;
        match src {
            "user-folder" | "common-folder" => {
                let dir = if user { user_folder() } else { common_folder() };
                trash::delete(dir.join(name)).map_err(|e| if user { e.to_string() } else { "admin".into() })?;
            }
            _ => {
                let (hive, flags, _, _, _) = reg_sources().into_iter().find(|s| s.0 == src).map(|s| (s.1, s.2, s.3, s.4, ())).ok_or("bad-id")?;
                let k = hive.open_subkey_with_flags(RUN, (flags & !KEY_READ) | KEY_SET_VALUE).map_err(err)?;
                k.delete_value(name).map_err(err)?;
            }
        }
        if let Ok(k) = approved_key(user).open_subkey_with_flags(format!("{}\\{}", APPROVED, section), KEY_SET_VALUE) {
            let _ = k.delete_value(name);
        }
        Ok(())
    }
}

#[cfg(windows)]
pub use imp::{list, remove, set_enabled};

#[cfg(not(windows))]
pub fn list() -> Vec<Entry> {
    let _ = (RUN, APPROVED, user_folder(), common_folder());
    vec![]
}
#[cfg(not(windows))]
pub fn set_enabled(_id: &str, _on: bool) -> Result<(), String> {
    Err("windows-only".into())
}
#[cfg(not(windows))]
pub fn remove(_id: &str) -> Result<(), String> {
    Err("windows-only".into())
}
