//! Soat yonidagi (tray) belgi: bo'sh joy, tezkor tozalash; fon tekshiruvlari: joy kam qolsa ogohlantirish va eslatma.

use crate::settings::{l, State};
use crate::{disk, junk, util};
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, Wry};
use tauri_plugin_notification::NotificationExt;

const TRAY: &str = "main";

pub fn show_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
}

fn menu(app: &AppHandle) -> tauri::Result<Menu<Wry>> {
    let lang = app.state::<State>().get().lang;
    let open = MenuItem::with_id(app, "open", l(&lang, "Farrosh'ni ochish", "Open Farrosh", "Открыть Farrosh"), true, None::<&str>)?;
    let quick = MenuItem::with_id(
        app,
        "quick",
        l(&lang, "Tezkor tozalash (kesh va vaqtinchalik fayllar)", "Quick clean (caches and temp files)", "Быстрая очистка (кэш и временные файлы)"),
        true,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, "quit", l(&lang, "Farrosh'dan chiqish", "Quit Farrosh", "Выйти из Farrosh"), true, None::<&str>)?;
    Menu::with_items(app, &[&open, &quick, &PredefinedMenuItem::separator(app)?, &quit])
}

pub fn build(app: &AppHandle) -> tauri::Result<()> {
    let m = menu(app)?;
    let mut b = TrayIconBuilder::with_id(TRAY)
        .tooltip("Farrosh")
        .menu(&m)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, ev| match ev.id().as_ref() {
            "open" => show_main(app),
            "quick" => quick_clean(app.clone()),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, ev| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = ev {
                show_main(tray.app_handle());
            }
        });
    if let Some(icon) = app.default_window_icon() {
        b = b.icon(icon.clone());
    }
    b.build(app)?;
    Ok(())
}

/// Til o'zgarganda menyu matnlarini yangilaydi.
pub fn refresh(app: &AppHandle) {
    if let (Some(tray), Ok(m)) = (app.tray_by_id(TRAY), menu(app)) {
        let _ = tray.set_menu(Some(m));
    }
    update_tooltip(app);
}

fn update_tooltip(app: &AppHandle) -> disk::Disk {
    let d = disk::info();
    let lang = app.state::<State>().get().lang;
    if let Some(tray) = app.tray_by_id(TRAY) {
        let free = util::fmt_bytes(d.free);
        let _ = tray.set_tooltip(Some(l(&lang, &format!("Farrosh — {} bo'sh", free), &format!("Farrosh — {} free", free), &format!("Farrosh — свободно {}", free))));
    }
    d
}

fn notify(app: &AppHandle, title: &str, body: &str) {
    let _ = app.notification().builder().title(title).body(body).show();
}

/// Kesh, vaqtinchalik fayllar va dasturchi keshlarini (avtomatik tanlanganlarini) tozalaydi.
pub fn quick_clean(app: AppHandle) {
    std::thread::spawn(move || {
        let lang = app.state::<State>().get().lang;
        let mut reqs = vec![];
        for cat in ["appCaches", "temp", "devCaches"] {
            let paths: Vec<String> = junk::scan(cat, &lang).into_iter().filter(|i| i.selected).flat_map(|i| i.paths).collect();
            reqs.push(junk::CleanRequest { category: cat.into(), paths });
        }
        let r = junk::clean(reqs, false);
        app.state::<State>().update(|s| s.last_clean = util::now());
        let freed = util::fmt_bytes(r.freed);
        notify(
            &app,
            &l(&lang, &format!("{} bo'shatildi", freed), &format!("{} freed", freed), &format!("Освобождено {}", freed)),
            &l(&lang, "Kesh va vaqtinchalik fayllar tozalandi.", "Caches and temporary files were cleaned.", "Кэш и временные файлы очищены."),
        );
        let _ = app.emit("cleaned", r.freed);
        update_tooltip(&app);
    });
}

/// Har 5 daqiqada: tray matni, joy kam qolsa ogohlantirish (kuniga ko'pi bilan bir marta), tozalash eslatmasi.
pub fn start_background(app: AppHandle) {
    std::thread::spawn(move || loop {
        let d = update_tooltip(&app);
        let st = app.state::<State>();
        let s = st.get();
        let now = util::now();
        let free_gb = d.free as f64 / 1024f64.powi(3);
        if s.low_space_gb > 0 && d.total > 0 && free_gb < s.low_space_gb as f64 && now.saturating_sub(s.last_low_warn) > 86_400 {
            st.update(|x| x.last_low_warn = now);
            let free = util::fmt_bytes(d.free);
            notify(
                &app,
                &l(&s.lang, &format!("{} diskida joy kam: {} qoldi", d.letter, free), &format!("Low disk space on {}: {} left", d.letter, free), &format!("Мало места на диске {}: осталось {}", d.letter, free)),
                &l(&s.lang, "Farrosh'ni ochib, keraksiz fayllarni tozalang.", "Open Farrosh to clean up junk files.", "Откройте Farrosh, чтобы удалить ненужные файлы."),
            );
        }
        let period = match s.reminder.as_str() {
            "weekly" => Some(7 * 86_400),
            "monthly" => Some(30 * 86_400),
            _ => None,
        };
        if let Some(p) = period {
            if now.saturating_sub(s.last_clean) > p && now.saturating_sub(s.last_remind) > p {
                st.update(|x| x.last_remind = now);
                notify(
                    &app,
                    &l(&s.lang, "Tozalash vaqti keldi", "Time for a cleanup", "Пора навести порядок"),
                    &l(&s.lang, "Kesh va vaqtinchalik fayllar yig'ilib qoldi. Farrosh'ni oching.", "Caches and temp files have piled up. Open Farrosh.", "Накопились кэш и временные файлы. Откройте Farrosh."),
                );
            }
        }
        std::thread::sleep(std::time::Duration::from_secs(300));
    });
}
