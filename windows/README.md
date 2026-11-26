# Farrosh for Windows

### ⬇️ [Yuklab olish — Farrosh_1.0.0_x64-setup.exe](https://github.com/bahodirhasan/farrosh/releases/download/windows-v1.0.0/Farrosh_1.0.0_x64-setup.exe)

O'rnatmasdan ishlatish uchun: [Farrosh.exe (ko'chma)](https://github.com/bahodirhasan/farrosh/releases/download/windows-v1.0.0/Farrosh.exe)

Windows 10 va 11 uchun Farrosh: kompyuterdagi keraksiz fayllarni topib tozalaydi. Interfeys o'zbek, ingliz va rus tillarida.

*Farrosh for Windows cleans up caches, temp files, installers, leftovers of removed apps, large files and duplicates. Uzbek, English and Russian.*

## O'rnatish

1. Yuqoridagi havoladan yoki [**Releases**](https://github.com/bahodirhasan/farrosh/releases/tag/windows-v1.0.0) sahifasidan `Farrosh_1.0.0_x64-setup.exe` ni yuklab oling va ishga tushiring. O'rnatish uchun administrator huquqi kerak emas.
2. Dastur imzolanmagan, shuning uchun birinchi marta Windows SmartScreen ogohlantirishi chiqishi mumkin: **Batafsil (More info) → Baribir ishga tushirish (Run anyway)**.

O'rnatmasdan ishlatish ham mumkin: `Farrosh.exe` ni (ko'chma versiya) to'g'ridan-to'g'ri ishga tushiring. Bu holda bildirishnomalar ishlamasligi mumkin.

Talablar: Windows 10 (1809+) yoki Windows 11, 64 bit. Microsoft Edge WebView2 Windows 11 da allaqachon bor, Windows 10 da o'rnatuvchi uni o'zi yuklab oladi.

## Imkoniyatlar

- **Umumiy ko'rinish.** Diskda qancha bo'sh joy borligini va uni nima egallab turganini ko'rsatadi: dasturlar, hujjatlar, media, ilovalar ma'lumoti, keraksiz fayllar, Windows.
- **Barcha disklar.** Kompyuterdagi hamma disklar (C:, D:, fleshkalar, tarmoq disklari) bitta ro'yxatda. Katta fayllar va dublikatlar barcha disklardan qidiriladi.
- **Ruxsat kerak bo'lganda so'raydi.** Himoyalangan joyni tozalash yoki barcha foydalanuvchilar sozlamasini o'zgartirish uchun Farrosh administrator ruxsatini so'raydi va o'zini shu huquq bilan qayta ochadi.
- **Tozalash toifalari:**
  - ilovalar va brauzerlar keshi (Chrome, Edge, Firefox, Telegram, VS Code…);
  - vaqtinchalik fayllar, nosozlik dumplari va xato hisobotlari;
  - dasturchi keshlari: npm, pip, Gradle, NuGet, Cargo, JetBrains va boshqalar;
  - eski `.exe`, `.msi` va `.iso` o'rnatish fayllari;
  - o'chirilgan dasturlardan qolgan papkalar;
  - Savat.
- **Ilovalar.** Dasturlarni bittalab yoki bir nechtasini birdan o'chiradi, keyin ularning AppData'dagi qoldiqlarini topadi.
- **Ishga tushish.** Windows bilan birga ochiladigan dasturlarni yoqadi yoki o'chiradi. Vazifalar menejeri bilan bir xil usulda ishlaydi, shuning uchun istalgan payt qaytarish mumkin.
- **Katta fayllar** va **dublikatlar** (tarkibi bo'yicha solishtiriladi). OneDrive'dagi "faqat onlayn" fayllar hisobga olinmaydi.
- **Soat yonidagi belgi:**
  - bo'sh joyni ko'rsatadi va bir bosishda tozalaydi;
  - joy kam qolganda ogohlantiradi;
  - haftalik yoki oylik tozalash eslatmasini yuboradi.

## Ko'zi ojiz va ko'rishi past foydalanuvchilar uchun

- NVDA, JAWS va Windows Hikoyachisi (Narrator) bilan ishlaydi. Skanerlash va tozalash natijalari ovozli aytiladi.
- Hamma amal klaviaturadan bajariladi. **F1** — tezkor tugmalar ro'yxati, **Ctrl + 1…5** — bo'limlar, **Ctrl + D** — disklarni o'qib berish.
- Matn o'lchami 100–200% (**Ctrl + plyus / minus / 0**), kuchaytirilgan kontrast va Windows yuqori kontrast mavzulari.

Versiyalar tarixi: [CHANGELOG.md](CHANGELOG.md).

Kesh va vaqtinchalik fayllar darhol o'chiriladi. O'rnatish fayllari, qoldiqlar, katta fayllar va dublikatlar avval Savatga tushadi, buni Sozlamalarda o'zgartirish mumkin.

## Manbadan yig'ish

Ilova [Tauri 2](https://tauri.app) asosida qurilgan: Rust backend va HTML/CSS/JS interfeys.

**Mac'da Windows uchun:**

```bash
rustup target add x86_64-pc-windows-gnu
brew install mingw-w64 makensis
cd windows && npm install && ./build.sh
```

Natija `windows/dist/` papkasiga tushadi: `Farrosh.exe` (ko'chma) va `Farrosh_1.0.0_x64-setup.exe` (o'rnatuvchi).

**Windows'da:** `npm install`, keyin `npx tauri build`.

**Interfeysni ko'rish:** `src/index.html` ni oddiy brauzerda ochsa ham bo'ladi. Bunda `mock.js` namunaviy ma'lumot beradi.

Tuzilishi:
- `src/` — interfeys;
- `src-tauri/src/` — Rust qismi:
  - `junk.rs` — tozalash toifalari;
  - `apps.rs` — dasturlar;
  - `startup.rs` — ishga tushish;
  - `files.rs` — katta fayllar va dublikatlar;
  - `tray.rs` — soat yonidagi belgi;
- `scripts/make-icon.swift` — ikonka.
