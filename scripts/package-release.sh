#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
if [ "${PIKA_SKIP_BUILD:-0}" != "1" ]; then ./scripts/build-app.sh; fi
codesign --verify --deep --strict "dist/Pika Dots.app"
lipo -verify_arch arm64 "dist/Pika Dots.app/Contents/MacOS/PikaDots"
lipo -verify_arch x86_64 "dist/Pika Dots.app/Contents/MacOS/PikaDots"
# Explicit app-only packaging: local keys and personal companions stay outside.
ditto -c -k --sequesterRsrc --keepParent "dist/Pika Dots.app" "dist/PikaDots-0.8.0-universal.zip"
(cd dist && shasum -a 256 "PikaDots-0.8.0-universal.zip" > "PikaDots-0.8.0-universal.zip.sha256")
printf 'Packaged dist/PikaDots-0.8.0-universal.zip\n'
