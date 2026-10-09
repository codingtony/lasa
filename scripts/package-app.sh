#!/usr/bin/env bash
# Stamps the version into an assembled build/Läsa.app, signs it ad hoc, and packs build/Läsa.zip
# and build/Läsa.dmg. build-app.sh runs it after assembling the app; CI runs it on its own to
# release the app already built for the same commit.
# Optional environment: VERSION (e.g. 1.2.0) and BUILD (e.g. a CI run number) are written into
# Info.plist as CFBundleShortVersionString and CFBundleVersion.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Läsa.app"
ZIP="build/Läsa.zip"
DMG="build/Läsa.dmg"
if [ ! -d "$APP" ]; then
  echo "$APP not found: run scripts/build-app.sh" >&2
  exit 1
fi
rm -f "$ZIP" "$DMG"

if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi

# install_name_tool and Info.plist edits invalidate signatures; arm64 refuses to load unsigned code.
codesign --force -s - "$APP/Contents/Frameworks"/*.dylib
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
