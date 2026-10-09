#!/usr/bin/env bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode.app),
# Swift Testing lives outside the default search paths, so pass them explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

# `swift test` also builds the app target, which links sherpa-onnx from Vendor/ (no-op once downloaded).
./scripts/fetch-vendor.sh

flags=()
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
  dev=/Library/Developer/CommandLineTools/Library/Developer
  flags=(-Xswiftc -F -Xswiftc "$dev/Frameworks"
         -Xlinker -rpath -Xlinker "$dev/Frameworks"
         -Xlinker -rpath -Xlinker "$dev/usr/lib")
fi
# ${flags[@]+…}: macOS's bash 3.2 treats an empty array as unbound under `set -u` (machines with Xcode).
swift test ${flags[@]+"${flags[@]}"} "$@"
