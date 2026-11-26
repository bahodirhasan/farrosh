//! Umumiy yordamchilar: papkalar, hajm hisoblash, o'chirish, Savatga ko'chirish.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from("C:\\"))
}

/// %LOCALAPPDATA%
pub fn local() -> PathBuf {
    dirs::data_local_dir().unwrap_or_else(|| home().join("AppData").join("Local"))
}

/// %APPDATA% (Roaming)
pub fn roaming() -> PathBuf {
    dirs::data_dir().unwrap_or_else(|| home().join("AppData").join("Roaming"))
}

pub fn local_low() -> PathBuf {
    home().join("AppData").join("LocalLow")
}

pub fn env_dir(var: &str, fallback: &str) -> PathBuf {
    std::env::var_os(var).map(PathBuf::from).unwrap_or_else(|| PathBuf::from(fallback))
}

pub fn program_data() -> PathBuf {
    env_dir("ProgramData", "C:\\ProgramData")
}

pub fn windows_dir() -> PathBuf {
    env_dir("SystemRoot", "C:\\Windows")
}

pub fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

pub fn mtime(md: &fs::Metadata) -> u64 {
    md.modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Bulutda turgan, kompyuterga yuklanmagan fayl (OneDrive "faqat onlayn").
/// Uni o'qish yuklab olishni boshlaydi, hajmi esa diskda yo'q — shuning uchun hisobga olinmaydi.
#[cfg(windows)]
pub fn is_cloud_only(md: &fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt;
    const RECALL_ON_DATA_ACCESS: u32 = 0x0040_0000;
    const RECALL_ON_OPEN: u32 = 0x0004_0000;
    const OFFLINE: u32 = 0x1000;
    md.file_attributes() & (RECALL_ON_DATA_ACCESS | RECALL_ON_OPEN | OFFLINE) != 0
}

#[cfg(not(windows))]
pub fn is_cloud_only(_md: &fs::Metadata) -> bool {
    false
}

/// Ramziy havola yoki junction: ichiga kirilmaydi, nishoni o'chirilmaydi.
pub fn is_link(md: &fs::Metadata) -> bool {
    md.file_type().is_symlink()
}

/// Papkani aylanib chiqadi. `skip_dir` true qaytargan papkalarga kirilmaydi.
pub fn walk<F>(root: &Path, skip_dir: &dyn Fn(&Path) -> bool, f: &mut F)
where
    F: FnMut(&Path, &fs::Metadata),
{
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(rd) = fs::read_dir(&dir) else { continue };
        for entry in rd.flatten() {
            let path = entry.path();
            let Ok(md) = entry.metadata() else { continue };
            if is_link(&md) {
                continue;
            }
            if md.is_dir() {
                if !skip_dir(&path) {
                    stack.push(path);
                }
            } else {
                f(&path, &md);
            }
        }
    }
}

/// Papka hajmi (bulutdagi fayllarsiz).
pub fn dir_size(p: &Path) -> u64 {
    let mut total = 0u64;
    walk(p, &|_| false, &mut |_, md| {
        if !is_cloud_only(md) {
            total += md.len();
        }
    });
    total
}

/// Papka hajmi va undagi eng yangi faylning vaqti.
pub fn dir_size_newest(p: &Path) -> (u64, u64) {
    let (mut total, mut newest) = (0u64, 0u64);
    walk(p, &|_| false, &mut |_, md| {
        if !is_cloud_only(md) {
            total += md.len();
        }
        newest = newest.max(mtime(md));
    });
    (total, newest)
}

pub fn size_of(p: &Path) -> u64 {
    match fs::symlink_metadata(p) {
        Ok(md) if is_link(&md) => 0,
        Ok(md) if md.is_dir() => dir_size(p),
        Ok(md) => md.len(),
        Err(_) => 0,
    }
}

/// Papka ichidagi birinchi darajadagi narsalar hajmi; `older_than` berilsa — faqat shundan eskilari.
pub fn children_size(dir: &Path, older_than: Option<u64>) -> u64 {
    let Ok(rd) = fs::read_dir(dir) else { return 0 };
    let limit = older_than.map(|s| now().saturating_sub(s));
    rd.flatten()
        .filter(|e| match (limit, e.metadata()) {
            (Some(l), Ok(md)) => mtime(&md) < l,
            (None, _) => true,
            _ => false,
        })
        .map(|e| size_of(&e.path()))
        .sum()
}

fn remove_link(p: &Path, md: &fs::Metadata) -> bool {
    if md.is_dir() {
        fs::remove_dir(p).is_ok()
    } else {
        fs::remove_file(p).is_ok()
    }
}

