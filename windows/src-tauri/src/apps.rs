//! O'rnatilgan dasturlar (Windows registridagi Uninstall ro'yxati), ularni o'chirish va qoldiqlarini topish.

use crate::junk::Item;
use crate::util::*;
use serde::Serialize;
use std::path::{Path, PathBuf};

#[derive(Serialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct App {
    pub id: String,
    pub name: String,
    pub version: String,
    pub publisher: String,
    pub size: u64,
    pub location: String,
    /// YYYY-MM-DD
    pub installed: String,
    /// "machine" — barcha foydalanuvchilar uchun, "user" — faqat shu foydalanuvchi.
    pub scope: String,
    pub has_quiet: bool,
}

const UNINSTALL: &str = r"Software\Microsoft\Windows\CurrentVersion\Uninstall";

#[cfg(windows)]
mod reg {
    use winreg::enums::*;
    use winreg::RegKey;

    pub fn hives() -> Vec<(&'static str, RegKey, u32)> {
        vec![
            ("HKLM64", RegKey::predef(HKEY_LOCAL_MACHINE), KEY_READ | KEY_WOW64_64KEY),
            ("HKLM32", RegKey::predef(HKEY_LOCAL_MACHINE), KEY_READ | KEY_WOW64_32KEY),
            ("HKCU", RegKey::predef(HKEY_CURRENT_USER), KEY_READ),
        ]
    }

    pub fn open(id: &str) -> Option<RegKey> {
        let (hive, sub) = id.split_once('|')?;
        let (key, flags) = hives().into_iter().find(|(n, _, _)| *n == hive).map(|(_, k, f)| (k, f))?;
        key.open_subkey_with_flags(format!("{}\\{}", super::UNINSTALL, sub), flags).ok()
    }

    pub fn s(k: &RegKey, name: &str) -> String {
        k.get_value::<String, _>(name).map(|v| v.trim().to_string()).unwrap_or_default()
    }

    pub fn n(k: &RegKey, name: &str) -> u32 {
        k.get_value::<u32, _>(name).unwrap_or(0)
    }
}

/// Ro'yxatdagi dasturlar. `sizes` false bo'lsa, hajmi registrda yo'q dasturlar papkasi o'lchanmaydi (tezroq).
#[cfg(windows)]
pub fn list(sizes: bool) -> Vec<App> {
    let mut out: Vec<App> = vec![];
    let mut seen = std::collections::HashSet::new();
    for (hive, key, flags) in reg::hives() {
        let Ok(root) = key.open_subkey_with_flags(UNINSTALL, flags) else { continue };
        for sub in root.enum_keys().flatten() {
            let Ok(k) = root.open_subkey_with_flags(&sub, flags) else { continue };
            let name = reg::s(&k, "DisplayName");
            if name.is_empty() || reg::n(&k, "SystemComponent") == 1 || !reg::s(&k, "ParentKeyName").is_empty() {
                continue;
            }
            let release = reg::s(&k, "ReleaseType").to_lowercase();
            if release.contains("update") || release.contains("hotfix") || reg::s(&k, "UninstallString").is_empty() {
                continue;
            }
            let version = reg::s(&k, "DisplayVersion");
            if !seen.insert((name.to_lowercase(), version.clone())) {
                continue;
            }
            let date = reg::s(&k, "InstallDate");
            let installed = if date.len() == 8 && date.chars().all(|c| c.is_ascii_digit()) {
                format!("{}-{}-{}", &date[0..4], &date[4..6], &date[6..8])
            } else {
                String::new()
            };
            out.push(App {
                id: format!("{}|{}", hive, sub),
                name,
                version,
                publisher: reg::s(&k, "Publisher"),
                size: reg::n(&k, "EstimatedSize") as u64 * 1024,
                location: reg::s(&k, "InstallLocation").trim_matches('"').to_string(),
                installed,
                scope: if hive == "HKCU" { "user".into() } else { "machine".into() },
                has_quiet: !reg::s(&k, "QuietUninstallString").is_empty(),
            });
        }
    }
    if sizes {
        // Hajmi yozilmagan dasturlar papkasini parallel o'lchaymiz.
        let need: Vec<usize> = (0..out.len())
            .filter(|&i| out[i].size == 0 && !out[i].location.is_empty() && Path::new(&out[i].location).is_dir())
            .collect();
        let measured: Vec<(usize, u64)> = std::thread::scope(|sc| {
            let handles: Vec<_> = need
                .chunks(need.len().div_ceil(8).max(1))
                .map(|chunk| {
                    let locs: Vec<(usize, String)> = chunk.iter().map(|&i| (i, out[i].location.clone())).collect();
                    sc.spawn(move || locs.into_iter().map(|(i, l)| (i, dir_size(Path::new(&l)))).collect::<Vec<_>>())
                })
                .collect();
            handles.into_iter().flat_map(|h| h.join().unwrap_or_default()).collect()
        });
        for (i, size) in measured {
            out[i].size = size;
        }
    }
    out.sort_by(|a, b| b.size.cmp(&a.size));
    out
}

