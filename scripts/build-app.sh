#!/usr/bin/env bash
# Builds build/Läsa.app (self-contained) and runs package-app.sh, which signs it ad hoc and makes
# build/Läsa.zip and build/Läsa.dmg. Optional environment: VERSION (e.g. 1.2.0) and BUILD (e.g. a
# CI run number) are written into Info.plist as CFBundleShortVersionString and CFBundleVersion.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/check-requirements.sh
./scripts/fetch-vendor.sh
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Lasa"

APP="build/Läsa.app"
ZIP="build/Läsa.zip"
DMG="build/Läsa.dmg"
# Also remove outputs from builds made before the bundle was renamed from Lasa.
rm -rf "$APP" "$ZIP" "$DMG" build/Lasa.app build/Lasa.zip build/Lasa.dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/piper"

cp "$BIN" "$APP/Contents/MacOS/Lasa"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Packaging/en.lproj Packaging/sv.lproj "$APP/Contents/Resources/"
cp Vendor/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib Vendor/sherpa-onnx/lib/libonnxruntime.dylib "$APP/Contents/Frameworks/"
cp -R Vendor/piper/. "$APP/Contents/Resources/piper/"

FW="$APP/Contents/Frameworks"
CAPI="$FW/libsherpa-onnx-c-api.dylib"
ORT="$FW/libonnxruntime.dylib"
EXE="$APP/Contents/MacOS/Lasa"

install_name_tool -id @rpath/libsherpa-onnx-c-api.dylib "$CAPI"
install_name_tool -id @rpath/libonnxruntime.dylib "$ORT"

old_ort="$(otool -L "$CAPI" | awk '/libonnxruntime/ {print $1; exit}')"
if [ "$old_ort" != "@rpath/libonnxruntime.dylib" ]; then
  install_name_tool -change "$old_ort" @rpath/libonnxruntime.dylib "$CAPI"
fi
if ! otool -l "$CAPI" | grep -q '@loader_path'; then
  install_name_tool -add_rpath @loader_path "$CAPI"
fi

old_capi="$(otool -L "$EXE" | awk '/libsherpa-onnx-c-api/ {print $1; exit}')"
if [ "$old_capi" != "@rpath/libsherpa-onnx-c-api.dylib" ]; then
  install_name_tool -change "$old_capi" @rpath/libsherpa-onnx-c-api.dylib "$EXE"
fi

./scripts/package-app.sh
