#!/usr/bin/env bash
# Checks everything scripts/build-app.sh needs and lists every missing piece before any work starts.
# Exit status 0 when the Mac can build Läsa, 1 otherwise.
set -uo pipefail
cd "$(dirname "$0")/.."

MIN_MACOS=14
MIN_SWIFT=6.0
MIN_FREE_GB=2

failures=0
ok() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n    → %s\n' "$1" "$2"; failures=$((failures + 1)); }

echo "Checking build requirements…"

if [ "$(uname -s)" != Darwin ]; then
  fail "macOS" "Läsa is a macOS app and can only be built on a Mac."
  exit 1
fi

# hw.optional.arm64 is also 1 when this shell runs under Rosetta, unlike `uname -m`.
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
  ok "Apple silicon Mac"
else
  fail "Apple silicon Mac (M1 or later)" "Intel Macs are not supported: the bundled speech engine is arm64 only."
fi

macos="$(sw_vers -productVersion)"
if [ "${macos%%.*}" -ge "$MIN_MACOS" ]; then
  ok "macOS $macos"
else
  fail "macOS $MIN_MACOS or later (found $macos)" "Update macOS in System Settings → General → Software Update."
fi

if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  fail "Swift toolchain (Xcode Command Line Tools)" "Run: xcode-select --install"
else
  swift_version="$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -n 1)"
  if [ -z "$swift_version" ]; then
    fail "Swift $MIN_SWIFT or later (could not read the version)" "Run: xcode-select --install, or update Xcode."
  elif [ "$(printf '%s\n%s\n' "$MIN_SWIFT" "$swift_version" | sort -V | head -n 1)" = "$MIN_SWIFT" ]; then
    ok "Swift $swift_version"
  else
    fail "Swift $MIN_SWIFT or later (found $swift_version)" "Update the Command Line Tools in Software Update, or install the latest Xcode."
  fi
fi

missing_tools=()
for tool in curl tar install_name_tool otool codesign ditto hdiutil; do
  command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
done
if [ ${#missing_tools[@]} -eq 0 ]; then
  ok "Build tools (curl, tar, install_name_tool, otool, codesign, ditto, hdiutil)"
else
  fail "Build tools: missing ${missing_tools[*]}" "Run: xcode-select --install"
fi

free_kb="$(df -Pk . | awk 'NR == 2 { print $4 }')"
free_gb=$((free_kb / 1024 / 1024))
if [ "$free_gb" -ge "$MIN_FREE_GB" ]; then
  ok "Free disk space (${free_gb} GB)"
else
  fail "At least ${MIN_FREE_GB} GB free disk space (found ${free_gb} GB)" "Free up space; the build needs room for the voices, the app, the zip and the disk image."
fi

# The speech engine and voices (~300 MB) are downloaded once into Vendor/.
needs_download=0
[ -d Vendor/sherpa-onnx ] || needs_download=1
for v in alma lisa nst; do
  [ -d "Vendor/piper/vits-piper-sv_SE-${v}-medium" ] || needs_download=1
done
if [ "$needs_download" = 0 ]; then
  ok "Speech engine and voices already downloaded (Vendor/)"
elif curl -fsI --max-time 15 https://github.com >/dev/null 2>&1; then
  ok "Internet access to github.com (first build downloads ~300 MB)"
else
  fail "Internet access to github.com" "The first build downloads the speech engine and voices from GitHub. Connect to the internet and retry."
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures requirement(s) missing. Fix the items marked ✗ and run the build again."
  exit 1
fi
echo "All requirements met."