#[cfg(not(windows))]
pub fn list(_sizes: bool) -> Vec<App> {
    vec![]
}

/// Qoldiqlarni aniqlash uchun: (nom, nashriyotchi).
pub fn names() -> Vec<(String, String)> {
    list(false).into_iter().map(|a| (a.name, a.publisher)).collect()
}

#[cfg(windows)]
pub fn exists(id: &str) -> bool {
    reg::open(id).is_some()
}

#[cfg(not(windows))]
pub fn exists(_id: &str) -> bool {
    false
}

/// "C:\Program Files\X\uninst.exe" /S  →  (exe, argumentlar)
fn split_command(c: &str) -> (String, String) {
    let c = c.trim();
    if let Some(rest) = c.strip_prefix('"') {
        if let Some(i) = rest.find('"') {
            return (rest[..i].to_string(), rest[i + 1..].trim().to_string());
        }
    }
    let low = c.to_ascii_lowercase();
    if let Some(i) = low.find(".exe") {
        let end = i + 4;
        return (c[..end].to_string(), c[end..].trim().to_string());
    }
    match c.split_once(' ') {
        Some((a, b)) => (a.to_string(), b.trim().to_string()),
        None => (c.to_string(), String::new()),
    }
}

/// Ba'zi MSI yozuvlarida "o'rnatish" (/I) buyrug'i turadi — uni "o'chirish" (/X) ga almashtiramiz.
fn fix_msi(c: &str) -> String {
    let low = c.to_ascii_lowercase();
    if !low.contains("msiexec") {
        return c.to_string();
    }
    let mut s = c.to_string();
    for pat in ["/i{", "/i {"] {
        if let Some(i) = s.to_ascii_lowercase().find(pat) {
            s.replace_range(i..i + 2, "/X");
        }
    }
    s
}

/// Dasturning o'z o'chirish dasturini ishga tushiradi. Windows administrator ruxsatini kerak bo'lsa o'zi so'raydi (UAC).
/// Ko'p o'chirish dasturlari (NSIS) o'z nusxasini ishga tushirib darhol yopiladi, shuning uchun jarayon kutilmaydi —
/// interfeys `exists` bilan dastur ro'yxatdan yo'qolishini kuzatadi va foydalanuvchi kutishni to'xtata oladi.
/// Qaytaradi: dastur allaqachon ro'yxatdan yo'qoldimi.
#[cfg(windows)]
pub fn uninstall(id: &str, quiet: bool) -> Result<bool, String> {
    use windows_sys::Win32::Foundation::{CloseHandle, GetLastError};
    use windows_sys::Win32::UI::Shell::{ShellExecuteExW, SEE_MASK_NOCLOSEPROCESS, SHELLEXECUTEINFOW};
    use windows_sys::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;

    let k = reg::open(id).ok_or_else(|| "not-found".to_string())?;
    let quiet_cmd = reg::s(&k, "QuietUninstallString");
    let cmd = if quiet && !quiet_cmd.is_empty() { quiet_cmd } else { reg::s(&k, "UninstallString") };
    if cmd.is_empty() {
        return Err("no-uninstaller".into());
    }
    let (exe, args) = split_command(&fix_msi(&cmd));
    let exe_w = wide(&exe);
    let args_w = wide(&args);
    let verb = wide("open");
    unsafe {
        let mut sei: SHELLEXECUTEINFOW = std::mem::zeroed();
        sei.cbSize = std::mem::size_of::<SHELLEXECUTEINFOW>() as u32;
        sei.fMask = SEE_MASK_NOCLOSEPROCESS;
        sei.lpVerb = verb.as_ptr();
        sei.lpFile = exe_w.as_ptr();
        sei.lpParameters = args_w.as_ptr();
        sei.nShow = SW_SHOWNORMAL;
        if ShellExecuteExW(&mut sei) == 0 {
            let err = GetLastError();
            // 1223: foydalanuvchi UAC oynasida "Yo'q" ni bosdi.
            return Err(if err == 1223 { "cancelled".into() } else { format!("start-failed:{}", err) });
        }
        if !sei.hProcess.is_null() {
            CloseHandle(sei.hProcess);
        }
    }
    std::thread::sleep(std::time::Duration::from_millis(1500));
    Ok(!exists(id))
}

