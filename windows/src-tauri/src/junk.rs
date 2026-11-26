//! Keraksiz fayllar toifalari: ilovalar keshi, vaqtinchalik fayllar, dasturchi keshlari,
//! o'rnatish fayllari, o'chirilgan ilovalar qoldig'i va Savat.

use crate::settings::l;
use crate::util::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Serialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct Item {
    pub id: String,
    pub name: String,
    pub detail: String,
    pub paths: Vec<String>,
    pub size: u64,
    /// Taxminan topilgan — tanlashdan oldin ko'rib chiqish kerak.
    pub review: bool,
    pub selected: bool,
    pub modified: u64,
}

const MB: u64 = 1024 * 1024;
const DAY: u64 = 86_400;

pub fn scan(category: &str, lang: &str) -> Vec<Item> {
    let mut items = match category {
        "appCaches" => app_caches(lang),
        "temp" => temp_files(lang),
        "devCaches" => dev_caches(lang),
        "installers" => installers(lang),
        "leftovers" => leftovers(lang),
        "recycle" => recycle_bin(lang),
        _ => vec![],
    };
    items.sort_by(|a, b| b.size.cmp(&a.size));
    items
}

// MARK: - Ilovalar keshi

const CACHE_DIRS: &[&str] = &[
    "cache", "code cache", "gpucache", "dawncache", "dawngraphitecache", "dawnwebgpucache",
    "graphitedawncache", "shadercache", "grshadercache", "cache2", "cacheddata", "cachestorage",
    "dxcache", "glcache", "inetcache", "d3dscache", "cacheddata",
];

/// Bu papkalarga kirilmaydi: tizim, Store ilovalari, Farrosh o'zi.
const SKIP_TOP: &[&str] = &["packages", "temp", "uz.farrosh.windows", "farrosh", "crashdumps"];

fn find_caches(dir: &Path, depth: u32, out: &mut Vec<PathBuf>) {
    if depth > 6 {
        return;
    }
    let Ok(rd) = fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let Ok(md) = e.metadata() else { continue };
        if !md.is_dir() || is_link(&md) {
            continue;
        }
        let name = e.file_name().to_string_lossy().to_lowercase();
        if CACHE_DIRS.contains(&name.as_str()) {
            out.push(e.path());
        } else if name != "user data" || depth < 3 {
            find_caches(&e.path(), depth + 1, out);
        }
    }
}

fn pretty_app(label: &str) -> String {
    match label.to_lowercase().as_str() {
        "google chrome" => "Google Chrome".into(),
        "microsoft edge" => "Microsoft Edge".into(),
        "bravesoftware brave-browser" => "Brave".into(),
        "mozilla firefox" => "Firefox".into(),
        "microsoft windows" => "Windows (Internet keshi)".into(),
        "code" => "Visual Studio Code".into(),
        "d3dscache" => "DirectX shader keshi".into(),
        "nvidia dxcache" | "nvidia glcache" => "NVIDIA shader keshi".into(),
        "amd dxcache" => "AMD shader keshi".into(),
        _ => label.to_string(),
    }
}

fn app_caches(lang: &str) -> Vec<Item> {
    let mut groups: BTreeMap<String, (Vec<PathBuf>, u64)> = BTreeMap::new();
    for root in [local(), roaming()] {
        let Ok(rd) = fs::read_dir(&root) else { continue };
        for top in rd.flatten() {
            let Ok(md) = top.metadata() else { continue };
            if !md.is_dir() || is_link(&md) {
                continue;
            }
            let tname = top.file_name().to_string_lossy().to_string();
            let tl = tname.to_lowercase();
            if SKIP_TOP.contains(&tl.as_str()) {
                continue;
            }
            let mut found = vec![];
            if CACHE_DIRS.contains(&tl.as_str()) {
                found.push(top.path());
            } else {
                find_caches(&top.path(), 0, &mut found);
            }
            for f in found {
                let rel: Vec<String> = f
                    .strip_prefix(&root)
                    .map(|r| r.components().map(|c| c.as_os_str().to_string_lossy().to_string()).collect())
                    .unwrap_or_default();
                let label = if rel.len() > 2 && !CACHE_DIRS.contains(&rel[1].to_lowercase().as_str()) {
                    format!("{} {}", rel[0], rel[1])
                } else {
                    rel.first().cloned().unwrap_or_else(|| tname.clone())
                };
                let size = dir_size(&f);
                let g = groups.entry(pretty_app(&label)).or_default();
                g.0.push(f);
                g.1 += size;
            }
        }
    }
    groups
        .into_iter()
        .filter(|(_, (_, size))| *size >= MB / 2)
        .map(|(name, (paths, size))| {
            let detail = if paths.len() > 1 {
                l(lang, &format!("{} ta kesh papkasi", paths.len()), &format!("{} cache folders", paths.len()), &format!("Папок кэша: {}", paths.len()))
            } else {
                pretty(&paths[0])
            };
            Item {
                id: format!("cache:{}", name),
                name,
                detail,
                paths: paths.iter().map(|p| p.display().to_string()).collect(),
                size,
                selected: true,
                ..Default::default()
            }
        })
        .collect()
}

