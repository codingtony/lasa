#!/usr/bin/env bash
# Installs (or updates) the latest release of Läsa:
#   curl -fsSL https://raw.githubusercontent.com/codingtony/lasa/main/scripts/install.sh | bash
#
# Installs into /Applications, or ~/Applications when /Applications is not writable. No sudo.
# Overrides, mainly for testing: LASA_ZIP_URL (zip to install, file:// works too) and
# LASA_INSTALL_DIR (destination folder).
set -euo pipefail

# Everything runs from main(), so a download cut off halfway through `curl | bash` runs nothing.
main() {
  local zip_url="${LASA_ZIP_URL:-https://github.com/codingtony/lasa/releases/latest/download/Lasa.zip}"

  if [ "$(uname -s)" != Darwin ]; then
    echo "Läsa is a macOS app; this Mac is required." >&2
    exit 1
  fi
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" != 1 ]; then
    echo "Läsa needs a Mac with Apple silicon (M1 or later)." >&2
    exit 1
  fi
  local macos
  macos="$(sw_vers -productVersion)"
  if [ "${macos%%.*}" -lt 14 ]; then
    echo "Läsa needs macOS 14 or later (this Mac has $macos)." >&2
    exit 1
  fi

  local dest="${LASA_INSTALL_DIR:-}"
  if [ -z "$dest" ]; then
    if [ -w /Applications ]; then dest=/Applications; else dest="$HOME/Applications"; fi
  fi
  mkdir -p "$dest"

  # Global (not local): the EXIT trap runs after main has returned.
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' EXIT

  echo "Downloading Läsa (about 200 MB)…"
  curl -fL --progress-bar "$zip_url" -o "$tmp/Lasa.zip"
  ditto -x -k "$tmp/Lasa.zip" "$tmp/unpacked"

  local app
  app="$(find "$tmp/unpacked" -maxdepth 1 -name '*.app' -print -quit)"
  if [ -z "$app" ]; then
    echo "The download did not contain the app." >&2
    exit 1
  fi
  local name
  name="$(basename "$app")"

  if pgrep -x Lasa >/dev/null; then
    echo "Quitting the running Läsa…"
    pkill -x Lasa || true
    sleep 1
  fi

  rm -rf "${dest:?}/$name"
  ditto "$app" "$dest/$name"
  # curl does not mark downloads as quarantined, but clear it in case the zip came from a browser.
  # /usr/bin/xattr explicitly: Homebrew's Python xattr can shadow it and lacks -r.
  /usr/bin/xattr -dr com.apple.quarantine "$dest/$name" 2>/dev/null || true

  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$dest/$name/Contents/Info.plist" 2>/dev/null || echo "?")"
  echo "Installed Läsa $version in $dest."
  if [ -z "${LASA_INSTALL_DIR:-}" ]; then
    open "$dest/$name"
  fi
}

main "$@"
