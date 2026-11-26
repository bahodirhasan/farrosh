//! Disk nima bilan band: hujjatlar, media, ilovalar ma'lumoti, dasturlar.

use crate::util::*;
use serde::Serialize;
use std::path::PathBuf;

#[derive(Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Usage {
    pub apps: u64,
    pub documents: u64,
    pub media: u64,
    pub app_data: u64,
}

fn sum(dirs: Vec<PathBuf>) -> u64 {
    std::thread::scope(|s| {
        let hs: Vec<_> = dirs.into_iter().filter(|d| d.is_dir()).map(|d| s.spawn(move || dir_size(&d))).collect();
        hs.into_iter().map(|h| h.join().unwrap_or(0)).sum()
    })
}

pub fn measure() -> Usage {
    let docs = vec![dirs::document_dir(), dirs::desktop_dir(), dirs::download_dir()].into_iter().flatten().collect();
    let media = vec![dirs::picture_dir(), dirs::video_dir(), dirs::audio_dir()].into_iter().flatten().collect();
    let data = vec![roaming(), local_low(), local()];
    let apps = vec![
        env_dir("ProgramFiles", "C:\\Program Files"),
        env_dir("ProgramFiles(x86)", "C:\\Program Files (x86)"),
        local().join("Programs"),
    ];
    std::thread::scope(|s| {
        let a = s.spawn(|| sum(apps));
        let d = s.spawn(|| sum(docs));
        let m = s.spawn(|| sum(media));
        let ad = s.spawn(|| sum(data));
        let apps = a.join().unwrap_or(0);
        let programs = dir_size(&local().join("Programs"));
        Usage {
            apps,
            documents: d.join().unwrap_or(0),
            media: m.join().unwrap_or(0),
            // Local\Programs ilovalarga qo'shilgan — ikki marta sanalmasin.
            app_data: ad.join().unwrap_or(0).saturating_sub(programs),
        }
    })
}
