'use strict';
// Faqat brauzerda (Tauri'siz) ochilganda: interfeysni ko'rish uchun namunaviy ma'lumot.
// Haqiqiy ilovada window.__TAURI__ bor va bu fayl hech narsa qilmaydi.
(function () {
  if (window.__TAURI__) return;
  const GB = 1024 ** 3, MB = 1024 ** 2;
  const now = Math.floor(Date.now() / 1000), day = 86400;
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  let settings = { lang: 'uz', appearance: 'system', permanent: false, closeToTray: true, lowSpaceGb: 10, reminder: 'weekly', largeMinMb: 100 };
  const it = (id, name, detail, size, extra = {}) => ({ id, name, detail, paths: [`C:\\Users\\Ali\\${id}`], size, review: false, selected: true, modified: 0, ...extra });
  const cats = {
    appCaches: [
      it('c1', 'Google Chrome', '4 ta kesh papkasi', 2.4 * GB), it('c2', 'Microsoft Edge', '3 ta kesh papkasi', 1.1 * GB),
      it('c3', 'Telegram Desktop', '~\\AppData\\Roaming\\Telegram Desktop\\tdata\\user_data\\cache', 820 * MB),
      it('c4', 'Visual Studio Code', '2 ta kesh papkasi', 410 * MB), it('c5', 'Discord', '~\\AppData\\Roaming\\discord\\Cache', 260 * MB),
      it('c6', 'DirectX shader keshi', '~\\AppData\\Local\\D3DSCache', 96 * MB),
    ],
    temp: [
      it('t1', 'Vaqtinchalik fayllar (foydalanuvchi)', "Bir kundan eski fayllar", 1.7 * GB), it('t2', 'Windows vaqtinchalik fayllari', "Bir kundan eski fayllar", 380 * MB),
      it('t3', 'Windows xato hisobotlari', "Microsoft'ga yuborilgan yoki navbatdagi hisobotlar", 120 * MB), it('t4', 'Eskiz rasmlar keshi', 'Explorer qayta yaratadi', 64 * MB),
    ],
    devCaches: [
      it('d1', 'npm', '~\\AppData\\Local\\npm-cache', 1.3 * GB), it('d2', 'Gradle', '~\\.gradle\\caches', 2.1 * GB),
      it('d3', 'NuGet paketlari', '~\\.nuget\\packages', 3.4 * GB, { review: true, selected: false }), it('d4', 'pip', '~\\AppData\\Local\\pip\\cache', 340 * MB),
    ],
    installers: [
      it('i1', 'Win11_24H2_Uzbek_x64.iso', '~\\Downloads · 41 kun oldin', 5.6 * GB), it('i2', 'OBS-Studio-30.2-Windows-Installer.exe', '~\\Downloads · 22 kun oldin', 140 * MB),
      it('i3', 'ChromeSetup.exe', '~\\Downloads · 3 kun oldin', 1.4 * MB, { selected: false }),
    ],
    leftovers: [
      it('l1', 'Spotify', "~\\AppData\\Roaming\\Spotify · 94 kundan beri ishlatilmagan", 610 * MB, { review: true, selected: false }),
      it('l2', 'Zoom', "~\\AppData\\Roaming\\Zoom · 210 kundan beri ishlatilmagan", 180 * MB, { review: true, selected: false }),
    ],
    recycle: [it('recycle', 'Savatdagi fayllar', '37 ta element, barcha disklarda', 2.9 * GB, { paths: [] })],
  };
  const apps = [
    ['Adobe Photoshop 2025', 'Adobe Inc.', '26.1', 4.8 * GB, '2025-09-14'], ['Microsoft Visual Studio Code', 'Microsoft Corporation', '1.96.2', 410 * MB, '2026-10-02'],
    ['Google Chrome', 'Google LLC', '131.0.6778', 620 * MB, '2026-11-01'], ['Telegram Desktop', 'Telegram FZ-LLC', '5.9', 190 * MB, '2026-08-20', 'user'],
    ['7-Zip 24.08 (x64)', 'Igor Pavlov', '24.08', 5.6 * MB, '2025-02-11'], ['OBS Studio', 'OBS Project', '30.2.3', 520 * MB, '2026-06-30'],
    ['Steam', 'Valve Corporation', '2.10.91', 1.2 * GB, '2024-12-01'], ['Notion', 'Notion Labs, Inc', '4.2.0', 380 * MB, '2026-07-12', 'user'],
    ['VLC media player', 'VideoLAN', '3.0.21', 180 * MB, '2025-05-05'], ['Zoom Workplace', 'Zoom Video Communications, Inc.', '6.2.0', 290 * MB, '2026-03-15', 'user'],
  ].map(([name, publisher, version, size, installed, scope], i) => ({ id: `HKLM64|app${i}`, name, publisher, version, size, installed, scope: scope || 'machine', location: '', hasQuiet: false }));
  const startup = [
    { id: 'hkcu-run|Telegram', name: 'Telegram Desktop', command: 'C:\\Users\\Ali\\AppData\\Roaming\\Telegram Desktop\\Telegram.exe -autostart', scope: 'user', kind: 'registry', enabled: true },
    { id: 'hkcu-run|Spotify', name: 'Spotify', command: 'C:\\Users\\Ali\\AppData\\Roaming\\Spotify\\Spotify.exe /minimized', scope: 'user', kind: 'registry', enabled: false },
    { id: 'hklm-run|SecurityHealth', name: 'SecurityHealth', command: '%windir%\\system32\\SecurityHealthSystray.exe', scope: 'machine', kind: 'registry', enabled: true },
    { id: 'user-folder|Notion.lnk', name: 'Notion', command: '~\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\Notion.lnk', scope: 'user', kind: 'folder', enabled: true },
  ];
  const f = (name, folder, size, kind, age) => ({ path: `C:\\Users\\Ali\\${folder}\\${name}`, name, folder: `~\\${folder}`, size, modified: now - age * day, kind });
  const handlers = {
    get_settings: () => settings,
    save_settings: ({ settings: s }) => (settings = s),
    get_autostart: () => false,
    set_autostart: ({ enabled }) => enabled,
    disk_info: () => ({ letter: 'C:', label: '', kind: 'fixed', system: true, total: 476 * GB, free: 38.4 * GB, used: 437.6 * GB }),
    list_disks: () => [
      { letter: 'C:', label: '', kind: 'fixed', system: true, total: 476 * GB, free: 38.4 * GB, used: 437.6 * GB },
      { letter: 'D:', label: "Ma'lumotlar", kind: 'fixed', system: false, total: 931 * GB, free: 412 * GB, used: 519 * GB },
      { letter: 'E:', label: 'FLESHKA', kind: 'removable', system: false, total: 58.6 * GB, free: 21.3 * GB, used: 37.3 * GB },
    ],
    is_elevated: () => false,
    relaunch_admin: async () => { await wait(300); throw 'cancelled'; },
    storage_usage: async () => { await wait(900); return { apps: 74 * GB, documents: 58 * GB, media: 96 * GB, appData: 41 * GB }; },
    scan_category: async ({ category }) => { await wait(300 + Math.random() * 900); return JSON.parse(JSON.stringify(cats[category] || [])); },
    clean: async ({ requests }) => { await wait(1600); let freed = 0, recycled = 0; requests.forEach((r) => { const list = cats[r.category]; const sz = list.filter((i) => r.paths.includes(i.paths[0]) || r.category === 'recycle').reduce((a, i) => a + i.size, 0); if (['installers', 'leftovers'].includes(r.category) && !settings.permanent) recycled += sz; else freed += sz; cats[r.category] = r.category === 'recycle' ? [] : list.filter((i) => !r.paths.includes(i.paths[0])); }); return { freed, recycled, failed: 3 }; },
    discard_paths: async ({ paths }) => { await wait(900); return { freed: 0, recycled: paths.length * 300 * MB, failed: 0 }; },
    list_apps: async () => { await wait(700); return apps; },
    app_exists: () => false,
    uninstall_app: async () => { await wait(2200); return true; },
    app_leftovers: async ({ name }) => [{ id: 'x', name: name.split(' ')[0], detail: `~\\AppData\\Roaming\\${name.split(' ')[0]}`, paths: ['C:\\x'], size: 84 * MB, review: false, selected: true, modified: 0 }],
    list_startup: async () => { await wait(300); return startup; },
    set_startup: () => null,
    remove_startup: () => null,
    scan_large: async () => { await wait(1500); return [f('Toy videosi.mp4', 'Videos', 7.8 * GB, 'video', 300), f('Win11_24H2_Uzbek_x64.iso', 'Downloads', 5.6 * GB, 'disk', 41), f('Ubuntu.vhdx', 'VMs', 12.4 * GB, 'disk', 120), f('Loyiha arxivi 2024.zip', 'Documents', 2.2 * GB, 'archive', 400), f('Podcast 12 xom.wav', 'Music', 1.1 * GB, 'audio', 80), f('Katalog.pdf', 'Desktop', 160 * MB, 'document', 12)].sort((a, b) => b.size - a.size); },
    scan_duplicates: async () => { await wait(1800); return [{ size: 1.4 * GB, files: [f('Maktab bitiruv.mp4', 'Videos', 1.4 * GB, 'video', 900), f('Maktab bitiruv (1).mp4', 'Downloads', 1.4 * GB, 'video', 30)] }, { size: 24 * MB, files: [f('IMG_2041.HEIC', 'Pictures\\iPhone', 24 * MB, 'image', 500), f('IMG_2041.HEIC', 'Desktop\\Rasmlar', 24 * MB, 'image', 60), f('IMG_2041 copy.HEIC', 'Downloads', 24 * MB, 'image', 10)] }]; },
    reveal: () => null,
    open_url: () => null,
    quick_clean: () => null,
  };
  window.mockInvoke = async (cmd, args = {}) => {
    const h = handlers[cmd];
    if (!h) throw new Error('mock: ' + cmd);
    return h(args);
  };
})();