// MARK: - Vaqtinchalik fayllar

/// Vaqtinchalik papkalarda oxirgi bir kunda o'zgargan narsalarga tegilmaydi — ular hozir ishlatilayotgan bo'lishi mumkin.
pub fn temp_age(p: &Path) -> Option<u64> {
    let s = p.to_string_lossy().to_lowercase();
    if s.ends_with("\\temp") { Some(DAY) } else { None }
}

fn temp_files(lang: &str) -> Vec<Item> {
    let user_temp = std::env::temp_dir();
    let sources: Vec<(&str, String, String, Vec<PathBuf>)> = vec![
        (
            "temp-user",
            l(lang, "Vaqtinchalik fayllar (foydalanuvchi)", "Temporary files (user)", "Временные файлы (пользователь)"),
            l(lang, "Bir kundan eski fayllar", "Files older than a day", "Файлы старше суток"),
            vec![user_temp],
        ),
        (
            "temp-win",
            l(lang, "Windows vaqtinchalik fayllari", "Windows temporary files", "Временные файлы Windows"),
            l(lang, "Bir kundan eski fayllar", "Files older than a day", "Файлы старше суток"),
            vec![windows_dir().join("Temp")],
        ),
        (
            "dumps",
            l(lang, "Ilovalar nosozlik dumplari", "App crash dumps", "Дампы сбоев приложений"),
            l(lang, "Ilova to'satdan yopilganda yoziladi", "Written when an app crashes", "Создаются при сбое приложения"),
            vec![local().join("CrashDumps")],
        ),
        (
            "wer",
            l(lang, "Windows xato hisobotlari", "Windows error reports", "Отчёты об ошибках Windows"),
            l(lang, "Microsoft'ga yuborilgan yoki navbatdagi hisobotlar", "Reports sent or queued for Microsoft", "Отправленные или ожидающие отчёты для Microsoft"),
            vec![local().join("Microsoft\\Windows\\WER"), program_data().join("Microsoft\\Windows\\WER")],
        ),
        (
            "thumbs",
            l(lang, "Eskiz rasmlar keshi", "Thumbnail cache", "Кэш эскизов"),
            l(lang, "Explorer qayta yaratadi", "Explorer recreates it", "Explorer создаст его заново"),
            vec![],
        ),
    ];
    let mut out = vec![];
    for (id, name, detail, paths) in sources {
        let (size, paths) = if id == "thumbs" {
            // thumbcache_*.db fayllari — bittalab.
            let dir = local().join("Microsoft\\Windows\\Explorer");
            let files: Vec<PathBuf> = fs::read_dir(&dir)
                .map(|rd| {
                    rd.flatten()
                        .map(|e| e.path())
                        .filter(|p| name_of(p).to_lowercase().starts_with("thumbcache_"))
                        .collect()
                })
                .unwrap_or_default();
            (files.iter().map(|p| size_of(p)).sum::<u64>(), files)
        } else {
            let paths: Vec<PathBuf> = paths.into_iter().filter(|p| p.is_dir()).collect();
            (paths.iter().map(|p| children_size(p, temp_age(p))).sum::<u64>(), paths)
        };
        if size >= MB / 2 && !paths.is_empty() {
            out.push(Item {
                id: id.into(),
                name,
                detail,
                paths: paths.iter().map(|p| p.display().to_string()).collect(),
                size,
                selected: true,
                ..Default::default()
            });
        }
    }
    out
}

