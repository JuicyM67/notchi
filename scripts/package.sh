#!/bin/bash
# Bygger Notchi.app (med hooken inbakad) i build/. Används både lokalt och i GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Bygger (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "▸ Paketerar Notchi.app…"
APP="build/Notchi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Notchi" "$APP/Contents/MacOS/Notchi"
cp "$BIN/notchi-hook" "$APP/Contents/MacOS/notchi-hook"
cp brand/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
VERSION="${NOTCHI_VERSION:-0.1.0}"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Notchi</string>
  <key>CFBundleDisplayName</key><string>Notchi</string>
  <key>CFBundleIdentifier</key><string>local.notchi.app</string>
  <key>CFBundleExecutable</key><string>Notchi</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${GITHUB_RUN_NUMBER:-1}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Notchi lyssnar när du håller inne snabbtangenten.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Notchi gör om det du säger till text.</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "✓ build/Notchi.app"
