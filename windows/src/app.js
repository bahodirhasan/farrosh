'use strict';
// Farrosh for Windows — interfeys. Ma'lumot Rust tomonidan (Tauri buyruqlari) keladi.
// Brauzerda (Tauri'siz) ochilsa, mock.js dagi namunaviy ma'lumot ishlatiladi.

const TAURI = window.__TAURI__;
const invoke = TAURI ? (cmd, args) => TAURI.core.invoke(cmd, args) : window.mockInvoke;

// MARK: - Holat

const S = {
  settings: { lang: 'uz', appearance: 'system', permanent: false, closeToTray: true, lowSpaceGb: 10, reminder: 'weekly', largeMinMb: 100, textScale: 100, highContrast: false },
  autostart: false,
  route: 'overview',
  disk: null,
  disks: null,
  elevated: false,
  usage: null,
  cats: {},
  scanning: new Set(),
  scope: new Set(['appCaches', 'temp', 'devCaches', 'installers', 'recycle']),
  apps: null, appsLoading: false, appChecked: new Set(), appQuery: '', appSort: 'size',
  startup: null, startupLoading: false,
  large: null, largeLoading: false, largeKind: 'all',
  dupes: null, dupesLoading: false,
  busy: false,
};

const L = (uz, en, ru) => (S.settings.lang === 'en' ? en : S.settings.lang === 'ru' ? ru : uz);

// MARK: - Yordamchilar

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/** Explorer bilan bir xil: 1024 asosida. */
function fmt(b) {
  b = Number(b) || 0;
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0;
  while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
  if (i === 0) return `${b} B`;
  const n = b >= 100 ? b.toFixed(0) : b.toFixed(1);
  return `${S.settings.lang === 'en' ? n : n.replace('.', ',')} ${u[i]}`;
}

const UZ_MONTHS = ['yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun', 'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr'];
function fmtDate(sec) {
  if (!sec) return '';
  const d = new Date(sec * 1000);
  // Brauzerlarda o'zbekcha oy nomlari yo'q — o'zimiz yozamiz: "9-iyun, 2024".
  if (S.settings.lang === 'uz') return `${d.getDate()}-${UZ_MONTHS[d.getMonth()]}, ${d.getFullYear()}`;
  return d.toLocaleDateString(S.settings.lang === 'ru' ? 'ru-RU' : 'en-US', { year: 'numeric', month: 'short', day: 'numeric' });
}


let toastTimer;
function toast(msg, ms = 4200) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.add('show');
  announce(msg, true);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), ms);
}

/** Ekran o'qigichga (NVDA, Hikoyachi, JAWS) xabar: ko'rinmaydi, faqat o'qiladi. */
function announce(msg, urgent = false) {
  const el = $(urgent ? '#sr-alert' : '#sr-status');
  if (!el) return;
  el.textContent = '';
  setTimeout(() => { el.textContent = msg; }, 80);
}

/** Aylanuvchi belgi: ekran o'qigich uchun nomi bor. */
const spin = (cls = '') => `<span class="spinner ${cls}" role="img" aria-label="${esc(L('Yuklanmoqda', 'Loading', 'Загрузка'))}"></span>`;

function errText(e) {
  const s = String(e?.message || e || '');
  if (s === 'admin') return L(
    "Bu element barcha foydalanuvchilarga tegishli. Uni o'zgartirish uchun administrator ruxsati kerak.",
    'This item belongs to all users. Changing it needs administrator permission.',
    'Этот элемент общий для всех пользователей. Для изменения нужны права администратора.');
  if (s === 'cancelled') return L("Windows ruxsat oynasida bekor qilindi.", 'Cancelled in the Windows permission prompt.', 'Отменено в окне разрешений Windows.');
  return L(`Xatolik: ${s}`, `Error: ${s}`, `Ошибка: ${s}`);
}

// MARK: - Belgilar (ikonkalar)

const ICONS = {
  drive: '<rect x="3" y="13" width="18" height="7" rx="2"/><path d="M5 13l2.2-7.2A2 2 0 0 1 9.1 4.4h5.8a2 2 0 0 1 1.9 1.4L19 13"/><path d="M7 16.5h.01M10.5 16.5h.01"/>',
  grid: '<rect x="4" y="4" width="7" height="7" rx="1.6"/><rect x="13" y="4" width="7" height="7" rx="1.6"/><rect x="4" y="13" width="7" height="7" rx="1.6"/><rect x="13" y="13" width="7" height="7" rx="1.6"/>',
  power: '<path d="M12 3.5v8"/><path d="M6.6 6.8a7.5 7.5 0 1 0 10.8 0"/>',
  file: '<path d="M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8z"/><path d="M14 3.5V8h4.5"/>',
  copy: '<rect x="8.5" y="8.5" width="12" height="12" rx="2"/><path d="M15.5 8.5V5.5a2 2 0 0 0-2-2h-8a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h3"/>',
  layers: '<path d="M12 3.5l8.5 4.5-8.5 4.5L3.5 8z"/><path d="M3.5 12.5l8.5 4.5 8.5-4.5"/><path d="M3.5 16.5l8.5 4.5 8.5-4.5" opacity=".55"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  code: '<path d="M8.5 7.5L4 12l4.5 4.5"/><path d="M15.5 7.5L20 12l-4.5 4.5"/><path d="M13.5 5l-3 14"/>',
  package: '<path d="M20.5 8l-8.5-4.5L3.5 8v8l8.5 4.5 8.5-4.5z"/><path d="M3.5 8l8.5 4.5L20.5 8"/><path d="M12 12.5v8"/>',
  ghost: '<rect x="4" y="4" width="16" height="16" rx="3.5" stroke-dasharray="3 3"/><path d="M9 10h.01M15 10h.01"/><path d="M9.5 14.5c1.4 1 3.6 1 5 0"/>',
  trash: '<path d="M4 7h16"/><path d="M9.5 7V4.5h5V7"/><path d="M6 7l1 12.5a1.5 1.5 0 0 0 1.5 1.5h7a1.5 1.5 0 0 0 1.5-1.5L18 7"/><path d="M10 11v6M14 11v6"/>',
  sliders: '<path d="M4 6.5h9M17 6.5h3"/><circle cx="15" cy="6.5" r="2"/><path d="M4 12h3M11 12h9"/><circle cx="9" cy="12" r="2"/><path d="M4 17.5h11M19 17.5h1"/><circle cx="17" cy="17.5" r="2"/>',
  folder: '<path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>',
  refresh: '<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3"/><path d="M19.5 4.5V9H15"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  warn: '<path d="M12 4l9 15.5H3z"/><path d="M12 10v4.5M12 17.2h.01"/>',
  info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5M12 7.8h.01"/>',
  chevron: '<path d="M9.5 6l6 6-6 6"/>',
  sparkle: '<path d="M12 3.5l1.9 5 5 1.9-5 1.9-1.9 5-1.9-5-5-1.9 5-1.9z"/><path d="M18.5 15.5l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8z"/>',
  video: '<rect x="3.5" y="6" width="12.5" height="12" rx="2"/><path d="M16 10.5l4.5-2.5v8L16 13.5"/>',
  audio: '<path d="M9 17.5V6l10-2v11.5"/><circle cx="6.5" cy="17.5" r="2.5"/><circle cx="16.5" cy="15.5" r="2.5"/>',
  image: '<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="M20.5 16l-5-5-8 8.5"/>',
  archive: '<rect x="3.5" y="4" width="17" height="5" rx="1.5"/><path d="M5 9v9.5a1.5 1.5 0 0 0 1.5 1.5h11a1.5 1.5 0 0 0 1.5-1.5V9"/><path d="M10 13h4"/>',
  disk: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2.5"/>',
  doc: '<path d="M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8z"/><path d="M14 3.5V8h4.5"/><path d="M9 13h6M9 16.5h4"/>',
  x: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
  user: '<circle cx="12" cy="8.5" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>',
  users: '<circle cx="9" cy="9" r="3.2"/><path d="M3 19.5a6 6 0 0 1 12 0"/><path d="M15.5 6a3 3 0 0 1 0 6M17.5 14.2a6 6 0 0 1 3.5 5.3"/>',
  external: '<path d="M14 4.5h5.5V10"/><path d="M19.5 4.5L11 13"/><path d="M17 14v4.5a1.5 1.5 0 0 1-1.5 1.5h-10A1.5 1.5 0 0 1 4 18.5v-10A1.5 1.5 0 0 1 5.5 7H10"/>',
};
const icon = (name, cls = '') => `<svg class="i ${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ''}</svg>`;
const tile = (name, color) => `<span class="tile" style="background:${color}">${icon(name)}</span>`;

const LOGO = `<svg viewBox="0 0 1024 1024" aria-hidden="true"><defs><linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3B82F6"/><stop offset="1" stop-color="#1E3A8A"/></linearGradient></defs><rect x="40" y="40" width="944" height="944" rx="210" fill="url(#lg)"/><g transform="translate(512,512) scale(1.9) translate(-114,-153)" fill="#fff"><polygon points="0,100 224,6 228,108 0,146" stroke="#fff" stroke-width="12" stroke-linejoin="round"/><polygon points="0,170 174,154 174,228 0,230" stroke="#fff" stroke-width="12" stroke-linejoin="round"/><rect x="-6" y="248" width="22" height="58" rx="11"/><rect x="26" y="248" width="22" height="50" rx="11"/><rect x="58" y="248" width="22" height="42" rx="11"/><rect x="90" y="248" width="22" height="34" rx="11"/></g></svg>`;

// MARK: - Toifalar

const CATS = [
  {
    id: 'appCaches', icon: 'layers', color: '#3B82F6',
    title: () => L('Ilovalar keshi', 'App caches', 'Кэш приложений'),
    sub: () => L('Brauzerlar va ilovalar qayta yaratadigan vaqtinchalik nusxalar', 'Temporary copies that browsers and apps recreate', 'Временные копии, которые браузеры и приложения создают заново'),
    foot: () => L("Kesh — ilovalar tezroq ishlashi uchun saqlaydigan nusxalar. O'chirilsa, ilova kerakli qismini qayta yuklab oladi. Ochiq ilovalar ishlatayotgan fayllar o'tkazib yuboriladi — ularni yopib qo'ysangiz, ko'proq joy bo'shaydi.",
      'Caches are copies apps keep to work faster. If removed, an app simply downloads what it needs again. Files that open apps are using are skipped — quit them to free more space.',
      'Кэш — копии, которые приложения хранят для быстрой работы. После удаления приложение заново загрузит нужное. Файлы, занятые открытыми приложениями, пропускаются — закройте их, чтобы освободить больше места.'),
  },
  {
    id: 'temp', icon: 'clock', color: '#8B5CF6',
    title: () => L('Vaqtinchalik fayllar', 'Temporary files', 'Временные файлы'),
    sub: () => L('Temp papkalari, nosozlik dumplari, xato hisobotlari, eskizlar keshi', 'Temp folders, crash dumps, error reports, thumbnail cache', 'Папки Temp, дампы сбоев, отчёты об ошибках, кэш эскизов'),
    foot: () => L("Temp papkalarida oxirgi bir kunda o'zgargan fayllarga tegilmaydi — ular hozir ishlatilayotgan bo'lishi mumkin.",
      "Files changed in the last day are left alone in Temp folders — they may be in use right now.",
      'Файлы в папках Temp, изменённые за последние сутки, не трогаются — они могут использоваться прямо сейчас.'),
  },
  {
    id: 'devCaches', icon: 'code', color: '#14B8A6',
    title: () => L('Dasturchi keshlari', 'Developer caches', 'Кэши разработчика'),
    sub: () => L('npm, pip, Gradle, NuGet, Cargo, JetBrains va boshqalar', 'npm, pip, Gradle, NuGet, Cargo, JetBrains and more', 'npm, pip, Gradle, NuGet, Cargo, JetBrains и другие'),
    foot: () => L("Paket menejerlari keshlari. Keyingi o'rnatish yoki yig'ishda qayta yuklanadi. «Tekshiring» belgisi borlari (NuGet paketlari, Maven) avtomatik tanlanmaydi — ularni o'chirsangiz, loyihalar ochilganda ko'p narsa qayta yuklanadi.",
      'Package manager caches. They are downloaded again on the next install or build. Items marked “Review” (NuGet packages, Maven) are not selected automatically — removing them means a lot is re-downloaded when you open projects.',
      'Кэши пакетных менеджеров. Они загрузятся снова при следующей установке или сборке. Элементы с пометкой «Проверьте» (пакеты NuGet, Maven) не выбираются автоматически.'),
  },
  {
    id: 'installers', icon: 'package', color: '#E59E0B',
    title: () => L("O'rnatish fayllari", 'Installers', 'Установщики'),
    sub: () => L('Yuklab olingan .exe, .msi va .iso fayllar', 'Downloaded .exe, .msi and .iso files', 'Скачанные файлы .exe, .msi и .iso'),
    foot: () => L("Dastur o'rnatilgach, uning o'rnatish fayli kerak bo'lmaydi. Ikki haftadan eskilari avtomatik tanlanadi. Yuklanmalar, Ish stoli va Hujjatlar papkalari tekshiriladi.",
      'Once an app is installed, its installer is no longer needed. Files older than two weeks are selected automatically. Downloads, Desktop and Documents are checked.',
      'После установки программы её установщик больше не нужен. Файлы старше двух недель выбираются автоматически. Проверяются Загрузки, Рабочий стол и Документы.'),
  },
  {
    id: 'leftovers', icon: 'ghost', color: '#EC4899',
    title: () => L("O'chirilgan ilovalar qoldig'i", 'Leftovers of removed apps', 'Остатки удалённых приложений'),
    short: () => L('Ilova qoldiqlari', 'App leftovers', 'Остатки'),
    sub: () => L("Dasturi kompyuterda yo'q, 30 kundan beri ishlatilmagan AppData papkalari", 'AppData folders of apps that are gone, unused for 30 days', 'Папки AppData удалённых программ, не использовавшиеся 30 дней'),
    foot: () => L("Bu elementlar taxminan topilgan va avtomatik tanlanmaydi. Har birini ko'rib chiqing: Microsoft Store'dan o'rnatilgan yoki ko'chma (portable) dasturlarning papkalari ham shu yerda chiqishi mumkin.",
      'These were matched by guesswork and are never selected automatically. Look each one over: folders of Microsoft Store or portable apps can show up here too.',
      'Эти элементы найдены приблизительно и не выбираются автоматически. Просмотрите каждый: здесь могут оказаться папки приложений из Microsoft Store или портативных программ.'),
  },
  {
    id: 'recycle', icon: 'trash', color: '#64748B',
    title: () => L('Savat', 'Recycle Bin', 'Корзина'),
    sub: () => L("Savatdagi fayllar butunlay o'chadi", 'Files in the Recycle Bin are deleted for good', 'Файлы в Корзине удаляются навсегда'),
    foot: () => L("Savat bo'shatilgach fayllarni qaytarib bo'lmaydi.", "Once the Recycle Bin is emptied, files can't be recovered.", 'После очистки Корзины файлы нельзя восстановить.'),
  },
];
const CAT = Object.fromEntries(CATS.map((c) => [c.id, c]));
/** Bu toifalar sozlamaga qarab Savatga ko'chiriladi; qolganlari darhol o'chiriladi. */
const TO_BIN = new Set(['installers', 'leftovers']);

