// Farrosh — Windows'ni keraksiz fayllardan tozalash ilovasi.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod apps;
mod disk;
mod files;
mod junk;
mod settings;
mod startup;
mod storage;
mod tray;
mod util;

use settings::{Settings, State};
use std::path::PathBuf;
use tauri::{AppHandle, Manager};
use tauri_plugin_autostart::ManagerExt;

/// Og'ir ishlar oynani qotirmasligi uchun alohida oqimda bajariladi.
async fn bg<T: Send + 'static>(f: impl FnOnce() -> T + Send + 'static) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(f).await.map_err(|e| e.to_string())
}

#[tauri::command]
async fn disk_info() -> Result<disk::Disk, String> {
    bg(disk::info).await
}

#[tauri::command]
async fn list_disks() -> Result<Vec<disk::Disk>, String> {
    bg(disk::list).await
}

#[tauri::command]
fn is_elevated() -> bool {
    disk::is_elevated()
}

/// Administrator sifatida qayta ochadi: UAC'ga rozilik berilsa, bu nusxa yopiladi.
#[tauri::command]
fn relaunch_admin(app: AppHandle) -> Result<(), String> {
    disk::relaunch_elevated()?;
    app.exit(0);
    Ok(())
}

#[tauri::command]
async fn storage_usage() -> Result<storage::Usage, String> {
    bg(storage::measure).await
}

#[tauri::command]
async fn scan_category(app: AppHandle, category: String) -> Result<Vec<junk::Item>, String> {
    let lang = app.state::<State>().get().lang;
    bg(move || junk::scan(&category, &lang)).await
}

#[tauri::command]
async fn clean(app: AppHandle, requests: Vec<junk::CleanRequest>) -> Result<junk::CleanResult, String> {
    let permanent = app.state::<State>().get().permanent;
    let r = bg(move || junk::clean(requests, permanent)).await?;
    app.state::<State>().update(|s| s.last_clean = util::now());
    Ok(r)
}

/// Katta fayllar, dublikatlar va qoldiqlar uchun: Savatga yoki butunlay (sozlamaga qarab).
#[tauri::command]
async fn discard_paths(app: AppHandle, paths: Vec<String>) -> Result<junk::CleanResult, String> {
    let permanent = app.state::<State>().get().permanent;
    bg(move || {
        let mut r = junk::CleanResult::default();
        for p in paths {
            match util::discard(&PathBuf::from(p), permanent) {
                Ok(size) if permanent => r.freed += size,
                Ok(size) => r.recycled += size,
                Err(_) => r.failed += 1,
            }
        }
        r
    })
    .await
}

#[tauri::command]
async fn list_apps() -> Result<Vec<apps::App>, String> {
    bg(|| apps::list(true)).await
}

#[tauri::command]
async fn app_exists(id: String) -> Result<bool, String> {
    bg(move || apps::exists(&id)).await
}

#[tauri::command]
async fn uninstall_app(id: String, quiet: bool) -> Result<bool, String> {
    bg(move || apps::uninstall(&id, quiet)).await?
}

#[tauri::command]
async fn app_leftovers(name: String, publisher: String, location: String) -> Result<Vec<junk::Item>, String> {
    bg(move || apps::leftovers(&name, &publisher, &location)).await
}

#[tauri::command]
async fn list_startup() -> Result<Vec<startup::Entry>, String> {
    bg(startup::list).await
}

#[tauri::command]
async fn set_startup(id: String, enabled: bool) -> Result<(), String> {
    bg(move || startup::set_enabled(&id, enabled)).await?
}

#[tauri::command]
async fn remove_startup(id: String) -> Result<(), String> {
    bg(move || startup::remove(&id)).await?
}

#[tauri::command]
async fn scan_large(min_mb: u64) -> Result<Vec<files::FileItem>, String> {
    bg(move || files::large(min_mb)).await
}

#[tauri::command]
async fn scan_duplicates() -> Result<Vec<files::Group>, String> {
    bg(files::duplicates).await
}

/// Explorer'da faylni belgilab ko'rsatadi.
#[tauri::command]
fn reveal(path: String) -> Result<(), String> {
    let mut cmd = std::process::Command::new("explorer");
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        if std::path::Path::new(&path).is_dir() {
            cmd.raw_arg(format!("\"{}\"", path));
        } else {
            cmd.raw_arg(format!("/select,\"{}\"", path));
        }
    }
    #[cfg(not(windows))]
    cmd.arg(&path);
    cmd.spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
fn open_url(url: String) -> Result<(), String> {
    if !url.starts_with("https://") {
        return Err("bad-url".into());
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const NO_WINDOW: u32 = 0x0800_0000;
        std::process::Command::new("rundll32").args(["url.dll,FileProtocolHandler", &url]).creation_flags(NO_WINDOW).spawn().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn get_settings(app: AppHandle) -> Settings {
    app.state::<State>().get()
}

#[tauri::command]
fn save_settings(app: AppHandle, settings: Settings) -> Settings {
    let lang_changed = app.state::<State>().get().lang != settings.lang;
    let s = app.state::<State>().update(|s| {
        let keep = (s.last_clean, s.last_low_warn, s.last_remind);
        *s = settings;
        (s.last_clean, s.last_low_warn, s.last_remind) = keep;
    });
    if lang_changed {
        tray::refresh(&app);
    }
    s
}

#[tauri::command]
fn get_autostart(app: AppHandle) -> bool {
    app.autolaunch().is_enabled().unwrap_or(false)
}

#[tauri::command]
fn set_autostart(app: AppHandle, enabled: bool) -> Result<bool, String> {
    let m = app.autolaunch();
    if enabled { m.enable() } else { m.disable() }.map_err(|e| e.to_string())?;
    Ok(m.is_enabled().unwrap_or(false))
}

#[tauri::command]
fn quick_clean(app: AppHandle) {
    tray::quick_clean(app);
}

fn main() {
    // Administrator sifatida qayta ochilganda eski nusxa yopilishini kutamiz,
    // aks holda single-instance yangi nusxani darhol yopib qo'yadi.
    if std::env::args().any(|a| a == "--elevated") {
        std::thread::sleep(std::time::Duration::from_millis(1500));
    }
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| tray::show_main(app)))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, Some(vec!["--hidden"])))
        .setup(|app| {
            let state = State::load(app.handle());
            app.manage(state);
            tray::build(app.handle())?;
            // Windows bilan birga ishga tushganda oyna ochilmaydi — faqat tray belgisi.
            if !std::env::args().any(|a| a == "--hidden") {
                tray::show_main(app.handle());
            }
            tray::start_background(app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if window.state::<State>().get().close_to_tray {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            disk_info,
            list_disks,
            is_elevated,
            relaunch_admin,
            storage_usage,
            scan_category,
            clean,
            discard_paths,
            list_apps,
            app_exists,
            uninstall_app,
            app_leftovers,
            list_startup,
            set_startup,
            remove_startup,
            scan_large,
            scan_duplicates,
            reveal,
            open_url,
            get_settings,
            save_settings,
            get_autostart,
            set_autostart,
            quick_clean
        ])
        .run(tauri::generate_context!())
        .expect("Farrosh ishga tushmadi");
}
