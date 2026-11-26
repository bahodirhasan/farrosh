//! Katta fayllar va dublikatlar: foydalanuvchi papkasi (AppData'siz) va boshqa disklar bo'yicha.

use crate::util::*;
use serde::Serialize;
use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use xxhash_rust::xxh3::{xxh3_64, Xxh3};

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct FileItem {
    pub path: String,
    pub name: String,
    pub folder: String,
    pub size: u64,
    pub modified: u64,
    pub kind: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Group {
    pub size: u64,
    pub files: Vec<FileItem>,
}

const SKIP: &[&str] = &["appdata", "$recycle.bin", "node_modules", ".git", ".gradle", ".nuget", ".cargo", ".rustup", ".m2", ".vscode", "onedrive - personal"];
/// Boshqa disklarning ildizidagi tizim papkalari: ularga tegilmaydi.
const SKIP_ROOT: &[&str] = &["system volume information", "windows", "program files", "program files (x86)", "programdata", "recovery", "$windows.~bt", "$windows.~ws", "msocache", "config.msi"];

fn skip_dir(p: &Path) -> bool {
    let n = name_of(p).to_lowercase();
    if SKIP.contains(&n.as_str()) {
        return true;
    }
    // D:\Windows kabi: ota papka disk ildizi bo'lsa.
    p.parent().map_or(false, |par| par.parent().is_none()) && SKIP_ROOT.contains(&n.as_str())
}

/// Qidiriladigan joylar: foydalanuvchi papkasi + boshqa barcha lokal va olinadigan disklar.
fn roots() -> Vec<PathBuf> {
    let mut r = vec![home()];
    r.extend(crate::disk::extra_roots());
    r
}

fn kind(p: &Path) -> String {
    let ext = p.extension().map(|x| x.to_string_lossy().to_lowercase()).unwrap_or_default();
    match ext.as_str() {
        "mp4" | "mkv" | "mov" | "avi" | "wmv" | "webm" | "m4v" | "flv" | "mts" => "video",
        "mp3" | "wav" | "flac" | "aac" | "m4a" | "ogg" | "wma" | "aiff" => "audio",
        "jpg" | "jpeg" | "png" | "heic" | "psd" | "raw" | "cr2" | "nef" | "arw" | "dng" | "tif" | "tiff" | "gif" | "webp" => "image",
        "zip" | "rar" | "7z" | "tar" | "gz" | "bz2" | "xz" | "tgz" => "archive",
        "iso" | "img" | "vhd" | "vhdx" | "vmdk" | "vdi" | "qcow2" | "wim" => "disk",
        "exe" | "msi" | "msix" | "appx" => "installer",
        "pdf" | "doc" | "docx" | "ppt" | "pptx" | "xls" | "xlsx" | "indd" | "ai" => "document",
        _ => "other",
    }
    .into()
}

fn item(p: &Path, md: &std::fs::Metadata) -> FileItem {
    FileItem {
        path: p.display().to_string(),
        name: name_of(p),
        folder: p.parent().map(pretty).unwrap_or_default(),
        size: md.len(),
        modified: mtime(md),
        kind: kind(p),
    }
}

pub fn large(min_mb: u64) -> Vec<FileItem> {
    let min = min_mb.max(1) * 1024 * 1024;
    let mut out = vec![];
    for root in roots() {
        walk(&root, &skip_dir, &mut |p, md| {
            if md.len() >= min && !is_cloud_only(md) {
                out.push(item(p, md));
            }
        });
    }
    out.sort_by(|a, b| b.size.cmp(&a.size));
    out.truncate(400);
    out
}

fn partial_hash(p: &Path, size: u64) -> Option<u64> {
    let mut f = File::open(p).ok()?;
    let mut buf = vec![0u8; 64 * 1024];
    let n = f.read(&mut buf).ok()?;
    let mut h = Xxh3::new();
    h.update(&buf[..n]);
    if size > 128 * 1024 {
        f.seek(SeekFrom::End(-(64 * 1024))).ok()?;
        let n = f.read(&mut buf).ok()?;
        h.update(&buf[..n]);
    }
    Some(h.digest())
}

fn full_hash(p: &Path) -> Option<u64> {
    let mut f = File::open(p).ok()?;
    let mut h = Xxh3::new();
    let mut buf = vec![0u8; 1024 * 1024];
    loop {
        let n = f.read(&mut buf).ok()?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }
    Some(h.digest())
}

pub fn duplicates() -> Vec<Group> {
    let min = 1024 * 1024u64;
    let mut by_size: HashMap<u64, Vec<(PathBuf, std::fs::Metadata)>> = HashMap::new();
    for root in roots() {
        walk(&root, &skip_dir, &mut |p, md| {
            if md.len() >= min && !is_cloud_only(md) {
                by_size.entry(md.len()).or_default().push((p.to_path_buf(), md.clone()));
            }
        });
    }
    let mut groups = vec![];
    for (size, files) in by_size.into_iter().filter(|(_, v)| v.len() > 1) {
        let mut by_partial: HashMap<u64, Vec<(PathBuf, std::fs::Metadata)>> = HashMap::new();
        for (p, md) in files {
            if let Some(h) = partial_hash(&p, size) {
                by_partial.entry(h).or_default().push((p, md));
            }
        }
        for (_, cands) in by_partial.into_iter().filter(|(_, v)| v.len() > 1) {
            let mut by_full: HashMap<u64, Vec<(PathBuf, std::fs::Metadata)>> = HashMap::new();
            for (p, md) in cands {
                if let Some(h) = full_hash(&p) {
                    by_full.entry(h ^ xxh3_64(&size.to_le_bytes())).or_default().push((p, md));
                }
            }
            for (_, same) in by_full.into_iter().filter(|(_, v)| v.len() > 1) {
                let mut files: Vec<FileItem> = same.iter().map(|(p, md)| item(p, md)).collect();
                // Eng eski nusxa birinchi — u "asl" deb qoldiriladi.
                files.sort_by_key(|f| (f.modified, f.path.len()));
                groups.push(Group { size, files });
            }
        }
    }
    groups.sort_by(|a, b| (b.size * (b.files.len() as u64 - 1)).cmp(&(a.size * (a.files.len() as u64 - 1))));
    groups.truncate(300);
    groups
}