const catItems = (id) => S.cats[id]?.items || [];
const catTotal = (id) => catItems(id).reduce((a, i) => a + i.size, 0);
const catSelected = (id) => catItems(id).filter((i) => i.selected);
const catSelSize = (id) => catSelected(id).reduce((a, i) => a + i.size, 0);
const scopeSize = () => [...S.scope].reduce((a, id) => a + catSelSize(id), 0);

// MARK: - Ma'lumot yuklash

async function loadDisk() {
  try { S.disk = await invoke('disk_info'); } catch (e) { console.error(e); }
  try { S.disks = await invoke('list_disks'); } catch (e) { S.disks = S.disk ? [S.disk] : []; }
  renderSidebar();
  if (S.route === 'overview') renderMain();
}

async function loadUsage() {
  try { S.usage = await invoke('storage_usage'); } catch (e) { console.error(e); }
  if (S.route === 'overview') renderMain();
}

async function scanCat(id) {
  S.scanning.add(id);
  rerender();
  try {
    const items = await invoke('scan_category', { category: id });
    S.cats[id] = { items };
  } catch (e) {
    S.cats[id] = { items: [], error: String(e) };
  }
  S.scanning.delete(id);
  rerender();
  if (!S.scanning.size && S.route === 'overview') {
    const t = scopeSize();
    announce(t ? L(`Skanerlash tugadi. Tozalash mumkin: ${fmt(t)}.`, `Scan finished. Ready to clean: ${fmt(t)}.`, `Сканирование завершено. Можно очистить: ${fmt(t)}.`)
      : L('Skanerlash tugadi. Kompyuter toza.', 'Scan finished. Your PC is clean.', 'Сканирование завершено. Компьютер чист.'));
  }
}

function scanAll() {
  CATS.forEach((c) => scanCat(c.id));
  loadDisk();
  loadUsage();
}

async function loadApps() {
  if (S.appsLoading) return;
  S.appsLoading = true;
  rerender();
  try { S.apps = await invoke('list_apps'); } catch (e) { toast(errText(e)); S.apps = []; }
  S.appsLoading = false;
  S.appChecked = new Set([...S.appChecked].filter((id) => S.apps.some((a) => a.id === id)));
  rerender();
}

async function loadStartup() {
  S.startupLoading = true;
  rerender();
  try { S.startup = await invoke('list_startup'); } catch (e) { toast(errText(e)); S.startup = []; }
  S.startupLoading = false;
  rerender();
}

// MARK: - Chap panel

function navItem(route, label, ic, color, badge = '') {
  const cur = S.route === route ? ' aria-current="page"' : '';
  return `<button class="nav-item" data-route="${route}"${cur}>${tile(ic, color)}<span class="label">${esc(label)}</span>${badge}</button>`;
}

const diskKind = (d) => ({
  fixed: L('Lokal disk', 'Local disk', 'Локальный диск'),
  removable: L('Olinadigan disk', 'Removable drive', 'Съёмный диск'),
  network: L('Tarmoq diski', 'Network drive', 'Сетевой диск'),
  cdrom: 'CD/DVD',
  ram: 'RAM disk',
}[d.kind] || L('Disk', 'Drive', 'Диск'));
const diskName = (d) => d.label ? `${d.letter} · ${d.label}` : `${d.letter} · ${diskKind(d)}`;
const diskPct = (d) => (d.total ? Math.round((d.used / d.total) * 100) : 0);
const diskLow = (d) => d.system && S.settings.lowSpaceGb && d.free < S.settings.lowSpaceGb * 1024 ** 3;
/** Ekran o'qigich uchun to'liq jumla: "C: diski, Windows: 38 GB bo'sh, jami 476 GB, 92% band". */
const diskSpeech = (d) => L(`${d.letter} diski${d.label ? ', ' + d.label : ''}: ${fmt(d.free)} bo'sh, jami ${fmt(d.total)}, ${diskPct(d)}% band`,
  `Drive ${d.letter}${d.label ? ', ' + d.label : ''}: ${fmt(d.free)} free of ${fmt(d.total)}, ${diskPct(d)}% used`,
  `Диск ${d.letter}${d.label ? ', ' + d.label : ''}: свободно ${fmt(d.free)} из ${fmt(d.total)}, занято ${diskPct(d)}%`);

// Qayta chizilganda klaviatura fokusi o'sha elementda qolsin (ekran o'qigich va klaviatura uchun muhim).
const FOCUS_ATTRS = ['data-action', 'data-route', 'data-key', 'data-value', 'data-id', 'data-cat', 'data-i', 'data-path', 'data-g', 'data-f', 'data-kind', 'data-m'];
function focusKey(el) {
  if (!el || el === document.body) return null;
  if (el.id) return '#' + CSS.escape(el.id);
  const parts = FOCUS_ATTRS.filter((a) => el.hasAttribute(a)).map((a) => `[${a}="${CSS.escape(el.getAttribute(a))}"]`);
  return parts.length ? el.tagName.toLowerCase() + parts.join('') : null;
}
function keepFocus(container, render) {
  const a = document.activeElement;
  const key = a && container.contains(a) ? focusKey(a) : null;
  const caret = key && a.selectionStart != null ? a.selectionStart : null;
  render();
  if (!key) return;
  const el = container.querySelector(key);
  if (el) { el.focus({ preventScroll: true }); if (caret != null && el.setSelectionRange) el.setSelectionRange(caret, caret); }
}

function renderSidebar() {
  const catBadge = (id) => S.scanning.has(id) ? spin()
    : `<span class="badge">${catTotal(id) ? fmt(catTotal(id)) : ''}</span>`;
  const disks = S.disks && S.disks.length ? S.disks : S.disk ? [S.disk] : [];
  $('#sidebar').setAttribute('aria-label', L("Bo'limlar", 'Sections', 'Разделы'));
  $('.skip').textContent = L("Asosiy qismga o'tish", 'Skip to main content', 'Перейти к содержимому');
  const sb = $('#sidebar');
  keepFocus(sb, () => { sb.innerHTML = `
    <div class="brand">${LOGO}<div><b>Farrosh</b><small>${L('Windows uchun', 'for Windows', 'для Windows')}</small></div></div>
    ${navItem('overview', L("Umumiy ko'rinish", 'Overview', 'Обзор'), 'drive', '#2563EB')}
    <div class="nav-group"><div class="nav-title">${L('Ilovalar', 'Applications', 'Приложения')}</div>
      ${navItem('apps', L('Ilovalar', 'Applications', 'Приложения'), 'grid', '#0EA5E9', S.apps ? `<span class="badge">${S.apps.length}</span>` : '')}
      ${navItem('startup', L('Ishga tushish', 'Startup', 'Автозапуск'), 'power', '#16A34A')}
    </div>
    <div class="nav-group"><div class="nav-title">${L('Fayllar', 'Files', 'Файлы')}</div>
      ${navItem('large', L('Katta fayllar', 'Large files', 'Большие файлы'), 'file', '#F97316')}
      ${navItem('dupes', L('Dublikatlar', 'Duplicates', 'Дубликаты'), 'copy', '#A855F7')}
    </div>
    <div class="nav-group"><div class="nav-title">${L('Keraksiz fayllar', 'Junk files', 'Ненужные файлы')}</div>
      ${CATS.map((c) => navItem('cat:' + c.id, (c.short || c.title)(), c.icon, c.color, catBadge(c.id))).join('')}
    </div>
    <div class="side-foot">
      ${navItem('settings', L('Sozlamalar', 'Settings', 'Настройки'), 'sliders', '#64748B')}
      ${disks.map((d) => `<div class="mini-disk" role="group" aria-label="${esc(diskSpeech(d))}">
        <div aria-hidden="true">${L(`${d.letter} diski`, `Drive ${d.letter}`, `Диск ${d.letter}`)}</div>
        <div class="track" aria-hidden="true"><div class="fill${diskLow(d) ? ' low' : ''}" style="width:${diskPct(d)}%"></div></div>
        <div class="num" aria-hidden="true">${L(`${fmt(d.free)} bo'sh · jami ${fmt(d.total)}`, `${fmt(d.free)} free of ${fmt(d.total)}`, `Свободно ${fmt(d.free)} из ${fmt(d.total)}`)}</div>
      </div>`).join('')}
    </div>`; });
}

// MARK: - Sahifalar

function rerender() {
  renderSidebar();
  renderMain();
}

function renderMain() {
  const main = $('#main');
  const top = main.scrollTop;
  const r = S.route;
  let html;
  if (r === 'overview') html = pageOverview();
  else if (r === 'apps') html = pageApps();
  else if (r === 'startup') html = pageStartup();
  else if (r === 'large') html = pageLarge();
  else if (r === 'dupes') html = pageDupes();
  else if (r === 'settings') html = pageSettings();
  else if (r.startsWith('cat:')) html = pageCategory(r.slice(4));
  keepFocus(main, () => { main.innerHTML = `<div class="page">${html}</div>`; });
  main.scrollTop = top;
  syncIndeterminate();
}

function syncIndeterminate() {
  document.querySelectorAll('[data-indeterminate="true"]').forEach((el) => { el.indeterminate = true; });
}

function go(route) {
  S.route = route;
  rerender();
  $('#main').scrollTop = 0;
  // Yangi sahifa sarlavhasiga o'tamiz — ekran o'qigich uni darhol o'qiydi.
  $('#main h1')?.focus({ preventScroll: true });
  if (route === 'apps' && !S.apps) loadApps();
  if (route === 'startup' && !S.startup) loadStartup();
}

function pageHead(title, sub, ic, color, actions = '') {
  return `<header class="page-head">${ic ? tile(ic, color) : ''}<div><h1 tabindex="-1">${esc(title)}</h1>${sub ? `<p>${esc(sub)}</p>` : ''}</div><div class="spacer"></div>${actions}</header>`;
}

const rescanBtn = (action, label) => `<button class="btn" data-action="${action}" title="${esc(label)} (F5)">${icon('refresh')}${esc(label)}</button>`;

// Umumiy ko'rinish