// MARK: - Dasturchi keshlari

fn dev_caches(lang: &str) -> Vec<Item> {
    let (h, lo, r) = (home(), local(), roaming());
    // (nom, yo'l, avtomatik tanlansinmi)
    let mut list: Vec<(String, PathBuf, bool)> = vec![
        ("npm".into(), lo.join("npm-cache"), true),
        ("Yarn".into(), lo.join("Yarn\\Cache"), true),
        ("pnpm".into(), lo.join("pnpm-cache"), true),
        ("pnpm store".into(), lo.join("pnpm\\store"), false),
        ("pip".into(), lo.join("pip\\cache"), true),
        ("uv".into(), lo.join("uv\\cache"), true),
        ("Bun".into(), h.join(".bun\\install\\cache"), true),
        ("node-gyp".into(), lo.join("node-gyp\\Cache"), true),
        ("Electron".into(), lo.join("electron\\Cache"), true),
        ("electron-builder".into(), lo.join("electron-builder\\Cache"), true),
        ("Gradle".into(), h.join(".gradle\\caches"), true),
        ("Maven".into(), h.join(".m2\\repository"), false),
        (l(lang, "NuGet HTTP keshi", "NuGet HTTP cache", "HTTP-кэш NuGet"), lo.join("NuGet\\v3-cache"), true),
        (l(lang, "NuGet paketlari", "NuGet packages", "Пакеты NuGet"), h.join(".nuget\\packages"), false),
        ("Cargo".into(), h.join(".cargo\\registry\\cache"), true),
        (l(lang, "Go yig'ish keshi", "Go build cache", "Кэш сборки Go"), lo.join("go-build"), true),
        ("Composer".into(), lo.join("Composer"), true),
        (l(lang, "VS Code kengaytma o'rnatuvchilari", "VS Code extension installers", "Установщики расширений VS Code"), r.join("Code\\CachedExtensionVSIXs"), true),
        (l(lang, "Playwright brauzerlari", "Playwright browsers", "Браузеры Playwright"), lo.join("ms-playwright"), false),
    ];
    // JetBrains IDE keshlari: %LOCALAPPDATA%\JetBrains\<IDE>\caches
    if let Ok(rd) = fs::read_dir(lo.join("JetBrains")) {
        for e in rd.flatten() {
            let p = e.path().join("caches");
            if p.is_dir() {
                list.push((format!("JetBrains {}", name_of(&e.path())), p, true));
            }
        }
    }
    list.into_iter()
        .filter(|(_, p, _)| p.is_dir())
        .filter_map(|(name, p, auto)| {
            let size = dir_size(&p);
            (size >= MB).then(|| Item {
                id: format!("dev:{}", name),
                name,
                detail: pretty(&p),
                paths: vec![p.display().to_string()],
                size,
                review: !auto,
                selected: auto,
                ..Default::default()
            })
        })
        .collect()
}

// MARK: - O'rnatish fayllari

const INSTALLER_EXT: &[&str] = &["exe", "msi", "msix", "msixbundle", "appx", "appxbundle", "iso"];

