#!/bin/bash
# Build the Go helper + the native SwiftUI app (Relay), bundle the helper
# inside it, sign, install to /Applications, and launch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DEV="/Applications/Xcode.app/Contents/Developer"
ENT="$ROOT/RelayNative/RelayNative.entitlements"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

IDENTITY=$(security find-identity -v -p codesigning \
  | grep "Apple Development:" | head -1 | awk '{print $2}')

echo "→ Building universal Go helper (arm64 + amd64)…"
( cd relay-helper
  CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -o relay-helper.arm64 .
  CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -o relay-helper.amd64 .
  lipo -create -output relay-helper relay-helper.arm64 relay-helper.amd64
  rm -f relay-helper.arm64 relay-helper.amd64 )

echo "→ Quitting any running Relay…"
osascript -e 'quit app "Relay"' >/dev/null 2>&1 || true
osascript -e 'quit app "RelayNative"' >/dev/null 2>&1 || true
pkill -f "/Applications/Relay.app" >/dev/null 2>&1 || true
pkill -f "relay-helper" >/dev/null 2>&1 || true
sleep 1

echo "→ Generating + building app…"
xcodegen generate >/dev/null
DEVELOPER_DIR="$DEV" xcodebuild -project Relay.xcodeproj -scheme Relay \
  -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="build/Build/Products/Release/Relay.app"
[ -d "$APP" ] || { echo "build product missing" >&2; exit 1; }

echo "→ Bundling helper + signing…"
mkdir -p "$APP/Contents/Resources"
cp relay-helper/relay-helper "$APP/Contents/Resources/relay-helper"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP/Contents/Resources/relay-helper"
# Sign any embedded frameworks (e.g. Sparkle) before the app, deep, so the
# outer signature is valid under the hardened runtime.
if [ -d "$APP/Contents/Frameworks" ]; then
  find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 | while IFS= read -r -d '' fw; do
    codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$fw"
  done
fi
codesign --force --options runtime --timestamp=none --deep --entitlements "$ENT" --sign "$IDENTITY" "$APP"

echo "→ Installing + launching…"
rm -rf /Applications/Relay.app /Applications/RelayNative.app
cp -R "$APP" /Applications/Relay.app
open -n /Applications/Relay.app
echo "✓ launched"
