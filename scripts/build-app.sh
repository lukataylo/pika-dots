#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="$PWD/dist/Pika Dots.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PikaDots" "$APP/Contents/MacOS/PikaDots"
for bundle in "$BIN_DIR"/*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PikaDots</string>
<key>CFBundleIdentifier</key><string>dev.pikadots.app</string>
<key>CFBundleName</key><string>Pika Dots</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.11.0</string>
<key>CFBundleVersion</key><string>15</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Talk to your cat instead of typing. Audio is transcribed and not stored.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Turns what you say to your cat into its purpose or question.</string>
<key>NSAppleEventsUsageDescription</key><string>Focus can close a YouTube tab after warning you, if you turn that on.</string>
</dict></plist>
PLIST
# Hardened runtime blocks Apple Events (closing a YouTube tab) and the microphone (talking to a cat) without these.
ENTITLEMENTS="$PWD/.build/PikaDots.entitlements"
cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.automation.apple-events</key><true/><key>com.apple.security.device.audio-input</key><true/></dict></plist>
ENT
if [ -n "${PIKA_SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$PIKA_SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi
printf 'Built %s\n' "$APP"