fn installers(lang: &str) -> Vec<Item> {
    let me = std::env::current_exe().ok();
    let roots: Vec<PathBuf> = [dirs::download_dir(), dirs::desktop_dir(), dirs::document_dir()].into_iter().flatten().collect();
    let mut out = vec![];
    let now = now();
    for root in roots {
        let mut stack = vec![(root.clone(), 0u32)];
        while let Some((dir, depth)) = stack.pop() {
            let Ok(rd) = fs::read_dir(&dir) else { continue };
            for e in rd.flatten() {
                let Ok(md) = e.metadata() else { continue };
                let p = e.path();
                if is_link(&md) {
                    continue;
                }
                if md.is_dir() {
                    if depth < 1 {
                        stack.push((p, depth + 1));
                    }
                    continue;
                }
                let ext = p.extension().map(|x| x.to_string_lossy().to_lowercase()).unwrap_or_default();
                if !INSTALLER_EXT.contains(&ext.as_str()) || is_cloud_only(&md) || Some(&p) == me.as_ref() {
                    continue;
                }
                let modified = mtime(&md);
                let days = now.saturating_sub(modified) / DAY;
                let age = l(lang, &format!("{} kun oldin", days), &format!("{} days ago", days), &format!("{} дн. назад", days));
                out.push(Item {
                    id: format!("inst:{}", p.display()),
                    name: name_of(&p),
                    detail: format!("{} · {}", pretty(p.parent().unwrap_or(&root)), age),
                    paths: vec![p.display().to_string()],
                    size: md.len(),
                    selected: days >= 14,
                    modified,
                    ..Default::default()
                });
            }
        }
    }
    out
}

// MARK: - O'chirilgan ilovalar qoldig'i

/// Windows'ning o'zi va keng tarqalgan umumiy papkalar — ular hech qachon qoldiq deb ko'rsatilmaydi.
const SYSTEM_FOLDERS: &[&str] = &[
    "microsoft", "packages", "temp", "programs", "connecteddevicesplatform", "comms", "d3dscache",
    "crashdumps", "publishers", "virtualstore", "packagecache", "packagemanagement", "windows",
    "history", "nvidia", "nvidiacorporation", "intel", "amd", "realtek", "ssh", "usoshared",
    "usoprivate", "softwaredistribution", "identities", "microsoftedge", "peernetworking",
    "placeholdertilelogofolder", "tiledatalayer", "uzfarrosh", "uzfarroshwindows", "farrosh",
    "pip", "npm", "npmcache", "yarn", "pnpm", "pnpmcache", "nodegyp", "gobuild", "composer", "nuget",
    "electron", "electronbuilder", "msplaywright", "deno", "uv", "regid19910", "windowsdefender",
    "windowsnt", "microsofthelp", "desktop", "documents", "startmenu", "templates", "applicationdata",
    "dell", "hp", "lenovo", "asus", "acer", "oem", "chocolatey", "sun", "oracle", "java",
    "githubdesktop", "adobe", "apple", "applecomputer", "mozilla", "google", "jetbrains",
    "fontcache", "iconcache", "squirreltemp", "cef", "webview2", "ebwebview", "lowregistry",
    "microsoftcorporationii", "wsl", "docker", "dbg", "symbols", "intelligent", "gamebar",
];

pub struct Installed {
    pub tokens: Vec<String>,
}

impl Installed {
    pub fn load() -> Installed {
        let mut tokens = vec![];
        for (name, publisher) in crate::apps::names() {
            let n = norm(&name);
            if n.len() >= 3 {
                tokens.push(n);
            }
            let p = norm(&publisher);
            if p.len() >= 3 {
                tokens.push(p);
            }
            if let Some(first) = name.split_whitespace().next() {
                let f = norm(first);
                if f.len() >= 4 {
                    tokens.push(f);
                }
            }
        }
        tokens.sort();
        tokens.dedup();
        Installed { tokens }
    }

    pub fn matches(&self, folder: &str) -> bool {
        let f = norm(folder);
        if f.len() < 3 {
            return true;
        }
        self.tokens.iter().any(|t| t.contains(&f) || (t.len() >= 4 && f.contains(t.as_str())))
    }
}

fn leftovers(lang: &str) -> Vec<Item> {
    let installed = Installed::load();
    let now = now();
    let mut out = vec![];
    for root in [roaming(), local(), local_low(), program_data()] {
        let Ok(rd) = fs::read_dir(&root) else { continue };
        for e in rd.flatten() {
            let Ok(md) = e.metadata() else { continue };
            if !md.is_dir() || is_link(&md) {
                continue;
            }
            let name = e.file_name().to_string_lossy().to_string();
            let n = norm(&name);
            if name.starts_with('.') || name.starts_with('{') || SYSTEM_FOLDERS.iter().any(|s| n == *s || n.starts_with("regid"))
                || installed.matches(&name)
            {
                continue;
            }
            let p = e.path();
            let (size, newest) = dir_size_newest(&p);
            // Oxirgi 30 kunda ishlatilgan papka — ehtimol ilova hali bor (masalan, Store yoki ko'chma ilova).
            if size < MB || now.saturating_sub(newest) < 30 * DAY {
                continue;
            }
            let days = now.saturating_sub(newest) / DAY;
            out.push(Item {
                id: format!("left:{}", p.display()),
                name,
                detail: format!(
                    "{} · {}",
                    pretty(&p),
                    l(lang, &format!("{} kundan beri ishlatilmagan", days), &format!("unused for {} days", days), &format!("не использовалась {} дн.", days))
                ),
                paths: vec![p.display().to_string()],
                size,
                review: true,
                selected: false,
                modified: newest,
            });
        }
    }
    out
}

