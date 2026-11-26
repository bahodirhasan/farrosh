//! Sozlamalar: %APPDATA%\uz.farrosh.windows\settings.json

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::{AppHandle, Manager};

#[derive(Serialize, Deserialize, Clone)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    /// uz | en | ru
    pub lang: String,
    /// system | light | dark
    pub appearance: String,
    /// true: o'rnatish fayllari, qoldiqlar va boshqalar Savatga emas, butunlay o'chadi.
    pub permanent: bool,
    /// Oyna yopilganda dastur tray'da (soat yonida) qoladi.
    pub close_to_tray: bool,
    /// Bo'sh joy shundan kam bo'lsa ogohlantiradi (GB, 0 — o'chiq).
    pub low_space_gb: u32,
    /// off | weekly | monthly
    pub reminder: String,
    pub large_min_mb: u64,
    /// Matn o'lchami, foizda (100–200): ko'rish qobiliyati past foydalanuvchilar uchun.
    pub text_scale: u32,
    /// Kuchaytirilgan kontrast: aniqroq chegaralar va to'qroq matn.
    pub high_contrast: bool,
    pub last_clean: u64,
    pub last_low_warn: u64,
    pub last_remind: u64,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            lang: "uz".into(),
            appearance: "system".into(),
            permanent: false,
            close_to_tray: true,
            low_space_gb: 10,
            reminder: "weekly".into(),
            large_min_mb: 100,
            text_scale: 100,
            high_contrast: false,
            last_clean: 0,
            last_low_warn: 0,
            last_remind: 0,
        }
    }
}

pub struct State {
    inner: Mutex<Settings>,
    path: PathBuf,
}

impl State {
    pub fn load(app: &AppHandle) -> State {
        let dir = app.path().app_config_dir().unwrap_or_else(|_| std::env::temp_dir().join("Farrosh"));
        let path = dir.join("settings.json");
        let mut s: Settings = std::fs::read_to_string(&path)
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default();
        if s.last_clean == 0 {
            s.last_clean = crate::util::now();
        }
        let st = State { inner: Mutex::new(s), path };
        st.save();
        st
    }

    pub fn get(&self) -> Settings {
        self.inner.lock().unwrap().clone()
    }

    pub fn update<F: FnOnce(&mut Settings)>(&self, f: F) -> Settings {
        let s = {
            let mut g = self.inner.lock().unwrap();
            f(&mut g);
            g.clone()
        };
        self.save();
        s
    }

    fn save(&self) {
        let s = self.inner.lock().unwrap().clone();
        if let Some(dir) = self.path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(t) = serde_json::to_string_pretty(&s) {
            let _ = std::fs::write(&self.path, t);
        }
    }
}

/// Matnni sozlamadagi tilda qaytaradi.
pub fn l(lang: &str, uz: &str, en: &str, ru: &str) -> String {
    match lang {
        "en" => en,
        "ru" => ru,
        _ => uz,
    }
    .to_string()
}
