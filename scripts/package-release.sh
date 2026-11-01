#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh
codesign --verify --deep --strict "dist/Pika Dots.app"
lipo -verify_arch arm64 x86_64 "dist/Pika Dots.app/Contents/MacOS/PikaDots"
# Explicit app-only packaging: local keys and personal companions stay outside.
ditto -c -k --sequesterRsrc --keepParent "dist/Pika Dots.app" "dist/PikaDots-0.8.0-universal.zip"
shasum -a 256 "dist/PikaDots-0.8.0-universal.zip" > "dist/PikaDots-0.8.0-universal.zip.sha256"
printf 'Packaged dist/PikaDots-0.8.0-universal.zip\n'
