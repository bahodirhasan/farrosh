#!/bin/zsh
# Farrosh.app ni yig'adi: Apple Silicon va Intel uchun bitta universal ilova (macOS 13+).
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"
APP="build/Farrosh.app"
rm -rf build && mkdir -p build

for arch in arm64 x86_64; do
  echo "→ $arch uchun kompilyatsiya"
  swiftc -swift-version 5 -parse-as-library -O \
    -target "$arch-apple-macos13.0" -sdk "$SDK" \
    Sources/*.swift -o "build/Farrosh-$arch"
done

for arch in arm64 x86_64; do
  echo "→ Vidjet: $arch"
  swiftc -swift-version 5 -parse-as-library -O -application-extension \
    -target "$arch-apple-macos14.0" -sdk "$SDK" \
    -Xlinker -e -Xlinker _NSExtensionMain \
    Widget/*.swift -o "build/FarroshWidget-$arch"
done

echo "→ Ikonka"
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
swift Resources/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/AppIcon.icns

echo "→ Ilova paketi"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create build/Farrosh-arm64 build/Farrosh-x86_64 -output "$APP/Contents/MacOS/Farrosh"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Tizim menyulari (Edit, Window…) tanlangan tilda chiqishi uchun.
for lang in uz en ru; do mkdir -p "$APP/Contents/Resources/$lang.lproj"; touch "$APP/Contents/Resources/$lang.lproj/InfoPlist.strings"; done

# Ish stoli vidjeti — ilova ichidagi WidgetKit kengaytmasi.
APPEX="$APP/Contents/PlugIns/FarroshWidget.appex"
mkdir -p "$APPEX/Contents/MacOS"
lipo -create build/FarroshWidget-arm64 build/FarroshWidget-x86_64 -output "$APPEX/Contents/MacOS/FarroshWidget"
cp Widget/Info.plist "$APPEX/Contents/Info.plist"
# Keychain'dagi doimiy «Farrosh Developer» imzosi: macOS bergan ruxsatlar (papkalar,
# System Events, To'liq disk ruxsati) qayta yig'ilganda ham saqlanib qoladi.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"Farrosh Developer"/ {print $2; exit}')
if [[ -n "$IDENTITY" ]]; then
  echo "→ Imzo: Farrosh Developer"
else
  echo "→ Imzo: vaqtinchalik (ad-hoc) — ruxsatlar har yig'ishda qayta so'raladi"
  IDENTITY="-"
fi
# Avval vidjet (sandbox bilan — WidgetKit buni talab qiladi), keyin ilovaning o'zi.
# --deep ishlatilmaydi: u vidjet imzosidagi sandbox ruxsatini o'chirib yuboradi.
codesign --force --options runtime --entitlements Widget/Widget.entitlements --sign "$IDENTITY" "$APPEX"
codesign --force --sign "$IDENTITY" "$APP"

lipo -info "$APP/Contents/MacOS/Farrosh"
echo "Tayyor: $PWD/$APP"