const SEGMENTS = () => {
  const d = S.disk, u = S.usage;
  if (!d) return [];
  const junk = CATS.reduce((a, c) => a + catTotal(c.id), 0);
  const inData = ['appCaches', 'temp', 'devCaches'].reduce((a, id) => a + catTotal(id), 0);
  const segs = [];
  if (u) {
    segs.push({ label: L('Dasturlar', 'Apps', 'Программы'), size: u.apps, color: '#3B82F6' });
    segs.push({ label: L('Hujjatlar', 'Documents', 'Документы'), size: Math.max(0, u.documents - catTotal('installers')), color: '#8B5CF6' });
    segs.push({ label: L('Rasm, video, musiqa', 'Photos, video, music', 'Фото, видео, музыка'), size: u.media, color: '#EC4899' });
    segs.push({ label: L("Ilovalar ma'lumoti", 'App data', 'Данные приложений'), size: Math.max(0, u.appData - inData), color: '#14B8A6' });
  }
  segs.push({ label: L('Keraksiz fayllar', 'Junk', 'Ненужные файлы'), size: junk, color: '#F5B400' });
  const known = segs.reduce((a, s) => a + s.size, 0);
  segs.push({ label: L('Windows va boshqalar', 'Windows and other', 'Windows и прочее'), size: u ? Math.max(0, d.used - known) : 0, color: '#64748B', pending: !u });
  return segs;
};

function pageOverview() {
  const d = S.disk;
  const scanningAny = CATS.some((c) => S.scanning.has(c.id));
  const total = scopeSize();
  let hero = `<section class="card hero"><div class="empty">${spin('lg')}</div></section>`;
  if (d) {
    const pct = d.total ? Math.round((d.used / d.total) * 100) : 0;
    const low = S.settings.lowSpaceGb && d.free < S.settings.lowSpaceGb * 1024 ** 3;
    const segs = SEGMENTS();
    const bar = segs.filter((s) => s.size > 0).map((s) => `<div style="flex:${s.size};background:${s.color}" title="${esc(s.label)} · ${fmt(s.size)}"></div>`).join('')
      + `<div style="flex:${d.free};background:transparent" title="${esc(L("Bo'sh", 'Free', 'Свободно'))} · ${fmt(d.free)}"></div>`;
    const legend = segs.map((s) => `<div role="listitem"><i aria-hidden="true" style="background:${s.color}"></i><span>${esc(s.label)}</span><b>${s.pending ? spin() : fmt(s.size)}</b></div>`).join('')
      + `<div role="listitem"><i aria-hidden="true" style="background:var(--free);border:1px solid var(--line)"></i><span>${L("Bo'sh", 'Free', 'Свободно')}</span><b>${fmt(d.free)}</b></div>`;
    hero = `<section class="card hero">
      <div class="hero-top">
        <div class="hero-main">
          <span class="drive-chip">${icon('drive')}${esc(diskName(d))}</span>
          <div class="free-big">${fmt(d.free)}<span>${L("bo'sh", 'free', 'свободно')}</span></div>
          <div class="free-sub">${L(`${fmt(d.used)} band · ${pct}% · jami ${fmt(d.total)}`, `${fmt(d.used)} used · ${pct}% · ${fmt(d.total)} total`, `Занято ${fmt(d.used)} · ${pct}% · всего ${fmt(d.total)}`)}
            ${low ? `<span class="pill warn">${icon('warn')}${L('Joy kam', 'Low space', 'Мало места')}</span>` : ''}</div>
        </div>
        <div class="cleanable">
          <div class="t">${icon('sparkle')}${L('Tozalash mumkin', 'Ready to clean', 'Можно очистить')}</div>
          <div class="v">${scanningAny && !total ? spin() : fmt(total)}</div>
          <button class="btn" data-action="clean-scope" ${total && !S.busy ? '' : 'disabled'}>${L('Hozir tozalash', 'Clean now', 'Очистить сейчас')}</button>
        </div>
      </div>
      <div class="seg-bar" aria-hidden="true">${bar}</div>
      <div class="legend" role="list" aria-label="${esc(L('Disk taqsimoti', 'Disk usage', 'Распределение диска'))}">${legend}</div>
      <div class="note">${icon('info')}<span>${L("«Windows va boshqalar» — tizim fayllari, sahifa fayli (pagefile), qayta tiklash nuqtalari va Farrosh o'lchay olmaydigan himoyalangan papkalar.",
        '“Windows and other” covers system files, the page file, restore points and protected folders Farrosh can’t measure.',
        '«Windows и прочее» — системные файлы, файл подкачки, точки восстановления и защищённые папки, которые Farrosh не может измерить.')}</span></div>
    </section>`;
  }
  const rows = CATS.map((c) => {
    const scanning = S.scanning.has(c.id);
    const sel = catSelSize(c.id);
    const tot = catTotal(c.id);
    const status = scanning ? `${spin()}`
      : !tot ? `<span class="pill ok">${icon('check')}${L('Toza', 'Clean', 'Чисто')}</span>`
      : !sel ? `<span class="size" style="font-weight:400"><span class="muted">${L('Tanlanmagan', 'None selected', 'Не выбрано')}</span><div class="faint" style="font-size:12px">${fmt(tot)}</div></span>`
      : `<span class="size">${fmt(sel)}${sel !== tot ? `<div class="faint" style="font-weight:400;font-size:12px">${L(`${fmt(tot)} dan`, `of ${fmt(tot)}`, `из ${fmt(tot)}`)}</div>` : ''}</span>`;
    return `<li class="row hl">
      <input type="checkbox" class="check" data-action="scope" data-id="${c.id}" ${S.scope.has(c.id) ? 'checked' : ''} ${tot ? '' : 'disabled'} aria-label="${esc(c.title())}, ${esc(fmt(catTotal(c.id)))}">
      ${tile(c.icon, c.color)}
      <div class="body click" data-route="cat:${c.id}"><div class="title"><span>${esc(c.title())}</span></div><div class="sub">${esc(c.sub())}</div></div>
      ${status}
      <button class="icon-btn" data-route="cat:${c.id}" aria-label="${esc(L('Ochish', 'Open', 'Открыть'))}: ${esc(c.title())}" title="${esc(L("Ichini ko'rish", 'See details', 'Подробнее'))}">${icon('chevron')}</button>
    </li>`;
  }).join('');
  return `${pageHead(L("Umumiy ko'rinish", 'Overview', 'Обзор'), '', '', '', rescanBtn('rescan-all', L('Qayta skanerlash', 'Rescan', 'Пересканировать')))}
    ${hero}
    ${disksSection()}
    <h2 class="section-title">${L('Tozalanadigan fayllar', 'Files to clean', 'Файлы для очистки')}</h2>
    <section class="card"><ul class="list">${rows}</ul></section>
    <div class="note">${icon('info')}<span>${S.settings.permanent
      ? L("Kesh va vaqtinchalik fayllar butunlay o'chiriladi — ilovalar ularni kerak bo'lganda qayta yaratadi. O'rnatish fayllari va qoldiqlar ham butunlay o'chiriladi (Sozlamalarda o'zgartirish mumkin).", 'Caches and temp files are deleted for good — apps recreate them when needed. Installers and leftovers are deleted for good too (change this in Settings).', 'Кэш и временные файлы удаляются навсегда — приложения создадут их заново. Установщики и остатки тоже удаляются навсегда (можно изменить в Настройках).')
      : L("Kesh va vaqtinchalik fayllar butunlay o'chiriladi — ilovalar ularni kerak bo'lganda qayta yaratadi. O'rnatish fayllari va qoldiqlar Savatga ko'chiriladi (Sozlamalarda o'zgartirish mumkin).", 'Caches and temp files are deleted for good — apps recreate them when needed. Installers and leftovers go to the Recycle Bin (change this in Settings).', 'Кэш и временные файлы удаляются навсегда — приложения создадут их заново. Установщики и остатки перемещаются в Корзину (можно изменить в Настройках).')}</span></div>
    ${actionBar(
      L(`<b>${[...S.scope].filter((id) => catSelSize(id)).length} ta toifa</b> tanlangan`, `<b>${[...S.scope].filter((id) => catSelSize(id)).length} categories</b> selected`, `Выбрано категорий: <b>${[...S.scope].filter((id) => catSelSize(id)).length}</b>`),
      `<button class="btn primary lg" data-action="clean-scope" ${total && !S.busy ? '' : 'disabled'}>${cleanLabel([...S.scope], total)}</button>`)}`;
}

/** Kompyuterdagi barcha disklar (bittadan ko'p bo'lsa). */
function disksSection() {
  const disks = S.disks || [];
  if (disks.length < 2) return '';
  const rows = disks.map((d) => `<li class="row disk-row">
      ${tile('drive', d.system ? '#2563EB' : d.kind === 'removable' ? '#F97316' : d.kind === 'network' ? '#0EA5E9' : '#64748B')}
      <div class="body"><div class="title"><span>${esc(diskName(d))}</span>${d.system ? `<span class="pill">${L('Tizim', 'System', 'Системный')}</span>` : ''}</div>
        <div class="sub">${esc(diskKind(d))} · ${L(`${diskPct(d)}% band · jami ${fmt(d.total)}`, `${diskPct(d)}% used · ${fmt(d.total)} total`, `Занято ${diskPct(d)}% · всего ${fmt(d.total)}`)}</div>
        <div class="dtrack" aria-hidden="true"><div class="fill${diskLow(d) ? ' low' : ''}" style="width:${diskPct(d)}%"></div></div></div>
      <span class="size">${fmt(d.free)}<div class="faint" style="font-weight:400;font-size:12px">${L("bo'sh", 'free', 'свободно')}</div></span>
    </li>`).join('');
  return `<h2 class="section-title">${L('Disklar', 'Drives', 'Диски')} <span class="faint" style="font-weight:400">· ${disks.length}</span></h2>
    <section class="card"><ul class="list" aria-label="${esc(L('Disklar', 'Drives', 'Диски'))}">${rows}</ul></section>
    <div class="note">${icon('info')}<span>${L("Katta fayllar va dublikatlar barcha disklardan qidiriladi. Keraksiz fayllar (kesh, vaqtinchalik fayllar) Windows o'rnatilgan diskda bo'ladi.",
      'Large files and duplicates are searched on every drive. Junk (caches, temp files) lives on the drive Windows is installed on.',
      'Большие файлы и дубликаты ищутся на всех дисках. Мусор (кэш, временные файлы) находится на диске с Windows.')}</span></div>`;
}

function actionBar(info, buttons) {
  return `<div class="actionbar"><div class="info">${info}</div>${buttons}</div>`;
}

function cleanLabel(scope, size) {
  if (S.busy) return L('Tozalanmoqda…', 'Cleaning…', 'Очистка…');
  if (scope.some((id) => S.scanning.has(id))) return L('Skanerlanmoqda…', 'Scanning…', 'Сканирование…');
  if (!size) return L('Tozalash', 'Clean', 'Очистить');
  if (scope.length === 1 && scope[0] === 'recycle') return L(`Savatni bo'shatish · ${fmt(size)}`, `Empty Recycle Bin · ${fmt(size)}`, `Очистить Корзину · ${fmt(size)}`);
  if (scope.length === 1 && TO_BIN.has(scope[0]) && !S.settings.permanent) return L(`Savatga ko'chirish · ${fmt(size)}`, `Move to Recycle Bin · ${fmt(size)}`, `В Корзину · ${fmt(size)}`);
  return L(`Tozalash · ${fmt(size)}`, `Clean · ${fmt(size)}`, `Очистить · ${fmt(size)}`);
}

// Toifa sahifasi

function pageCategory(id) {
  const c = CAT[id];
  const items = catItems(id);
  const scanning = S.scanning.has(id);
  const sel = catSelected(id);
  const all = items.length && sel.length === items.length;
  const some = sel.length && !all;
  let body;
  if (scanning && !items.length) {
    body = `<section class="card"><div class="empty">${spin('lg')}<p style="margin-top:12px">${L('Skanerlanmoqda…', 'Scanning…', 'Сканирование…')}</p></div></section>`;
  } else if (!items.length) {
    body = `<section class="card"><div class="empty"><span class="big-icon" style="background:var(--ok-soft);color:var(--ok)">${icon('check')}</span><h3>${L('Bu yer toza', 'All clean here', 'Здесь чисто')}</h3><p>${L("Hozircha tozalaydigan narsa topilmadi.", 'Nothing to clean right now.', 'Сейчас нечего очищать.')}</p></div></section>`;
  } else {
    const rows = items.map((it, i) => `<li class="row hl">
      <input type="checkbox" class="check" data-action="item" data-cat="${id}" data-i="${i}" ${it.selected ? 'checked' : ''} aria-label="${esc(it.name)}, ${esc(fmt(it.size))}">
      <div class="body"><div class="title"><span>${esc(it.name)}</span>${it.review ? `<span class="pill warn">${icon('warn')}${L('Tekshiring', 'Review', 'Проверьте')}</span>` : ''}</div>
      <div class="sub" title="${esc(it.paths.join('\n'))}">${esc(it.detail)}</div></div>
      <span class="size">${fmt(it.size)}</span>
      ${it.paths.length ? `<button class="icon-btn" data-action="reveal" data-path="${esc(it.paths[0])}" aria-label="${esc(L("Explorer'da ko'rsatish", 'Show in Explorer', 'Показать в Проводнике'))}" title="${esc(L("Explorer'da ko'rsatish", 'Show in Explorer', 'Показать в Проводнике'))}">${icon('folder')}</button>` : '<span style="width:32px"></span>'}
    </li>`).join('');
    body = `<section class="card"><ul class="list">
      <li class="row head"><input type="checkbox" class="check" data-action="cat-all" data-cat="${id}" ${all ? 'checked' : ''} data-indeterminate="${some ? 'true' : 'false'}" aria-label="${esc(L('Hammasini tanlash', 'Select all', 'Выбрать все'))}">
        <div class="body muted">${L(`${items.length} ta topildi · ${sel.length} ta tanlangan`, `${items.length} found · ${sel.length} selected`, `Найдено: ${items.length} · выбрано: ${sel.length}`)}</div>
        <span class="size">${fmt(catTotal(id))}</span><span style="width:32px"></span></li>
      ${rows}</ul></section>`;
  }
  const size = catSelSize(id);
  return `${pageHead(c.title(), c.sub(), c.icon, c.color, rescanBtn('rescan-cat', L('Qayta skanerlash', 'Rescan', 'Пересканировать')))}
    ${body}
    <div class="note">${icon('info')}<span>${esc(c.foot())}</span></div>
    ${items.length ? actionBar(
      L(`Tanlangan: <b>${fmt(size)}</b>`, `Selected: <b>${fmt(size)}</b>`, `Выбрано: <b>${fmt(size)}</b>`),
      `<button class="btn ${id === 'recycle' || (TO_BIN.has(id) && S.settings.permanent) ? 'danger' : 'primary'} lg" data-action="clean-cat" data-cat="${id}" ${size && !S.busy ? '' : 'disabled'}>${cleanLabel([id], size)}</button>`) : ''}`;
}

