#!/usr/bin/env bash
# Downloads the sherpa-onnx runtime and the Swedish Piper voices into Vendor/.
# Idempotent: existing directories are left untouched.
set -euo pipefail
cd "$(dirname "$0")/.."

SHERPA_VERSION=1.13.8
SHERPA_NAME="sherpa-onnx-v${SHERPA_VERSION}-osx-arm64-shared"
VOICES=(alma lisa nst)

mkdir -p Vendor/piper

if [ ! -d Vendor/sherpa-onnx ]; then
  echo "Fetching ${SHERPA_NAME}"
  curl -fL "https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/${SHERPA_NAME}.tar.bz2" | tar -xj -C Vendor
  mv "Vendor/${SHERPA_NAME}" Vendor/sherpa-onnx
fi

for v in "${VOICES[@]}"; do
  name="vits-piper-sv_SE-${v}-medium"
  if [ ! -d "Vendor/piper/${name}" ]; then
    echo "Fetching ${name}"
    curl -fL "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${name}.tar.bz2" | tar -xj -C Vendor/piper
  fi
done
