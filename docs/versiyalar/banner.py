#!/usr/bin/env python3
"""Versiyalar tarixi uchun skrinshotli bannerlar (1600×800 PNG).

Ishlatish:  python3 docs/versiyalar/banner.py
Kerak: Google Chrome (headless). Skrinshotlar docs/versiyalar/src/ da.
"""
import html, os, pathlib, subprocess, tempfile

HERE = pathlib.Path(__file__).resolve().parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

LOGO = """<svg viewBox="0 0 1024 1024" width="56" height="56"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3B82F6"/><stop offset="1" stop-color="#1E3A8A"/></linearGradient></defs><rect x="40" y="40" width="944" height="944" rx="210" fill="url(#g)" stroke="rgba(255,255,255,.35)" stroke-width="16"/><g transform="translate(512,512) scale(1.9) translate(-114,-153)" fill="#fff"><polygon points="0,100 224,6 228,108 0,146" stroke="#fff" stroke-width="12" stroke-linejoin="round"/><polygon points="0,170 174,154 174,228 0,230" stroke="#fff" stroke-width="12" stroke-linejoin="round"/><rect x="-6" y="248" width="22" height="58" rx="11"/><rect x="26" y="248" width="22" height="50" rx="11"/><rect x="58" y="248" width="22" height="42" rx="11"/><rect x="90" y="248" width="22" height="34" rx="11"/></g></svg>"""

# (fayl nomi, platforma, versiya, sana, sarlavha, bandlar, skrinshot)
BANNERS = [
    ("mac-1.4", "Mac", "1.4", "26-noyabr, 2026", "Ko'zi ojizlar uchun",
     ["VoiceOver har bir qator va tugmani to'liq o'qiydi", "Skanerlash va tozalash natijasi ovozli aytiladi", "Belgilash, ochish va Finder — klaviaturadan"],
     "mac-kesh.jpg"),
    ("mac-1.3", "Mac", "1.3", "22-noyabr, 2026", "Tozalash animatsiyasi",
     ["Supurish animatsiyasi va sanab boruvchi natija", "Farrosh o'zini ham o'chira oladi", "Farrosh o'z ilovalar ro'yxatida ko'rinadi"],
     "mac-umumiy.jpg"),
    ("mac-1.2", "Mac", "1.2", "22-noyabr, 2026", "Himoyalangan ilovalar",
     ["Xcode kabi administrator ilovalarini o'chirish", "Bitta standart macOS parol oynasi orqali", "Xato o'rniga aniq natija"],
     "mac-ilovalar.jpg"),
    ("mac-1.1", "Mac", "1.1", "22-noyabr, 2026", "Jonli ro'yxatlar",
     ["Xcode, Pages kabi Apple ilovalari ham ko'rinadi", "Ro'yxatlar fayl paydo bo'lishi bilan yangilanadi", "Yuklamalar, Savat va qoldiqlar kuzatiladi"],
     "mac-ilovalar.jpg"),
    ("mac-1.0", "Mac", "1.0", "22-noyabr, 2026", "Birinchi versiya",
     ["Kesh, loglar, dasturchi keshlari va Savat", "Ilovalar, ishga tushish, katta fayllar, dublikatlar", "Menyu satri, vidjetlar va eslatmalar"],
     "mac-umumiy.jpg"),
    ("windows-1.0.0", "Windows", "1.0.0", "26-noyabr, 2026", "Farrosh endi Windows'da",
     ["Kompyuterdagi barcha disklar bir oynada", "Kerak bo'lganda administrator ruxsatini so'raydi", "NVDA, JAWS, Hikoyachi, katta matn va kontrast"],
     "win-umumiy.png"),
]

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
*{{box-sizing:border-box;margin:0}}
body{{width:1600px;height:800px;overflow:hidden;font-family:-apple-system,"Segoe UI",Inter,sans-serif;color:#fff;
  background:radial-gradient(1200px 700px at 85% 110%,#60A5FA55,transparent 60%),linear-gradient(135deg,#1E3A8A 0%,#2563EB 70%,#3B82F6 100%);position:relative}}
.left{{position:absolute;left:84px;top:86px;width:560px}}
.brand{{display:flex;align-items:center;gap:16px;font-size:26px;font-weight:600;opacity:.95}}
.brand small{{display:block;font-size:19px;font-weight:400;opacity:.75;margin-top:2px}}
.ver{{font-size:168px;font-weight:800;letter-spacing:-6px;line-height:1;margin-top:52px}}
.date{{font-size:22px;opacity:.75;margin-top:10px}}
h1{{font-size:44px;font-weight:700;margin-top:34px;letter-spacing:-.5px}}
ul{{list-style:none;padding:0;margin-top:22px}}
li{{font-size:24px;line-height:1.35;margin-top:12px;padding-left:34px;position:relative;opacity:.95}}
li:before{{content:"";position:absolute;left:4px;top:11px;width:12px;height:12px;border-radius:50%;background:#93C5FD}}
.shot{{position:absolute;left:700px;top:74px;width:1000px;height:760px;border-radius:22px;overflow:hidden;
  box-shadow:0 40px 90px rgba(5,12,40,.55),0 0 0 1px rgba(255,255,255,.18)}}
.shot img{{width:100%;height:100%;object-fit:cover;object-position:left top;display:block}}
</style></head><body>
<div class="left">
  <div class="brand">{logo}<div>Farrosh<small>{platform} uchun</small></div></div>
  <div class="ver">{ver}</div>
  <div class="date">{date}</div>
  <h1>{title}</h1>
  <ul>{items}</ul>
</div>
<div class="shot"><img src="{img}"></div>
</body></html>"""


def main():
    out = HERE
    with tempfile.TemporaryDirectory() as tmp:
        for name, platform, ver, date, title, items, shot in BANNERS:
            page = PAGE.format(
                logo=LOGO, platform=platform, ver=html.escape(ver), date=html.escape(date), title=html.escape(title),
                items="".join(f"<li>{html.escape(i)}</li>" for i in items), img=(HERE / "src" / shot).as_uri())
            src = pathlib.Path(tmp) / f"{name}.html"
            src.write_text(page, encoding="utf-8")
            subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                            "--window-size=1600,800", "--force-device-scale-factor=1", f"--user-data-dir={tmp}/chrome",
                            f"--screenshot={out / (name + '.png')}", src.as_uri()],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print("✓", name + ".png")


if __name__ == "__main__":
    main()