// Ilovalar

const AV_COLORS = ['#2563EB', '#0EA5E9', '#14B8A6', '#16A34A', '#CA8A04', '#EA580C', '#DB2777', '#9333EA', '#4F46E5', '#64748B'];
function avatar(name) {
  let h = 0;
  for (const ch of name) h = (h * 31 + ch.codePointAt(0)) >>> 0;
  const letter = (name.match(/[\p{L}\p{N}]/u) || ['?'])[0].toUpperCase();
  return `<span class="avatar" style="background:${AV_COLORS[h % AV_COLORS.length]}">${esc(letter)}</span>`;
}

function visibleApps() {
  const q = S.appQuery.trim().toLowerCase();
  let list = (S.apps || []).filter((a) => !q || a.name.toLowerCase().includes(q) || a.publisher.toLowerCase().includes(q));
  if (S.appSort === 'name') list = [...list].sort((a, b) => a.name.localeCompare(b.name));
  else if (S.appSort === 'date') list = [...list].sort((a, b) => (b.installed || '').localeCompare(a.installed || ''));
  return list;
}

function pageApps() {
  const apps = S.apps;
  const sub = apps ? L(`${apps.length} ta dastur · jami ${fmt(apps.reduce((a, x) => a + x.size, 0))}`, `${apps.length} apps · ${fmt(apps.reduce((a, x) => a + x.size, 0))} total`, `Программ: ${apps.length} · всего ${fmt(apps.reduce((a, x) => a + x.size, 0))}`) : '';
  const head = pageHead(L('Ilovalar', 'Applications', 'Приложения'), sub, 'grid', '#0EA5E9', rescanBtn('reload-apps', L('Yangilash', 'Refresh', 'Обновить')));
  if (!apps) return `${head}<section class="card"><div class="empty">${spin('lg')}<p style="margin-top:12px">${L("Dasturlar ro'yxati o'qilmoqda…", 'Reading the list of apps…', 'Читаем список программ…')}</p></div></section>`;
  const list = visibleApps();
  const checkedVisible = list.filter((a) => S.appChecked.has(a.id)).length;
  const all = list.length && checkedVisible === list.length;
  const rows = list.map((a) => {
    const meta = [a.publisher, a.version, a.installed].filter(Boolean).join(' · ');
    return `<li class="row hl">
      <input type="checkbox" class="check" data-action="app-check" data-id="${esc(a.id)}" ${S.appChecked.has(a.id) ? 'checked' : ''} aria-label="${esc(L('Tanlash', 'Select', 'Выбрать'))}: ${esc(a.name)}">
      ${avatar(a.name)}
      <div class="body"><div class="title"><span>${esc(a.name)}</span>${a.scope === 'user' ? `<span class="pill gray" title="${esc(L("Faqat sizning hisobingiz uchun o'rnatilgan", 'Installed only for your account', 'Установлено только для вашей учётной записи'))}">${icon('user')}${L('Faqat siz', 'Just you', 'Только вы')}</span>` : ''}</div><div class="sub">${esc(meta)}</div></div>
      <span class="size">${a.size ? fmt(a.size) : '<span class="faint">—</span>'}</span>
      <button class="btn" data-action="uninstall-one" data-id="${esc(a.id)}">${L("O'chirish", 'Uninstall', 'Удалить')}</button>
    </li>`;
  }).join('');
  const checked = (S.apps || []).filter((a) => S.appChecked.has(a.id));
  const checkedSize = checked.reduce((s, a) => s + a.size, 0);
  return `${head}
    <div class="toolbar">
      <label class="search">${icon('search')}<input id="app-q" type="search" placeholder="${esc(L('Dastur yoki nashriyotchi', 'App or publisher', 'Программа или издатель'))}" value="${esc(S.appQuery)}" aria-label="${esc(L('Qidirish', 'Search', 'Поиск'))}"></label>
      <select id="app-sort" aria-label="${esc(L('Tartiblash', 'Sort', 'Сортировка'))}">
        <option value="size" ${S.appSort === 'size' ? 'selected' : ''}>${L("Hajmi bo'yicha", 'By size', 'По размеру')}</option>
        <option value="name" ${S.appSort === 'name' ? 'selected' : ''}>${L("Nomi bo'yicha", 'By name', 'По имени')}</option>
        <option value="date" ${S.appSort === 'date' ? 'selected' : ''}>${L("O'rnatilgan sanasi", 'By install date', 'По дате установки')}</option>
      </select>
    </div>
    <section class="card"><ul class="list">
      <li class="row head"><input type="checkbox" class="check" data-action="apps-all" ${all ? 'checked' : ''} data-indeterminate="${checkedVisible && !all ? 'true' : 'false'}" aria-label="${esc(L('Hammasini tanlash', 'Select all', 'Выбрать все'))}">
        <div class="body muted">${S.appQuery ? L(`Topilganlarning hammasini tanlash (${list.length} ta)`, `Select all matches (${list.length})`, `Выбрать все найденные (${list.length})`) : L(`Hammasini tanlash (${list.length} ta)`, `Select all (${list.length})`, `Выбрать все (${list.length})`)}</div></li>
      ${rows || `<li class="row"><div class="body muted">${L('Hech narsa topilmadi', 'Nothing found', 'Ничего не найдено')}</div></li>`}
    </ul></section>
    <div class="note">${icon('info')}<span>${L("Har bir dasturning o'z o'chirish dasturi ochiladi — Windows'ning «Dasturlarni o'chirish» bo'limidagi kabi. Microsoft Store ilovalari bu ro'yxatda yo'q.", 'Each app’s own uninstaller opens — the same as in Windows “Installed apps”. Microsoft Store apps are not listed here.', 'Открывается собственный деинсталлятор каждой программы — как в «Установленных приложениях» Windows. Приложения из Microsoft Store здесь не показаны.')}</span></div>
    ${checked.length ? actionBar(
      L(`<b>${checked.length} ta</b> tanlandi · ${fmt(checkedSize)}`, `<b>${checked.length}</b> selected · ${fmt(checkedSize)}`, `Выбрано: <b>${checked.length}</b> · ${fmt(checkedSize)}`),
      `<button class="btn" data-action="apps-none">${L('Tanlovni bekor qilish', 'Clear selection', 'Снять выбор')}</button><button class="btn danger lg" data-action="uninstall-checked">${L(`${checked.length} ta ilovani o'chirish`, checked.length === 1 ? 'Uninstall 1 app' : `Uninstall ${checked.length} apps`, `Удалить программы (${checked.length})`)}</button>`) : ''}`;
}

// Ishga tushish

function pageStartup() {
  const head = pageHead(L('Ishga tushish', 'Startup', 'Автозапуск'), L("Windows yonganda o'zi ochiladigan dasturlar", 'Apps that open when Windows starts', 'Программы, запускаемые вместе с Windows'), 'power', '#16A34A', rescanBtn('reload-startup', L('Yangilash', 'Refresh', 'Обновить')));
  if (!S.startup) return `${head}<section class="card"><div class="empty">${spin('lg')}</div></section>`;
  const on = S.startup.filter((e) => e.enabled).length;
  const rows = S.startup.map((e) => `<li class="row hl">
    ${tile('power', e.enabled ? '#16A34A' : '#94A3B8')}
    <div class="body"><div class="title"><span>${esc(e.name)}</span>
      <span class="pill gray">${icon(e.scope === 'user' ? 'user' : 'users')}${e.scope === 'user' ? L('Faqat siz', 'Just you', 'Только вы') : L('Barcha foydalanuvchilar', 'All users', 'Все пользователи')}</span></div>
      <div class="sub mono" title="${esc(e.command)}">${esc(e.command)}</div></div>
    <span class="muted" style="min-width:76px;text-align:right">${e.enabled ? L('Yoqilgan', 'On', 'Вкл.') : L("O'chirilgan", 'Off', 'Выкл.')}</span>
    <label class="switch"><input type="checkbox" data-action="startup-toggle" data-id="${esc(e.id)}" ${e.enabled ? 'checked' : ''} aria-label="${esc(e.name)}"></label>
    <button class="icon-btn" data-action="startup-remove" data-id="${esc(e.id)}" aria-label="${esc(L("Ro'yxatdan olib tashlash", 'Remove from list', 'Убрать из списка'))}: ${esc(e.name)}" title="${esc(L("Ro'yxatdan olib tashlash", 'Remove from list', 'Убрать из списка'))}">${icon('trash')}</button>
  </li>`).join('');
  return `${head}
    ${S.startup.length ? `<section class="card"><ul class="list">
      <li class="row head"><div class="body muted">${L(`${S.startup.length} ta dastur · ${on} tasi yoqilgan`, `${S.startup.length} apps · ${on} on`, `Программ: ${S.startup.length} · включено: ${on}`)}</div></li>${rows}</ul></section>`
      : `<section class="card"><div class="empty"><span class="big-icon" style="background:var(--ok-soft);color:var(--ok)">${icon('check')}</span><h3>${L("Ro'yxat bo'sh", 'Nothing here', 'Список пуст')}</h3><p>${L("Windows bilan birga hech qanday dastur ochilmaydi.", 'No apps open when Windows starts.', 'Вместе с Windows ничего не запускается.')}</p></div></section>`}
    <div class="note">${icon('info')}<span>${L("O'chirilgan dastur keyingi safar Windows yonganda ochilmaydi, lekin kompyuterda qoladi — istalgan payt qayta yoqish mumkin. Bu Vazifalar menejeridagi «Ishga tushish» bo'limi bilan bir xil ishlaydi.",
      'A turned-off app won’t open the next time Windows starts, but stays installed — turn it back on any time. This works the same way as the Startup tab in Task Manager.',
      'Выключенная программа не откроется при следующем запуске Windows, но останется установленной — её можно снова включить. Работает так же, как вкладка «Автозагрузка» в Диспетчере задач.')}</span></div>`;
}

// Katta fayllar

const KINDS = () => [
  ['all', L('Hammasi', 'All', 'Все')], ['video', L('Video', 'Video', 'Видео')], ['archive', L('Arxivlar', 'Archives', 'Архивы')],
  ['disk', L('Disk tasvirlari', 'Disk images', 'Образы дисков')], ['installer', L("O'rnatish fayllari", 'Installers', 'Установщики')],
  ['image', L('Rasmlar', 'Images', 'Изображения')], ['audio', L('Audio', 'Audio', 'Аудио')], ['document', L('Hujjatlar', 'Documents', 'Документы')], ['other', L('Boshqa', 'Other', 'Другое')],
];
const KIND_ICON = { video: ['video', '#EF4444'], audio: ['audio', '#EC4899'], image: ['image', '#10B981'], archive: ['archive', '#F59E0B'], disk: ['disk', '#6366F1'], installer: ['package', '#0EA5E9'], document: ['doc', '#3B82F6'], other: ['file', '#64748B'] };

function removeLabel(size) {
  return S.settings.permanent ? L(`Butunlay o'chirish · ${fmt(size)}`, `Delete permanently · ${fmt(size)}`, `Удалить навсегда · ${fmt(size)}`)
    : L(`Savatga ko'chirish · ${fmt(size)}`, `Move to Recycle Bin · ${fmt(size)}`, `В Корзину · ${fmt(size)}`);
}

function fileRow(f, action, attrs, checked, extra = '') {
  const [ic, col] = KIND_ICON[f.kind] || KIND_ICON.other;
  return `<li class="row hl">
    <input type="checkbox" class="check" data-action="${action}" ${attrs} ${checked ? 'checked' : ''} aria-label="${esc(f.name)}, ${esc(fmt(f.size))}, ${esc(f.folder)}">
    ${tile(ic, col)}
    <div class="body"><div class="title"><span>${esc(f.name)}</span>${extra}</div><div class="sub" title="${esc(f.path)}">${esc(f.folder)} · ${esc(fmtDate(f.modified))}</div></div>
    <span class="size">${fmt(f.size)}</span>
    <button class="icon-btn" data-action="reveal" data-path="${esc(f.path)}" aria-label="${esc(L("Explorer'da ko'rsatish", 'Show in Explorer', 'Показать в Проводнике'))}" title="${esc(L("Explorer'da ko'rsatish", 'Show in Explorer', 'Показать в Проводнике'))}">${icon('folder')}</button>
  </li>`;
}

function pageLarge() {
  const minSel = `<select id="large-min" aria-label="${esc(L('Eng kichik hajm', 'Minimum size', 'Минимальный размер'))}">${[50, 100, 500, 1024].map((m) => `<option value="${m}" ${S.settings.largeMinMb === m ? 'selected' : ''}>${L(`${m >= 1024 ? '1 GB' : m + ' MB'} dan katta`, `Larger than ${m >= 1024 ? '1 GB' : m + ' MB'}`, `Больше ${m >= 1024 ? '1 ГБ' : m + ' МБ'}`)}</option>`).join('')}</select>`;
  const head = pageHead(L('Katta fayllar', 'Large files', 'Большие файлы'), L("Eng ko'p joy egallayotgan fayllar", 'Files taking up the most space', 'Файлы, занимающие больше всего места'), 'file', '#F97316',
    `${minSel}<button class="btn primary" data-action="scan-large" ${S.largeLoading ? 'disabled' : ''}>${icon('search')}${S.large ? L('Qayta skanerlash', 'Rescan', 'Пересканировать') : L('Skanerlash', 'Scan', 'Сканировать')}</button>`);
  if (S.largeLoading) return `${head}<section class="card"><div class="empty">${spin('lg')}<p style="margin-top:12px">${L('Fayllar tekshirilmoqda… Bu bir necha daqiqa olishi mumkin.', 'Checking files… This can take a few minutes.', 'Проверяем файлы… Это может занять несколько минут.')}</p></div></section>`;
  if (!S.large) return `${head}<section class="card"><div class="empty"><span class="big-icon" style="background:var(--accent-soft);color:var(--accent)">${icon('search')}</span><h3>${L('Katta fayllarni topish', 'Find large files', 'Найти большие файлы')}</h3><p>${L("Foydalanuvchi papkangiz (AppData'siz) tekshiriladi. OneDrive'dagi faqat onlayn fayllar hisobga olinmaydi — ular diskda joy egallamaydi.", 'Your user folder (without AppData) is checked. Online-only OneDrive files are skipped — they take no space on disk.', 'Проверяется папка пользователя (без AppData). Файлы OneDrive «только в сети» не учитываются — они не занимают место.')}</p><button class="btn primary lg" data-action="scan-large">${L('Skanerlashni boshlash', 'Start scan', 'Начать сканирование')}</button></div></section>`;
  const kinds = new Set(S.large.map((f) => f.kind));
  const list = S.large.filter((f) => S.largeKind === 'all' || f.kind === S.largeKind);
  const chips = KINDS().filter(([k]) => k === 'all' || kinds.has(k)).map(([k, label]) => `<button class="chip" data-action="large-kind" data-kind="${k}" aria-pressed="${S.largeKind === k}">${esc(label)}</button>`).join('');
  const sel = S.large.filter((f) => f.selected);
  const selSize = sel.reduce((a, f) => a + f.size, 0);
  return `${head}
    <div class="toolbar"><div class="chips">${chips}</div></div>
    ${list.length ? `<section class="card"><ul class="list">${list.map((f) => fileRow(f, 'large-check', `data-path="${esc(f.path)}"`, f.selected)).join('')}</ul></section>`
      : `<section class="card"><div class="empty"><h3>${L('Topilmadi', 'Nothing found', 'Ничего не найдено')}</h3><p>${L('Bu chegaradan katta fayl yo\'q.', 'No files above this size.', 'Нет файлов больше этого размера.')}</p></div></section>`}
    ${sel.length ? actionBar(L(`<b>${sel.length} ta</b> tanlandi`, `<b>${sel.length}</b> selected`, `Выбрано: <b>${sel.length}</b>`),
      `<button class="btn ${S.settings.permanent ? 'danger' : 'primary'} lg" data-action="discard-large">${removeLabel(selSize)}</button>`) : ''}`;
}

// Dublikatlar

function pageDupes() {
  const head = pageHead(L('Dublikatlar', 'Duplicates', 'Дубликаты'), L("Bir xil tarkibli fayllar nusxalari", 'Copies of files with identical content', 'Копии файлов с одинаковым содержимым'), 'copy', '#A855F7',
    `<button class="btn primary" data-action="scan-dupes" ${S.dupesLoading ? 'disabled' : ''}>${icon('search')}${S.dupes ? L('Qayta skanerlash', 'Rescan', 'Пересканировать') : L('Skanerlash', 'Scan', 'Сканировать')}</button>`);
  if (S.dupesLoading) return `${head}<section class="card"><div class="empty">${spin('lg')}<p style="margin-top:12px">${L('Fayllar solishtirilmoqda… Bu bir necha daqiqa olishi mumkin.', 'Comparing files… This can take a few minutes.', 'Сравниваем файлы… Это может занять несколько минут.')}</p></div></section>`;
  if (!S.dupes) return `${head}<section class="card"><div class="empty"><span class="big-icon" style="background:var(--accent-soft);color:var(--accent)">${icon('copy')}</span><h3>${L('Nusxalarni topish', 'Find duplicates', 'Найти дубликаты')}</h3><p>${L("1 MB dan katta fayllar tarkibi bo'yicha solishtiriladi — nomi boshqacha bo'lsa ham topiladi. Har guruhda eng eski nusxa saqlab qolinadi.", 'Files over 1 MB are compared by content — found even if their names differ. The oldest copy in each group is kept.', 'Файлы больше 1 МБ сравниваются по содержимому — даже с разными именами. В каждой группе сохраняется самая старая копия.')}</p><button class="btn primary lg" data-action="scan-dupes">${L('Skanerlashni boshlash', 'Start scan', 'Начать сканирование')}</button></div></section>`;
  if (!S.dupes.length) return `${head}<section class="card"><div class="empty"><span class="big-icon" style="background:var(--ok-soft);color:var(--ok)">${icon('check')}</span><h3>${L("Dublikat yo'q", 'No duplicates', 'Дубликатов нет')}</h3></div></section>`;
  const wasted = S.dupes.reduce((a, g) => a + g.size * (g.files.length - 1), 0);
  let allGone = 0;
  const groups = S.dupes.map((g, gi) => {
    if (g.files.every((f) => f.selected)) allGone++;
    return `<section class="card" style="margin-top:12px"><ul class="list">
      <li class="row head"><div class="body"><div class="title"><span>${esc(g.files[0].name)}</span></div>
        <div class="sub">${L(`${g.files.length} ta nusxa · har biri ${fmt(g.size)}`, `${g.files.length} copies · ${fmt(g.size)} each`, `Копий: ${g.files.length} · по ${fmt(g.size)}`)}</div></div>
        ${g.files.every((f) => f.selected) ? `<span class="pill warn">${icon('warn')}${L('Hammasi tanlangan', 'All selected', 'Выбраны все')}</span>` : ''}</li>
      ${g.files.map((f, fi) => fileRow(f, 'dupe-check', `data-g="${gi}" data-f="${fi}"`, f.selected, fi === 0 ? `<span class="pill info">${L('Eng eski', 'Oldest', 'Самая старая')}</span>` : '')).join('')}
    </ul></section>`;
  }).join('');
  const sel = S.dupes.flatMap((g) => g.files.filter((f) => f.selected));
  const selSize = sel.reduce((a, f) => a + f.size, 0);
  return `${head}
    <div class="note" style="padding-top:0">${icon('info')}<span>${L(`${S.dupes.length} ta guruh · ortiqcha nusxalar ${fmt(wasted)} egallaydi.`, `${S.dupes.length} groups · extra copies take ${fmt(wasted)}.`, `Групп: ${S.dupes.length} · лишние копии занимают ${fmt(wasted)}.`)}</span></div>
    ${groups}
    ${sel.length ? actionBar(allGone ? `<span style="color:var(--warn)">${L(`${allGone} ta guruhda barcha nusxalar tanlangan`, `All copies selected in ${allGone} group(s)`, `Выбраны все копии в группах: ${allGone}`)}</span>` : L(`<b>${sel.length} ta</b> nusxa tanlandi`, `<b>${sel.length}</b> copies selected`, `Выбрано копий: <b>${sel.length}</b>`),
      `<button class="btn ${S.settings.permanent ? 'danger' : 'primary'} lg" data-action="discard-dupes">${removeLabel(selSize)}</button>`) : ''}`;
}

// Sozlamalar

function segBtns(key, opts, aria = '') {
  return `<div class="seg" role="group"${aria ? ` aria-label="${esc(aria)}"` : ''}>${opts.map(([v, label]) => `<button data-action="set" data-key="${key}" data-value="${esc(JSON.stringify(v))}" aria-pressed="${S.settings[key] === v}">${esc(label)}</button>`).join('')}</div>`;
}
function selectSet(key, opts, aria) {
  return `<select data-action="set-select" data-key="${key}" aria-label="${esc(aria)}">${opts.map(([v, label]) => `<option value="${esc(JSON.stringify(v))}" ${S.settings[key] === v ? 'selected' : ''}>${esc(label)}</option>`).join('')}</select>`;
}
function setRow(title, sub, control) {
  return `<div class="set-row"><div class="body"><div class="title">${esc(title)}</div>${sub ? `<div class="sub">${esc(sub)}</div>` : ''}</div>${control}</div>`;
}

function pageSettings() {
  const s = S.settings;
  return `${pageHead(L('Sozlamalar', 'Settings', 'Настройки'), '', 'sliders', '#64748B')}
    <h2 class="section-title">${L("Ko'rinish", 'Appearance', 'Оформление')}</h2>
    <section class="card">
      ${setRow(L('Ilova tili', 'App language', 'Язык приложения'), '', selectSet('lang', [['uz', "O'zbekcha"], ['en', 'English'], ['ru', 'Русский']], L('Til', 'Language', 'Язык')))}
      ${setRow(L('Mavzu', 'Theme', 'Тема'), '', segBtns('appearance', [['system', L('Avtomatik', 'Automatic', 'Авто')], ['light', L('Kunduzgi', 'Light', 'Светлая')], ['dark', L('Kechki', 'Dark', 'Тёмная')]], L('Mavzu', 'Theme', 'Тема')))}
    </section>
    <h2 class="section-title">${L('Maxsus imkoniyatlar', 'Accessibility', 'Специальные возможности')}</h2>
    <section class="card">
      ${setRow(L("Matn o'lchami", 'Text size', 'Размер текста'), L("Butun oyna kattalashadi. Tezkor tugmalar: Ctrl + plyus, Ctrl + minus, Ctrl + 0.", 'Enlarges the whole window. Shortcuts: Ctrl + plus, Ctrl + minus, Ctrl + 0.', 'Увеличивает всё окно. Клавиши: Ctrl + плюс, Ctrl + минус, Ctrl + 0.'),
        selectSet('textScale', [[100, '100%'], [125, '125%'], [150, '150%'], [175, '175%'], [200, '200%']], L("Matn o'lchami", 'Text size', 'Размер текста')))}
      ${setRow(L('Kuchaytirilgan kontrast', 'Increased contrast', 'Повышенная контрастность'), L("To'qroq matn, aniq chegaralar va qalin fokus ramkasi. Windows'ning yuqori kontrast mavzusi ham qo'llab-quvvatlanadi.", 'Darker text, clear borders and a thick focus frame. Windows high-contrast themes are supported too.', 'Более тёмный текст, чёткие границы и толстая рамка фокуса. Темы высокой контрастности Windows тоже поддерживаются.'),
        `<label class="switch"><input type="checkbox" data-action="set-toggle" data-key="highContrast" ${s.highContrast ? 'checked' : ''} aria-label="${esc(L('Kuchaytirilgan kontrast', 'Increased contrast', 'Повышенная контрастность'))}"></label>`)}
      ${setRow(L('Ekran o\'qigich va klaviatura', 'Screen reader and keyboard', 'Экранный диктор и клавиатура'), L("Farrosh NVDA, JAWS va Windows Hikoyachisi (Narrator) bilan ishlaydi. Hamma amalni sichqonchasiz, klaviaturadan bajarish mumkin.", 'Farrosh works with NVDA, JAWS and Windows Narrator. Everything can be done from the keyboard, without a mouse.', 'Farrosh работает с NVDA, JAWS и Экранным диктором Windows. Всё можно делать с клавиатуры, без мыши.'),
        `<button class="btn" data-action="shortcuts">${L('Tezkor tugmalar', 'Keyboard shortcuts', 'Сочетания клавиш')} (F1)</button>`)}
    </section>
    <h2 class="section-title">${L('Ruxsatlar', 'Permissions', 'Разрешения')}</h2>
    <section class="card">
      ${setRow(L('Administrator huquqlari', 'Administrator rights', 'Права администратора'),
        S.elevated ? L("Bor. Windows'ning umumiy vaqtinchalik fayllari va barcha foydalanuvchilar uchun ishga tushadigan dasturlar ham o'zgartiriladi.", 'On. Shared Windows temp files and startup items for all users can be changed too.', 'Есть. Можно менять и общие временные файлы Windows, и автозапуск для всех пользователей.')
          : L("Yo'q. Windows'ning umumiy vaqtinchalik fayllari va barcha foydalanuvchilar uchun ishga tushadigan dasturlarni o'zgartirish uchun kerak bo'ladi. Kerak bo'lganda Farrosh o'zi so'raydi.", 'Off. Needed to change shared Windows temp files and startup items for all users. Farrosh asks when it needs them.', 'Нет. Нужны, чтобы менять общие временные файлы Windows и автозапуск для всех пользователей. Farrosh спросит, когда понадобится.'),
        S.elevated ? `<span class="pill ok">${icon('check')}${L('Yoqilgan', 'On', 'Включено')}</span>` : `<button class="btn" data-action="relaunch-admin">${icon('users')}${L('Administrator sifatida ochish', 'Run as administrator', 'Запустить от имени администратора')}</button>`)}
    </section>
    <h2 class="section-title">${L("O'chirish", 'Removal', 'Удаление')}</h2>
    <section class="card">
      ${setRow(L("O'chirilgan fayllar", 'Removed files', 'Удалённые файлы'),
        s.permanent ? L("O'rnatish fayllari, qoldiqlar, katta fayllar va dublikatlar darhol o'chadi — joy shu zahoti bo'shaydi, lekin ularni qaytarib bo'lmaydi.", 'Installers, leftovers, large files and duplicates are deleted right away — space is freed at once, but they can’t be recovered.', 'Установщики, остатки, большие файлы и дубликаты удаляются сразу — место освобождается немедленно, но восстановить их нельзя.')
          : L("O'rnatish fayllari, qoldiqlar, katta fayllar va dublikatlar Savatga tushadi — xato o'chirilganini qaytarib olish mumkin. Joy Savat bo'shatilgach bo'shaydi.", 'Installers, leftovers, large files and duplicates go to the Recycle Bin — you can restore a mistake. Space is freed once the Recycle Bin is emptied.', 'Установщики, остатки, большие файлы и дубликаты попадают в Корзину — ошибку можно исправить. Место освободится после очистки Корзины.'),
        segBtns('permanent', [[false, L("Savatga ko'chirilsin", 'Move to Recycle Bin', 'В Корзину')], [true, L("Butunlay o'chirilsin", 'Delete permanently', 'Удалять навсегда')]], L("O'chirilgan fayllar", 'Removed files', 'Удалённые файлы')))}
    </section>
    <h2 class="section-title">${L('Fonda ishlash', 'Background', 'Фоновая работа')}</h2>
    <section class="card">
      ${setRow(L('Oyna yopilganda soat yonida qolish', 'Stay next to the clock when closed', 'Оставаться у часов при закрытии'), L("Farrosh belgisi vazifalar panelining o'ng tomonida turadi: bo'sh joyni ko'rsatadi va bir bosishda tozalaydi.", 'The Farrosh icon stays at the right of the taskbar: it shows free space and cleans in one click.', 'Значок Farrosh остаётся справа на панели задач: показывает свободное место и очищает в один клик.'),
        `<label class="switch"><input type="checkbox" data-action="set-toggle" data-key="closeToTray" ${s.closeToTray ? 'checked' : ''} aria-label="${esc(L('Soat yonida qolish', 'Stay next to the clock', 'Оставаться у часов'))}"></label>`)}
      ${setRow(L('Windows bilan birga ishga tushish', 'Start with Windows', 'Запускать вместе с Windows'), L('Oyna ochilmaydi — faqat soat yonidagi belgi paydo bo\'ladi.', 'No window opens — only the icon next to the clock appears.', 'Окно не открывается — появляется только значок у часов.'),
        `<label class="switch"><input type="checkbox" data-action="autostart" ${S.autostart ? 'checked' : ''} aria-label="${esc(L('Windows bilan birga ishga tushish', 'Start with Windows', 'Запускать вместе с Windows'))}"></label>`)}
      ${setRow(L('Joy kam qolganda ogohlantirish', 'Warn when free space is below', 'Предупреждать, когда свободно меньше'), L('Kuniga ko\'pi bilan bir marta bildirishnoma keladi.', 'At most one notification a day.', 'Не чаще одного уведомления в день.'),
        selectSet('lowSpaceGb', [[0, L("O'chiq", 'Off', 'Выкл.')], [5, '5 GB'], [10, '10 GB'], [20, '20 GB'], [50, '50 GB']], L('Chegara', 'Threshold', 'Порог')))}
      ${setRow(L('Tozalash eslatmasi', 'Cleanup reminder', 'Напоминание об очистке'), L('Oxirgi tozalashdan beri shuncha vaqt o\'tsa, eslatadi.', 'Reminds you when this much time has passed since the last cleanup.', 'Напомнит, если с последней очистки прошло столько времени.'),
        selectSet('reminder', [['off', L("O'chiq", 'Off', 'Выкл.')], ['weekly', L('Haftada bir', 'Weekly', 'Раз в неделю')], ['monthly', L('Oyda bir', 'Monthly', 'Раз в месяц')]], L('Eslatma', 'Reminder', 'Напоминание')))}
    </section>
    <h2 class="section-title">${L('Dastur haqida', 'About', 'О программе')}</h2>
    <section class="card">
      ${setRow('Farrosh 1.0.0', L("Windows'ni keraksiz fayllardan tozalaydi. Mac uchun versiyasi ham bor.", 'Cleans junk files off Windows. There is a Mac version too.', 'Очищает Windows от ненужных файлов. Есть и версия для Mac.'),
        `<button class="btn" data-action="open-github">${icon('external')}GitHub</button>`)}
      ${setRow(L('Versiyalar tarixi', 'Version history', 'История версий'), L("Har bir versiyada nima o'zgargani.", 'What changed in each version.', 'Что изменилось в каждой версии.'),
        `<button class="btn" data-action="open-changelog">${icon('external')}${L('Ochish', 'Open', 'Открыть')}</button>`)}
    </section>`;
}

// MARK: - Oynalar (dialog)

const modal = () => $('#modal');
let modalHandlers = {};

function openModal(html, handlers = {}, opts = {}) {
  const m = modal();
  m.innerHTML = html;
  modalHandlers = handlers;
  // Ekran o'qigich dialog ochilganda sarlavha va matnni o'qiydi.
  const h = m.querySelector('h2');
  if (h) { h.id = 'dlg-title'; m.setAttribute('aria-labelledby', 'dlg-title'); }
  const body = m.querySelector('.dlg-body');
  if (body) { body.id = 'dlg-desc'; m.setAttribute('aria-describedby', 'dlg-desc'); }
  m.dataset.locked = opts.locked ? '1' : '';
  if (!m.open) m.showModal();
  const focus = m.querySelector('[autofocus]') || m.querySelector('.dlg-foot .btn:last-child');
  if (focus) focus.focus();
}
function closeModal() {
  const m = modal();
  if (m.open) m.close();
  modalHandlers = {};
}

function confirmModal({ title, lines = [], extra = '', okLabel, danger = false }) {
  return new Promise((resolve) => {
    openModal(`<div class="dlg-body"><h2>${esc(title)}</h2>${lines.map((l) => `<p>${esc(l)}</p>`).join('')}${extra}</div>
      <div class="dlg-foot"><button class="btn" data-m="cancel">${L('Bekor qilish', 'Cancel', 'Отмена')}</button><button class="btn ${danger ? 'danger' : 'primary'}" data-m="ok" autofocus>${esc(okLabel)}</button></div>`,
    { ok: () => { const v = collectModal(); closeModal(); resolve(v || true); }, cancel: () => { closeModal(); resolve(false); } });
  });
}

/** Dialogdagi belgilash katakchalari holati. */
function collectModal() {
  const out = {};
  modal().querySelectorAll('input[type=checkbox][name]').forEach((el) => { out[el.name] = el.checked; });
  const items = [...modal().querySelectorAll('input[type=checkbox][data-pick]')].filter((el) => el.checked).map((el) => el.dataset.pick);
  return Object.keys(out).length || items.length ? { ...out, items } : null;
}

function busyModal(text) {
  announce(text);
  openModal(`<div class="dlg-body dlg-center" style="padding-bottom:28px"><div class="sweep">${tile('sparkle', '')}<span class="dot"></span><span class="dot"></span><span class="dot"></span></div><h2>${esc(text)}</h2><p>${L("Bir necha soniya kuting.", 'This takes a few seconds.', 'Подождите несколько секунд.')}</p></div>`, {}, { locked: true });
}

function resultModal(r, extraNote = '') {
  const size = r.freed + r.recycled;
  const lines = [];
  if (r.recycled) lines.push(L(`${fmt(r.recycled)} Savatga ko'chirildi. Savatni bo'shatsangiz, bu joy ham bo'shaydi.`, `${fmt(r.recycled)} moved to the Recycle Bin. Empty it to free this space too.`, `${fmt(r.recycled)} перемещено в Корзину. Очистите её, чтобы освободить и это место.`));
  if (r.failed) lines.push(L(`${r.failed} ta element o'chmadi — ular hozir ishlatilmoqda yoki himoyalangan.`, `${r.failed} items weren't removed — they are in use or protected.`, `Не удалено элементов: ${r.failed} — они используются или защищены.`));
  if (extraNote) lines.push(extraNote);
  const title = r.freed ? L(`${fmt(r.freed)} bo'shatildi`, `${fmt(r.freed)} freed`, `Освобождено ${fmt(r.freed)}`)
    : size ? L(`${fmt(size)} Savatga ko'chirildi`, `${fmt(size)} moved to the Recycle Bin`, `${fmt(size)} в Корзине`)
    : L("Hech narsa o'chmadi", 'Nothing was removed', 'Ничего не удалено');
  const offerAdmin = r.failed && !S.elevated && !r.noAdmin;
  if (offerAdmin) lines.push(L("Ba'zilari Windows tomonidan himoyalangan bo'lishi mumkin — administrator sifatida qayta urinib ko'ring.", 'Some may be protected by Windows — try again as administrator.', 'Часть может быть защищена Windows — попробуйте от имени администратора.'));
  openModal(`<div class="dlg-body dlg-center"><div class="result-icon" aria-hidden="true"${size ? '' : ' style="background:var(--warn-soft);color:var(--warn)"'}>${icon(size ? 'check' : 'warn')}</div><h2>${esc(title)}</h2>${lines.map((l) => `<p>${esc(l)}</p>`).join('')}</div>
    <div class="dlg-foot" style="justify-content:center">${offerAdmin ? `<button class="btn" data-m="admin">${icon('users')}${L('Administrator sifatida', 'As administrator', 'От имени администратора')}</button>` : ''}<button class="btn primary lg" data-m="close" autofocus>${L('Tayyor', 'Done', 'Готово')}</button></div>`,
  { close: closeModal, admin: () => { closeModal(); askAdmin(); } });
}

/** Administrator ruxsati kerak bo'lganda so'raydi va rozi bo'lsa ilovani shu huquq bilan qayta ochadi. */
async function askAdmin(reason = '') {
  if (S.elevated) return;
  const ok = await confirmModal({
    title: L('Administrator ruxsati kerak', 'Administrator permission needed', 'Нужны права администратора'),
    lines: [reason || L("Windows'ning umumiy vaqtinchalik fayllari va barcha foydalanuvchilarga tegishli sozlamalar himoyalangan.", 'Shared Windows temp files and settings for all users are protected.', 'Общие временные файлы Windows и настройки для всех пользователей защищены.'),
      L("Farrosh yopilib, administrator sifatida qayta ochiladi. Windows ruxsat so'raydi — «Ha» tugmasini bosing.", 'Farrosh will close and reopen as administrator. Windows will ask for permission — choose “Yes”.', 'Farrosh закроется и откроется снова от имени администратора. Windows спросит разрешение — нажмите «Да».')],
    okLabel: L('Administrator sifatida ochish', 'Run as administrator', 'Запустить от имени администратора'),
  });
  if (!ok) return;
  try { await invoke('relaunch_admin'); } catch (e) { toast(errText(e)); }
}

const SHORTCUTS = () => [
  ['Tab / Shift + Tab', L("Keyingi / oldingi boshqaruv elementi", 'Next / previous control', 'Следующий / предыдущий элемент')],
  ['Enter, Space', L('Tugmani bosish, belgilash', 'Press a button, toggle a checkbox', 'Нажать кнопку, отметить флажок')],
  ['Ctrl + 1', L("Umumiy ko'rinish", 'Overview', 'Обзор')],
  ['Ctrl + 2', L('Ilovalar', 'Applications', 'Приложения')],
  ['Ctrl + 3', L('Ishga tushish', 'Startup', 'Автозапуск')],
  ['Ctrl + 4', L('Katta fayllar', 'Large files', 'Большие файлы')],
  ['Ctrl + 5', L('Dublikatlar', 'Duplicates', 'Дубликаты')],
  ['Ctrl + ,', L('Sozlamalar', 'Settings', 'Настройки')],
  ['F5, Ctrl + R', L('Qayta skanerlash', 'Rescan', 'Пересканировать')],
  ['Ctrl + D', L("Disklar haqida o'qib berish", 'Read out drive space', 'Озвучить место на дисках')],
  ['Ctrl + +, Ctrl + −, Ctrl + 0', L("Matnni kattalashtirish, kichraytirish, asl holi", 'Larger, smaller, reset text', 'Крупнее, мельче, сбросить текст')],
  ['Esc', L('Oynani yopish', 'Close a dialog', 'Закрыть окно')],
  ['F1', L("Shu ro'yxat", 'This list', 'Этот список')],
];

function shortcutsModal() {
  openModal(`<div class="dlg-body"><h2>${L('Tezkor tugmalar', 'Keyboard shortcuts', 'Сочетания клавиш')}</h2>
    <table class="keys"><tbody>${SHORTCUTS().map(([k, v]) => `<tr><th scope="row"><kbd>${esc(k)}</kbd></th><td>${esc(v)}</td></tr>`).join('')}</tbody></table></div>
    <div class="dlg-foot"><button class="btn primary" data-m="close" autofocus>${L('Yopish', 'Close', 'Закрыть')}</button></div>`, { close: closeModal, cancel: closeModal });
}

// MARK: - Tozalash

async function cleanCats(ids) {
  ids = ids.filter((id) => catSelSize(id) > 0);
  if (!ids.length || S.busy) return;
  const total = ids.reduce((a, id) => a + catSelSize(id), 0);
  const onlyBin = ids.length === 1 && ids[0] === 'recycle';
  const lines = [L(`Jami ${fmt(total)} tozalanadi.`, `${fmt(total)} will be cleaned in total.`, `Всего будет очищено ${fmt(total)}.`)];
  const kept = ids.filter((id) => TO_BIN.has(id)).reduce((a, id) => a + catSelSize(id), 0);
  if (kept) lines.push(S.settings.permanent
    ? L(`O'rnatish fayllari va qoldiqlar (${fmt(kept)}) butunlay o'chadi.`, `Installers and leftovers (${fmt(kept)}) will be deleted permanently.`, `Установщики и остатки (${fmt(kept)}) будут удалены навсегда.`)
    : L(`O'rnatish fayllari va qoldiqlar (${fmt(kept)}) Savatga ko'chiriladi.`, `Installers and leftovers (${fmt(kept)}) will be moved to the Recycle Bin.`, `Установщики и остатки (${fmt(kept)}) будут перемещены в Корзину.`));
  if (ids.includes('recycle')) lines.push(L(`Savatdagi ${fmt(catSelSize('recycle'))} butunlay o'chadi va qaytarib bo'lmaydi.`, `${fmt(catSelSize('recycle'))} in the Recycle Bin will be deleted for good and can't be recovered.`, `${fmt(catSelSize('recycle'))} в Корзине будут удалены навсегда.`));
  lines.push(L("Ochiq ilovalarni yopib qo'ysangiz, ko'proq joy bo'shaydi.", 'Quit open apps to free up more space.', 'Закройте открытые приложения, чтобы освободить больше места.'));
  const ok = await confirmModal({
    title: onlyBin ? L(`Savat bo'shatilsinmi? ${fmt(total)}`, `Empty the Recycle Bin? ${fmt(total)}`, `Очистить Корзину? ${fmt(total)}`) : L(`${fmt(total)} tozalansinmi?`, `Clean ${fmt(total)}?`, `Очистить ${fmt(total)}?`),
    lines, okLabel: onlyBin ? L("Savatni bo'shatish", 'Empty Recycle Bin', 'Очистить Корзину') : L('Tozalash', 'Clean', 'Очистить'), danger: true,
  });
  if (!ok) return;
  S.busy = true;
  rerender();
  busyModal(L('Tozalanmoqda…', 'Cleaning…', 'Очистка…'));
  const requests = ids.map((id) => ({ category: id, paths: catSelected(id).flatMap((i) => i.paths) }));
  let r = { freed: 0, recycled: 0, failed: 0 };
  try { r = await invoke('clean', { requests }); } catch (e) { toast(errText(e)); }
  S.busy = false;
  resultModal(r);
  ids.forEach(scanCat);
  if (ids.some((id) => TO_BIN.has(id)) && !S.settings.permanent) scanCat('recycle');
  loadDisk();
}

async function discardFiles(paths, total, title) {
  const ok = await confirmModal({
    title,
    lines: [S.settings.permanent ? L("Fayllar butunlay o'chadi va ularni qaytarib bo'lmaydi.", 'The files will be deleted for good and can’t be recovered.', 'Файлы будут удалены навсегда без возможности восстановления.')
      : L("Fayllar Savatga ko'chiriladi — kerak bo'lsa, u yerdan qaytarib olasiz.", 'The files go to the Recycle Bin — you can restore them from there.', 'Файлы будут перемещены в Корзину — оттуда их можно восстановить.')],
    okLabel: removeLabel(total), danger: S.settings.permanent,
  });
  if (!ok) return null;
  busyModal(S.settings.permanent ? L("O'chirilmoqda…", 'Deleting…', 'Удаление…') : L("Savatga ko'chirilmoqda…", 'Moving to the Recycle Bin…', 'Перемещение в Корзину…'));
  let r = { freed: 0, recycled: 0, failed: 0 };
  try { r = await invoke('discard_paths', { paths }); } catch (e) { toast(errText(e)); }
  resultModal(r);
  loadDisk();
  scanCat('recycle');
  return r;
}

// MARK: - Ilovalarni o'chirish

async function uninstallApps(ids) {
  const apps = ids.map((id) => S.apps.find((a) => a.id === id)).filter(Boolean);
  if (!apps.length) return;
  const one = apps.length === 1;
  const title = one ? L(`«${apps[0].name}» o'chirilsinmi?`, `Uninstall “${apps[0].name}”?`, `Удалить «${apps[0].name}»?`)
    : L(`${apps.length} ta ilova o'chirilsinmi?`, `Uninstall ${apps.length} apps?`, `Удалить программы (${apps.length})?`);
  const list = one ? '' : `<div class="scroll"><ul class="list">${apps.map((a) => `<li class="row">${avatar(a.name)}<div class="body"><div class="title"><span>${esc(a.name)}</span></div></div><span class="size">${a.size ? fmt(a.size) : ''}</span></li>`).join('')}</ul></div>`;
  const res = await confirmModal({
    title,
    lines: [one ? L("Dasturning o'z o'chirish oynasi ochiladi — undagi ko'rsatmalarga amal qiling. Windows ruxsat so'rashi mumkin.", 'The app’s own uninstaller will open — follow its steps. Windows may ask for permission.', 'Откроется деинсталлятор программы — следуйте его шагам. Windows может запросить разрешение.')
      : L("Har bir dasturning o'z o'chirish oynasi navbat bilan ochiladi — ko'rsatmalariga amal qiling. Windows ruxsat so'rashi mumkin.", 'Each app’s uninstaller opens in turn — follow its steps. Windows may ask for permission.', 'Деинсталляторы откроются по очереди — следуйте их шагам. Windows может запросить разрешение.')],
    extra: `${list}<label class="row" style="min-height:0;padding:12px 0 0"><input type="checkbox" class="check" name="leftovers" checked><span>${L("Keyin qoldiq papkalarini ham qidirish", 'Then look for leftover folders', 'Затем найти оставшиеся папки')}</span></label>`,
    okLabel: one ? L("O'chirish", 'Uninstall', 'Удалить') : L(`${apps.length} ta ilovani o'chirish`, `Uninstall ${apps.length} apps`, `Удалить (${apps.length})`), danger: true,
  });
  if (!res) return;
  const wantLeftovers = res.leftovers !== false;
  const status = Object.fromEntries(apps.map((a) => [a.id, 'wait']));
  let skip = false;
  const draw = (current) => {
    const label = { wait: L('Navbatda', 'Waiting', 'В очереди'), run: L("O'chirish oynasi ochiq", 'Uninstaller is open', 'Деинсталлятор открыт'), done: L("O'chirildi", 'Uninstalled', 'Удалено'), kept: L("O'chirilmadi", 'Not uninstalled', 'Не удалено'), fail: L('Xatolik', 'Error', 'Ошибка') };
    const pill = { wait: 'gray', run: 'info', done: 'ok', kept: 'warn', fail: 'warn' };
    openModal(`<div class="dlg-body"><h2>${L("Ilovalar o'chirilmoqda", 'Uninstalling apps', 'Удаление программ')}</h2>
      <p>${current ? L(`«${esc(current.name)}» o'chirish oynasini tugating. Oyna ko'rinmasa, vazifalar panelini tekshiring.`, `Finish the “${esc(current.name)}” uninstaller. If you don't see it, check the taskbar.`, `Завершите деинсталлятор «${esc(current.name)}». Если окна не видно, проверьте панель задач.`) : ''}</p>
      <div class="scroll"><ul class="list">${apps.map((a) => `<li class="row">${avatar(a.name)}<div class="body"><div class="title"><span>${esc(a.name)}</span></div></div>
        <span class="pill ${pill[status[a.id]]}">${status[a.id] === 'run' ? spin() : ''}${label[status[a.id]]}</span></li>`).join('')}</ul></div></div>
      <div class="dlg-foot">${current ? `<button class="btn" data-m="skip">${L("Kutmasdan davom etish", 'Continue without waiting', 'Продолжить, не дожидаясь')}</button>` : ''}</div>`,
    { skip: () => { skip = true; } }, { locked: true });
  };
  const removed = [];
  for (const a of apps) {
    status[a.id] = 'run';
    skip = false;
    draw(a);
    try {
      let gone = await invoke('uninstall_app', { id: a.id, quiet: false });
      // Ko'p o'chirish dasturlari darhol nusxasini ishga tushirib, o'zi yopiladi — ro'yxatdan yo'qolguncha kutamiz.
      for (let t = 0; !gone && !skip && t < 300; t++) {
        await new Promise((r) => setTimeout(r, 2000));
        gone = !(await invoke('app_exists', { id: a.id }));
      }
      status[a.id] = gone ? 'done' : 'kept';
      if (gone) removed.push(a);
    } catch (e) {
      status[a.id] = String(e) === 'cancelled' ? 'kept' : 'fail';
    }
  }
  draw(null);
  S.apps = S.apps.filter((a) => !removed.some((r) => r.id === a.id));
  removed.forEach((a) => S.appChecked.delete(a.id));
  rerender();
  if (!wantLeftovers || !removed.length) {
    resultModal({ freed: removed.reduce((s, a) => s + a.size, 0), recycled: 0, failed: apps.length - removed.length });
    loadDisk();
    return;
  }
  busyModal(L('Qoldiqlar qidirilmoqda…', 'Looking for leftovers…', 'Ищем остатки…'));
  let left = [];
  for (const a of removed) {
    try { left = left.concat(await invoke('app_leftovers', { name: a.name, publisher: a.publisher, location: a.location })); } catch (e) { console.error(e); }
  }
  const freedApps = removed.reduce((s, a) => s + a.size, 0);
  if (!left.length) {
    resultModal({ freed: freedApps, recycled: 0, failed: apps.length - removed.length }, L('Qoldiq papkalar topilmadi.', 'No leftover folders found.', 'Оставшихся папок не найдено.'));
    loadDisk();
    return;
  }
  const leftTotal = left.reduce((s, i) => s + i.size, 0);
  const ok = await confirmModal({
    title: L(`Qoldiqlar topildi: ${fmt(leftTotal)}`, `Leftovers found: ${fmt(leftTotal)}`, `Найдены остатки: ${fmt(leftTotal)}`),
    lines: [L(`${removed.length} ta ilova o'chirildi. Ularning sozlama va ma'lumot papkalari qoldi — o'chirilsinmi?`, `${removed.length} app(s) uninstalled. Their settings and data folders remain — remove them?`, `Удалено программ: ${removed.length}. Остались папки с настройками и данными — удалить их?`)],
    extra: `<div class="scroll"><ul class="list">${left.map((i) => `<li class="row"><input type="checkbox" class="check" data-pick="${esc(i.paths[0])}" ${i.selected ? 'checked' : ''} aria-label="${esc(i.name)}"><div class="body"><div class="title"><span>${esc(i.name)}</span>${i.review ? `<span class="pill warn">${icon('warn')}${L('Tekshiring', 'Review', 'Проверьте')}</span>` : ''}</div><div class="sub">${esc(i.detail)}</div></div><span class="size">${fmt(i.size)}</span></li>`).join('')}</ul></div>`,
    okLabel: S.settings.permanent ? L("Qoldiqlarni o'chirish", 'Delete leftovers', 'Удалить остатки') : L("Qoldiqlarni Savatga ko'chirish", 'Move leftovers to Recycle Bin', 'Остатки — в Корзину'),
    danger: S.settings.permanent,
  });
  let r = { freed: freedApps, recycled: 0, failed: apps.length - removed.length };
  if (ok && ok.items && ok.items.length) {
    busyModal(L('Qoldiqlar tozalanmoqda…', 'Removing leftovers…', 'Удаляем остатки…'));
    try {
      const x = await invoke('discard_paths', { paths: ok.items });
      r = { freed: r.freed + x.freed, recycled: x.recycled, failed: r.failed + x.failed };
    } catch (e) { toast(errText(e)); }
  }
  resultModal(r);
  loadDisk();
  scanCat('leftovers');
  scanCat('recycle');
}

// MARK: - Sozlamalarni saqlash

async function saveSettings(patch) {
  const prevLang = S.settings.lang;
  S.settings = { ...S.settings, ...patch };
  applyTheme();
  rerender();
  try { S.settings = await invoke('save_settings', { settings: S.settings }); } catch (e) { toast(errText(e)); }
  if (patch.lang && patch.lang !== prevLang) {
    document.documentElement.lang = S.settings.lang;
    CATS.forEach((c) => scanCat(c.id)); // Toifa nomlari Rust'dan ham shu tilda kelsin.
  }
}

function applyTheme() {
  const a = S.settings.appearance;
  const root = document.documentElement;
  if (a === 'light' || a === 'dark') root.dataset.theme = a;
  else delete root.dataset.theme;
  if (S.settings.highContrast) root.dataset.contrast = 'high';
  else delete root.dataset.contrast;
  // Butun oyna (matn, tugmalar, belgilar) bir xil kattalashadi — brauzerdagi Ctrl+plyus kabi.
  const z = (S.settings.textScale || 100) / 100;
  const wv = TAURI?.webview?.getCurrentWebview?.();
  if (wv?.setZoom) {
    wv.setZoom(z).catch((e) => console.error(e));
  } else {
    // Oddiy brauzerda ko'rish uchun (mock): CSS zoom.
    document.body.style.zoom = String(z);
    root.style.setProperty('--z', String(z));
  }
}

const SCALES = [100, 125, 150, 175, 200];
function stepScale(dir) {
  const cur = S.settings.textScale || 100;
  const next = dir === 0 ? 100 : dir > 0 ? SCALES.find((x) => x > cur) || 200 : [...SCALES].reverse().find((x) => x < cur) || 100;
  if (next === cur) return;
  saveSettings({ textScale: next });
  announce(L(`Matn o'lchami ${next}%`, `Text size ${next}%`, `Размер текста ${next}%`));
}

// MARK: - Hodisalar

document.addEventListener('click', async (ev) => {
  const m = ev.target.closest('[data-m]');
  if (m && modal().contains(m)) { modalHandlers[m.dataset.m]?.(); return; }
  const routeEl = ev.target.closest('[data-route]');
  if (routeEl && !ev.target.closest('input')) { go(routeEl.dataset.route); return; }
  const el = ev.target.closest('[data-action]');
  if (!el) return;
  const a = el.dataset.action;
  const id = el.dataset.id;
  switch (a) {
    case 'rescan-all': scanAll(); break;
    case 'rescan-cat': scanCat(S.route.slice(4)); loadDisk(); break;
    case 'clean-scope': cleanCats([...S.scope]); break;
    case 'clean-cat': cleanCats([el.dataset.cat]); break;
    case 'scope': if (el.checked) S.scope.add(id); else S.scope.delete(id); rerender(); break;
    case 'item': { const it = catItems(el.dataset.cat)[+el.dataset.i]; if (it) it.selected = el.checked; rerender(); break; }
    case 'cat-all': catItems(el.dataset.cat).forEach((i) => { i.selected = el.checked; }); rerender(); break;
    case 'reveal': invoke('reveal', { path: el.dataset.path }).catch((e) => toast(errText(e))); break;
    case 'reload-apps': loadApps(); break;
    case 'app-check': if (el.checked) S.appChecked.add(id); else S.appChecked.delete(id); renderMain(); break;
    case 'apps-all': visibleApps().forEach((x) => (el.checked ? S.appChecked.add(x.id) : S.appChecked.delete(x.id))); renderMain(); break;
    case 'apps-none': S.appChecked.clear(); renderMain(); break;
    case 'uninstall-one': uninstallApps([id]); break;
    case 'uninstall-checked': uninstallApps([...S.appChecked]); break;
    case 'reload-startup': loadStartup(); break;
    case 'startup-toggle': {
      const e = S.startup.find((x) => x.id === id);
      try { await invoke('set_startup', { id, enabled: el.checked }); e.enabled = el.checked; }
      catch (err) { el.checked = !el.checked; if (String(err) === 'admin' && !S.elevated) askAdmin(errText(err)); else toast(errText(err), 7000); }
      renderMain();
      break;
    }
    case 'startup-remove': {
      const e = S.startup.find((x) => x.id === id);
      const ok = await confirmModal({
        title: L(`«${e.name}» ro'yxatdan olib tashlansinmi?`, `Remove “${e.name}” from startup?`, `Убрать «${e.name}» из автозапуска?`),
        lines: [L("Dastur kompyuterda qoladi, faqat Windows bilan birga ochilmaydi. Qaytarish uchun dasturning o'z sozlamalaridan yoqish kerak bo'ladi — vaqtincha to'xtatish uchun almashtirgichdan foydalaning.", 'The app stays installed, it just won’t open with Windows. To undo, you’d need to turn it on in the app’s own settings — use the switch to pause it instead.', 'Программа останется установленной, просто не будет запускаться с Windows. Чтобы вернуть, придётся включить это в её настройках — для паузы используйте переключатель.')],
        okLabel: L('Olib tashlash', 'Remove', 'Убрать'), danger: true,
      });
      if (!ok) break;
      try { await invoke('remove_startup', { id }); S.startup = S.startup.filter((x) => x.id !== id); renderMain(); }
      catch (err) { if (String(err) === 'admin' && !S.elevated) askAdmin(errText(err)); else toast(errText(err), 7000); }
      break;
    }
    case 'scan-large':
      S.largeLoading = true; S.largeKind = 'all'; renderMain();
      try { S.large = (await invoke('scan_large', { minMb: S.settings.largeMinMb })).map((f) => ({ ...f, selected: false })); } catch (e) { toast(errText(e)); }
      S.largeLoading = false; renderMain();
      break;
    case 'large-kind': S.largeKind = el.dataset.kind; renderMain(); break;
    case 'large-check': { const f = S.large.find((x) => x.path === el.dataset.path); if (f) f.selected = el.checked; renderMain(); break; }
    case 'discard-large': {
      const sel = S.large.filter((f) => f.selected);
      const size = sel.reduce((s, f) => s + f.size, 0);
      const r = await discardFiles(sel.map((f) => f.path), size, L(`${sel.length} ta fayl o'chirilsinmi?`, sel.length === 1 ? 'Remove 1 file?' : `Remove ${sel.length} files?`, `Удалить файлы (${sel.length})?`));
      if (r) { S.large = S.large.filter((f) => !f.selected); renderMain(); }
      break;
    }
    case 'scan-dupes':
      S.dupesLoading = true; renderMain();
      try { S.dupes = (await invoke('scan_duplicates')).map((g) => ({ ...g, files: g.files.map((f, i) => ({ ...f, selected: i > 0 })) })); } catch (e) { toast(errText(e)); }
      S.dupesLoading = false; renderMain();
      break;
    case 'dupe-check': { const f = S.dupes[+el.dataset.g]?.files[+el.dataset.f]; if (f) f.selected = el.checked; renderMain(); break; }
    case 'discard-dupes': {
      const sel = S.dupes.flatMap((g) => g.files.filter((f) => f.selected));
      const size = sel.reduce((s, f) => s + f.size, 0);
      const r = await discardFiles(sel.map((f) => f.path), size, L(`${sel.length} ta nusxa o'chirilsinmi?`, sel.length === 1 ? 'Remove 1 copy?' : `Remove ${sel.length} copies?`, `Удалить копии (${sel.length})?`));
      if (r) {
        S.dupes = S.dupes.map((g) => ({ ...g, files: g.files.filter((f) => !f.selected) })).filter((g) => g.files.length > 1);
        renderMain();
      }
      break;
    }
    case 'set': saveSettings({ [el.dataset.key]: JSON.parse(el.dataset.value) }); break;
    case 'set-toggle': saveSettings({ [el.dataset.key]: el.checked }); break;
    case 'autostart':
      try { S.autostart = await invoke('set_autostart', { enabled: el.checked }); } catch (e) { toast(errText(e)); }
      renderMain();
      break;
    case 'relaunch-admin': askAdmin(); break;
    case 'shortcuts': shortcutsModal(); break;
    case 'open-changelog': invoke('open_url', { url: 'https://github.com/bahodirhasan/farrosh/blob/main/windows/CHANGELOG.md' }).catch(() => {}); break;
    case 'open-github': invoke('open_url', { url: 'https://github.com/bahodirhasan/farrosh' }).catch(() => {}); break;
  }
});

document.addEventListener('change', (ev) => {
  const el = ev.target;
  if (el.dataset.action === 'set-select') saveSettings({ [el.dataset.key]: JSON.parse(el.value) });
  if (el.id === 'app-sort') { S.appSort = el.value; renderMain(); }
  if (el.id === 'large-min') saveSettings({ largeMinMb: +el.value });
});

document.addEventListener('input', (ev) => {
  if (ev.target.id === 'app-q') { S.appQuery = ev.target.value; renderMain(); }
});

// Bloklangan dialogni Esc bilan yopib bo'lmaydi (masalan, tozalash davomida).
modal().addEventListener('cancel', (ev) => {
  if (modal().dataset.locked) ev.preventDefault();
  else modalHandlers.cancel?.();
});

document.addEventListener('keydown', (ev) => {
  if (ev.key === 'F5' || (ev.ctrlKey && ev.key.toLowerCase() === 'r')) {
    ev.preventDefault();
    if (S.route === 'apps') loadApps();
    else if (S.route === 'startup') loadStartup();
    else if (S.route.startsWith('cat:')) scanCat(S.route.slice(4));
    else if (S.route === 'overview') scanAll();
  }
  if (ev.ctrlKey && ev.key === ',') { ev.preventDefault(); go('settings'); }
  if (modal().open) return;
  const routes = { 1: 'overview', 2: 'apps', 3: 'startup', 4: 'large', 5: 'dupes' };
  if (ev.ctrlKey && !ev.shiftKey && !ev.altKey && routes[ev.key]) { ev.preventDefault(); go(routes[ev.key]); }
  if (ev.key === 'F1') { ev.preventDefault(); shortcutsModal(); }
  if (ev.ctrlKey && (ev.key === '+' || ev.key === '=')) { ev.preventDefault(); stepScale(1); }
  if (ev.ctrlKey && ev.key === '-') { ev.preventDefault(); stepScale(-1); }
  if (ev.ctrlKey && ev.key === '0') { ev.preventDefault(); stepScale(0); }
  if (ev.ctrlKey && ev.key.toLowerCase() === 'd') {
    ev.preventDefault();
    const disks = S.disks && S.disks.length ? S.disks : S.disk ? [S.disk] : [];
    announce(disks.map(diskSpeech).join('. '));
  }
});
document.addEventListener('contextmenu', (ev) => { if (!ev.target.closest('input[type=search]')) ev.preventDefault(); });

// MARK: - Ishga tushirish

(async function start() {
  try { S.settings = { ...S.settings, ...(await invoke('get_settings')) }; } catch (e) { console.error(e); }
  try { S.autostart = await invoke('get_autostart'); } catch { /* ixtiyoriy */ }
  try { S.elevated = await invoke('is_elevated'); } catch { /* ixtiyoriy */ }
  document.documentElement.lang = S.settings.lang;
  applyTheme();
  rerender();
  scanAll();
  loadApps();
  if (TAURI?.event) {
    TAURI.event.listen('cleaned', () => { ['appCaches', 'temp', 'devCaches'].forEach(scanCat); loadDisk(); });
  }
  setInterval(loadDisk, 60_000);
  // Skrinshot va sinov uchun: index.html?route=settings
  const startRoute = new URLSearchParams(location.search).get('route');
  if (startRoute) go(startRoute);
})();