#[cfg(not(windows))]
pub fn uninstall(_id: &str, _quiet: bool) -> Result<bool, String> {
    Err("windows-only".into())
}

/// Nomidan versiya va bit sonini olib tashlaydi: "7-Zip 23.01 (x64)" → "7-Zip".
fn base_name(name: &str) -> String {
    let words: Vec<&str> = name
        .split_whitespace()
        .take_while(|w| !w.starts_with('(') && !w.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) && !w.eq_ignore_ascii_case("version"))
        .collect();
    if words.is_empty() { name.to_string() } else { words.join(" ") }
}

const GENERIC: &[&str] = &["microsoft", "windows", "google", "adobe", "visual", "java", "update", "tools", "driver", "intel", "nvidia", "amd", "the", "free", "open"];

/// O'chirilgan dastur qoldiqlari: AppData va ProgramData'dagi shu nomli papkalar va o'rnatilgan papkaning o'zi.
pub fn leftovers(name: &str, publisher: &str, location: &str) -> Vec<Item> {
    let base = norm(&base_name(name));
    let full = norm(name);
    let publ = norm(publisher);
    let first = name.split_whitespace().next().map(norm).unwrap_or_default();
    let mut found: Vec<(PathBuf, bool)> = vec![];
    let matches_exact = |n: &str| n == base || n == full;
    let matches_loose = |n: &str| first.len() >= 4 && !GENERIC.contains(&first.as_str()) && n == first;

    for root in [roaming(), local(), local_low(), program_data()] {
        let Ok(rd) = std::fs::read_dir(&root) else { continue };
        for e in rd.flatten() {
            let Ok(md) = e.metadata() else { continue };
            if !md.is_dir() || is_link(&md) {
                continue;
            }
            let n = norm(&e.file_name().to_string_lossy());
            if n.is_empty() {
                continue;
            }
            if matches_exact(&n) {
                found.push((e.path(), false));
            } else if matches_loose(&n) {
                found.push((e.path(), true));
            } else if !publ.is_empty() && (n == publ || publ.starts_with(&n) && n.len() >= 4) && !GENERIC.contains(&n.as_str()) {
                // Nashriyotchi papkasi ichida dastur nomli papka.
                if let Ok(inner) = std::fs::read_dir(e.path()) {
                    for c in inner.flatten() {
                        let cn = norm(&c.file_name().to_string_lossy());
                        if c.path().is_dir() && (matches_exact(&cn) || matches_loose(&cn)) {
                            found.push((c.path(), false));
                        }
                    }
                }
            }
        }
    }
    let loc = PathBuf::from(location);
    if !location.is_empty() && loc.is_dir() {
        found.push((loc, false));
    }
    found.sort();
    found.dedup_by(|a, b| a.0 == b.0);
    found
        .into_iter()
        // Program Files ichidagilarni oddiy foydalanuvchi o'chira olmaydi — faqat o'z papkalari ko'rsatiladi.
        .filter(|(p, _)| is_safe(p))
        .filter_map(|(p, review)| {
            let size = dir_size(&p);
            (size > 0).then(|| Item {
                id: format!("left:{}", p.display()),
                name: name_of(&p),
                detail: pretty(&p),
                paths: vec![p.display().to_string()],
                size,
                review,
                selected: !review,
                ..Default::default()
            })
        })
        .collect()
}