// MARK: - Savat

#[cfg(windows)]
pub fn recycle_query() -> (u64, u64) {
    use windows_sys::Win32::UI::Shell::{SHQueryRecycleBinW, SHQUERYRBINFO};
    unsafe {
        let mut info: SHQUERYRBINFO = std::mem::zeroed();
        info.cbSize = std::mem::size_of::<SHQUERYRBINFO>() as u32;
        if SHQueryRecycleBinW(std::ptr::null(), &mut info) == 0 {
            return (info.i64Size.max(0) as u64, info.i64NumItems.max(0) as u64);
        }
    }
    (0, 0)
}

#[cfg(not(windows))]
pub fn recycle_query() -> (u64, u64) {
    (0, 0)
}

#[cfg(windows)]
fn recycle_empty() -> bool {
    use windows_sys::Win32::UI::Shell::{SHEmptyRecycleBinW, SHERB_NOCONFIRMATION, SHERB_NOPROGRESSUI, SHERB_NOSOUND};
    unsafe { SHEmptyRecycleBinW(std::ptr::null_mut(), std::ptr::null(), SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND) == 0 }
}

#[cfg(not(windows))]
fn recycle_empty() -> bool {
    false
}

fn recycle_bin(lang: &str) -> Vec<Item> {
    let (size, count) = recycle_query();
    if count == 0 {
        return vec![];
    }
    vec![Item {
        id: "recycle".into(),
        name: l(lang, "Savatdagi fayllar", "Files in the Recycle Bin", "Файлы в Корзине"),
        detail: l(lang, &format!("{} ta element, barcha disklarda", count), &format!("{} items on all drives", count), &format!("Элементов: {}, на всех дисках", count)),
        paths: vec![],
        size,
        selected: true,
        ..Default::default()
    }]
}

// MARK: - Tozalash

#[derive(Deserialize)]
pub struct CleanRequest {
    pub category: String,
    pub paths: Vec<String>,
}

#[derive(Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct CleanResult {
    /// Darhol bo'shagan joy.
    pub freed: u64,
    /// Savatga ko'chirilgan (Savat bo'shatilgach bo'shaydi).
    pub recycled: u64,
    /// O'chmagan elementlar (band yoki himoyalangan).
    pub failed: u32,
}

pub fn clean(requests: Vec<CleanRequest>, permanent: bool) -> CleanResult {
    let mut r = CleanResult::default();
    for req in requests {
        match req.category.as_str() {
            "recycle" => {
                let (size, _) = recycle_query();
                if recycle_empty() {
                    r.freed += size;
                } else {
                    r.failed += 1;
                }
            }
            "appCaches" | "devCaches" | "temp" => {
                for p in req.paths.iter().map(PathBuf::from) {
                    let ok = if p.is_dir() { is_safe_to_empty(&p) } else { is_safe(&p) };
                    if !ok {
                        r.failed += 1;
                        continue;
                    }
                    let (freed, failed) = if p.is_dir() { purge_children(&p, temp_age(&p)) } else { purge(&p, false) };
                    r.freed += freed;
                    r.failed += failed;
                }
            }
            _ => {
                for p in req.paths.iter().map(PathBuf::from) {
                    match discard(&p, permanent) {
                        Ok(size) if permanent => r.freed += size,
                        Ok(size) => r.recycled += size,
                        Err(_) => r.failed += 1,
                    }
                }
            }
        }
    }
    r
}
