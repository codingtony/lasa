#!/usr/bin/env bash
# Builds build/Läsa.app (self-contained, ad-hoc signed), build/Läsa.zip and build/Läsa.dmg.
# Optional environment: VERSION (e.g. 1.2.0) and BUILD (e.g. a CI run number) are written into
# Info.plist as CFBundleShortVersionString and CFBundleVersion.
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
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi
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

# install_name_tool invalidates signatures; arm64 refuses to load unsigned code.
codesign --force -s - "$FW"/*.dylib
codesign --force -s - "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"

# Disk image: the app next to an Applications shortcut, so installing is a single drag.
STAGE=build/dmg-stage
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Läsa.app"
ln -s /Applications "$STAGE/Applications"
# hdiutil occasionally fails with "Resource busy" on CI machines; a retry is enough.
for attempt in 1 2 3; do
  if hdiutil create -volname "Läsa" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null; then
    break
  fi
  [ "$attempt" = 3 ] && exit 1
  echo "hdiutil failed (attempt $attempt), retrying"
  sleep 5
done
rm -rf "$STAGE"

echo "Built $APP ($(du -sh "$APP" | cut -f1)), $ZIP and $DMG ($(du -sh "$DMG" | cut -f1))"
