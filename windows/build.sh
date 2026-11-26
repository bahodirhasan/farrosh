#!/bin/bash
# Farrosh for Windows'ni Mac'da yig'adi: o'rnatuvchi (NSIS) va ko'chma .exe → windows/dist/
# Kerak: rustup target add x86_64-pc-windows-gnu · brew install mingw-w64 makensis · npm install
set -euo pipefail
cd "$(dirname "$0")"
TARGET=x86_64-pc-windows-gnu
# Homebrew makensis C locale bilan std::bad_alloc bilan yiqiladi, UTF-8 locale kerak
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
npx tauri build --target "$TARGET"
mkdir -p dist
cp "src-tauri/target/$TARGET/release/farrosh.exe" dist/Farrosh.exe
cp src-tauri/target/$TARGET/release/bundle/nsis/*-setup.exe dist/
ls -lh dist
echo "Tayyor: $(pwd)/dist"