/// O'chiriladigan narsani imkon qadar o'chiradi. Band fayllar qoladi.
/// Qaytaradi: (bo'shagan bayt, o'chmagan elementlar soni).
pub fn purge(p: &Path, keep_root: bool) -> (u64, u32) {
    let Ok(md) = fs::symlink_metadata(p) else { return (0, 0) };
    if is_link(&md) {
        if keep_root {
            return (0, 0);
        }
        return if remove_link(p, &md) { (0, 0) } else { (0, 1) };
    }
    if md.is_dir() {
        let (mut freed, mut failed) = (0u64, 0u32);
        if let Ok(rd) = fs::read_dir(p) {
            for e in rd.flatten() {
                let (a, b) = purge(&e.path(), false);
                freed += a;
                failed += b;
            }
        }
        if !keep_root && fs::remove_dir(p).is_err() && failed == 0 {
            failed += 1;
        }
        return (freed, failed);
    }
    let len = if is_cloud_only(&md) { 0 } else { md.len() };
    if fs::remove_file(p).is_ok() {
        return (len, 0);
    }
    // Faqat o'qish uchun belgilangan fayl.
    let mut perm = md.permissions();
    if perm.readonly() {
        #[allow(clippy::permissions_set_readonly_false)]
        perm.set_readonly(false);
        let _ = fs::set_permissions(p, perm);
        if fs::remove_file(p).is_ok() {
            return (len, 0);
        }
    }
    (0, 1)
}

/// Papka ichini tozalaydi; `older_than` berilsa — faqat shundan eski narsalarni (vaqtinchalik fayllar uchun).
pub fn purge_children(dir: &Path, older_than: Option<u64>) -> (u64, u32) {
    let Ok(rd) = fs::read_dir(dir) else { return (0, 0) };
    let limit = older_than.map(|s| now().saturating_sub(s));
    let (mut freed, mut failed) = (0u64, 0u32);
    for e in rd.flatten() {
        if let (Some(l), Ok(md)) = (limit, e.metadata()) {
            if mtime(&md) >= l {
                continue;
            }
        }
        let (a, b) = purge(&e.path(), false);
        freed += a;
        failed += b;
    }
    (freed, failed)
}

/// Faqat foydalanuvchi papkasi, ProgramData va Windows\Temp ichidagi, chuqurroq yo'llar qabul qilinadi.
/// Asosiy papkalarning o'zi (Hujjatlar, AppData va h.k.) hech qachon butunligicha o'chirilmaydi.
pub fn is_safe(p: &Path) -> bool {
    check_path(p, false)
}

/// Ichini tozalash uchun (kesh, Temp): papkaning o'zi qoladi, shuning uchun Temp kabi papkalar ham qabul qilinadi.
pub fn is_safe_to_empty(p: &Path) -> bool {
    check_path(p, true)
}

fn check_path(p: &Path, children: bool) -> bool {
    let low = |x: &Path| x.to_string_lossy().trim_end_matches('\\').to_lowercase();
    let lp = low(p);
    if lp.contains("..") || p.components().count() < 4 {
        return false;
    }
    let win_temp = low(&windows_dir().join("Temp"));
    let roots = [low(&home()), low(&program_data()), win_temp.clone()];
    let inside = roots.iter().any(|r| lp.starts_with(&(r.clone() + "\\"))) || (children && lp == win_temp);
    if !inside {
        return false;
    }
    let mut forbidden = vec![home(), local(), roaming(), local_low(), program_data()];
    if !children {
        forbidden.push(windows_dir().join("Temp"));
        forbidden.push(std::env::temp_dir());
        for d in [dirs::document_dir(), dirs::desktop_dir(), dirs::download_dir(), dirs::picture_dir(), dirs::video_dir(), dirs::audio_dir()]
            .into_iter()
            .flatten()
        {
            forbidden.push(d);
        }
    }
    !forbidden.iter().any(|f| low(f) == lp)
}

/// Sozlamaga qarab: Savatga ko'chiradi yoki butunlay o'chiradi. Hajmini qaytaradi.
pub fn discard(p: &Path, permanent: bool) -> Result<u64, String> {
    if !is_safe(p) {
        return Err(format!("ruxsat etilmagan yo'l: {}", p.display()));
    }
    let size = size_of(p);
    if permanent {
        let (_, failed) = purge(p, false);
        if failed > 0 {
            return Err(format!("{} ta element o'chmadi", failed));
        }
    } else {
        trash::delete(p).map_err(|e| e.to_string())?;
    }
    Ok(size)
}

/// Uy papkasini ~ bilan qisqartiradi.
pub fn pretty(p: &Path) -> String {
    let h = home();
    match p.strip_prefix(&h) {
        Ok(rest) => format!("~\\{}", rest.display()),
        Err(_) => p.display().to_string(),
    }
}

pub fn name_of(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default()
}

/// Taqqoslash uchun: faqat kichik harf va raqamlar.
pub fn norm(s: &str) -> String {
    s.chars().filter(|c| c.is_alphanumeric()).flat_map(|c| c.to_lowercase()).collect()
}

/// Explorer bilan bir xil: 1024 asosida.
pub fn fmt_bytes(b: u64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"];
    let mut v = b as f64;
    let mut i = 0;
    while v >= 1024.0 && i < units.len() - 1 {
        v /= 1024.0;
        i += 1;
    }
    if i == 0 {
        format!("{} B", b)
    } else if v >= 100.0 {
        format!("{:.0} {}", v, units[i])
    } else {
        format!("{:.1} {}", v, units[i])
    }
}

pub fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}
