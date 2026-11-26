//! Disklar: hajmi va bo'sh joyi (Explorer ko'rsatadigan qiymatlar), administrator huquqlari.

use serde::Serialize;
use std::path::PathBuf;

#[derive(Serialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct Disk {
    pub letter: String,
    pub label: String,
    /// fixed · removable · network · cdrom · ram
    pub kind: String,
    pub total: u64,
    pub free: u64,
    pub used: u64,
    pub system: bool,
}

pub fn system_drive() -> String {
    std::env::var("SystemDrive").unwrap_or_else(|_| "C:".into())
}

#[cfg(windows)]
fn measure(letter: &str) -> Option<Disk> {
    use windows_sys::Win32::Storage::FileSystem::{GetDiskFreeSpaceExW, GetDriveTypeW, GetVolumeInformationW};
    let root = crate::util::wide(&format!("{}\\", letter));
    let kind = match unsafe { GetDriveTypeW(root.as_ptr()) } {
        2 => "removable",
        3 => "fixed",
        4 => "network",
        5 => "cdrom",
        6 => "ram",
        _ => return None,
    };
    let (mut avail, mut total, mut total_free) = (0u64, 0u64, 0u64);
    // Bo'sh CD yoki kartasiz kartridjer: hajmi o'qilmaydi — ro'yxatga kirmaydi.
    if unsafe { GetDiskFreeSpaceExW(root.as_ptr(), &mut avail, &mut total, &mut total_free) } == 0 || total == 0 {
        return None;
    }
    let mut name = [0u16; 261];
    let ok = unsafe {
        GetVolumeInformationW(root.as_ptr(), name.as_mut_ptr(), name.len() as u32, std::ptr::null_mut(), std::ptr::null_mut(), std::ptr::null_mut(), std::ptr::null_mut(), 0)
    };
    let label = if ok != 0 {
        let n = name.iter().position(|&c| c == 0).unwrap_or(0);
        String::from_utf16_lossy(&name[..n])
    } else {
        String::new()
    };
    Some(Disk {
        letter: letter.to_string(),
        label,
        kind: kind.into(),
        total,
        free: avail,
        used: total.saturating_sub(total_free),
        system: letter.eq_ignore_ascii_case(&system_drive()),
    })
}

/// Kompyuterdagi barcha disklar (A: dan Z: gacha), tizim diski birinchi.
#[cfg(windows)]
pub fn list() -> Vec<Disk> {
    use windows_sys::Win32::Storage::FileSystem::GetLogicalDrives;
    let mask = unsafe { GetLogicalDrives() };
    let mut out: Vec<Disk> = (0..26u8)
        .filter(|i| mask & (1 << i) != 0)
        .filter_map(|i| measure(&format!("{}:", (b'A' + i) as char)))
        .collect();
    out.sort_by_key(|d| (!d.system, d.letter.clone()));
    out
}

#[cfg(not(windows))]
pub fn list() -> Vec<Disk> {
    vec![]
}

pub fn info() -> Disk {
    #[cfg(windows)]
    if let Some(d) = measure(&system_drive()) {
        return d;
    }
    Disk { letter: system_drive(), kind: "fixed".into(), system: true, ..Default::default() }
}

/// Katta fayllar va dublikatlar qidiriladigan boshqa disklar (tizim diskidan tashqari,
/// tarmoq va CD disklarsiz). Tizim diskida faqat foydalanuvchi papkasi ko'riladi.
pub fn extra_roots() -> Vec<PathBuf> {
    list()
        .into_iter()
        .filter(|d| !d.system && (d.kind == "fixed" || d.kind == "removable"))
        .map(|d| PathBuf::from(format!("{}\\", d.letter)))
        .collect()
}

/// Ilova administrator huquqlari bilan ishlayaptimi.
pub fn is_elevated() -> bool {
    #[cfg(windows)]
    unsafe {
        return windows_sys::Win32::UI::Shell::IsUserAnAdmin() != 0;
    }
    #[allow(unreachable_code)]
    false
}

/// Ilovani administrator sifatida qayta ochadi (UAC oynasi chiqadi).
/// Foydalanuvchi rozi bo'lsa Ok(()), rad etsa Err("cancelled").
pub fn relaunch_elevated() -> Result<(), String> {
    #[cfg(windows)]
    {
        use windows_sys::Win32::UI::Shell::{ShellExecuteExW, SHELLEXECUTEINFOW};
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        let verb = crate::util::wide("runas");
        let file = crate::util::wide(&exe.display().to_string());
        let params = crate::util::wide("--elevated");
        let mut info: SHELLEXECUTEINFOW = unsafe { std::mem::zeroed() };
        info.cbSize = std::mem::size_of::<SHELLEXECUTEINFOW>() as u32;
        info.lpVerb = verb.as_ptr();
        info.lpFile = file.as_ptr();
        info.lpParameters = params.as_ptr();
        info.nShow = 1; // SW_SHOWNORMAL
        if unsafe { ShellExecuteExW(&mut info) } == 0 {
            return Err("cancelled".into());
        }
        return Ok(());
    }
    #[allow(unreachable_code)]
    Err("unsupported".into())
}
