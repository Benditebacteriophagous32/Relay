#!/bin/bash
# Build Relay into a distributable, AD-HOC-signed .app + .dmg for GitHub Releases.
#
# NOT notarized and tied to no Apple Developer account — like most open-source Mac
# apps. On first launch users approve it once via System Settings → Privacy &
# Security → "Open Anyway" (or right-click → Open on older macOS). Auto-update still
# works: Sparkle verifies the EdDSA-signed appcast, independent of Apple notarization.
#
# Usage:  scripts/release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DEV="/Applications/Xcode.app/Contents/Developer"
DIST="$ROOT/dist"

echo "→ Building universal Go helper (arm64 + amd64)…"
( cd relay-helper
  CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -o relay-helper.arm64 .
  CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -o relay-helper.amd64 .
  lipo -create -output relay-helper relay-helper.arm64 relay-helper.amd64
  rm -f relay-helper.arm64 relay-helper.amd64 )

echo "→ Generating project + building Release…"
xcodegen generate >/dev/null
DEVELOPER_DIR="$DEV" xcodebuild -project Relay.xcodeproj -scheme Relay \
  -configuration Release -derivedDataPath build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build >/dev/null

APP_SRC="build/Build/Products/Release/Relay.app"
[ -d "$APP_SRC" ] || { echo "error: build product missing" >&2; exit 1; }
rm -rf "$DIST"; mkdir -p "$DIST"
APP="$DIST/Relay.app"
cp -R "$APP_SRC" "$APP"

echo "→ Bundling helper + ad-hoc signing (inside-out)…"
mkdir -p "$APP/Contents/Resources"
cp relay-helper/relay-helper "$APP/Contents/Resources/relay-helper"
codesign --force --sign - "$APP/Contents/Resources/relay-helper"
if [ -d "$APP/Contents/Frameworks" ]; then
  find "$APP/Contents/Frameworks" \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" -o -name "*.dylib" \) -print0 \
    | while IFS= read -r -d '' n; do codesign --force --sign - "$n"; done
  find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 \
    | while IFS= read -r -d '' fw; do codesign --force --sign - "$fw"; done
fi
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "  ad-hoc signature ok"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0")

echo "→ Zipping (Sparkle update artifact)…"
ZIP="$DIST/Relay.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "→ Building drag-to-Applications DMG…"
DMG="$DIST/Relay.dmg"
STAGING="$DIST/dmg-staging"; rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/Relay.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Relay" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

# --- Sparkle appcast (EdDSA-signed; private key lives in your Keychain) -------
GENAPPCAST="${GENAPPCAST:-$ROOT/.sparkle-tools/bin/generate_appcast}"
if [ ! -x "$GENAPPCAST" ]; then
  GENAPPCAST=$(find "$ROOT/build" -name generate_appcast -type f 2>/dev/null | head -1)
fi
APPCAST="$DIST/appcast.xml"
if [ -n "${GENAPPCAST:-}" ] && [ -x "$GENAPPCAST" ]; then
  echo "→ Generating signed appcast…"
  APPCAST_SRC="$DIST/appcast-src"; rm -rf "$APPCAST_SRC"; mkdir -p "$APPCAST_SRC"
  cp "$ZIP" "$APPCAST_SRC/"
  "$GENAPPCAST" --download-url-prefix "https://github.com/hatimhtm/Relay/releases/download/v$VERSION/" "$APPCAST_SRC"
  mv "$APPCAST_SRC/appcast.xml" "$APPCAST"
  rm -rf "$APPCAST_SRC"
else
  echo "⚠ generate_appcast not found — skipping appcast (auto-update won't update without it)." >&2
  echo "  Download the Sparkle tools into .sparkle-tools/ or set GENAPPCAST — see RELEASE.md." >&2
  APPCAST=""
fi

echo "✓ Done."
echo "  App: $APP   (ad-hoc signed, not notarized)"
echo "  DMG (direct download): $DMG"
echo "  Zip (Sparkle update):  $ZIP"
[ -n "$APPCAST" ] && echo "  Appcast (auto-update): $APPCAST"
echo
echo "Publish the release with the GitHub CLI (tag MUST be v$VERSION to match the appcast URLs):"
if [ -n "$APPCAST" ]; then
  echo "  gh release create v$VERSION \"$DMG\" \"$ZIP\" \"$APPCAST\" --title \"Relay v$VERSION\" --notes \"…\""
else
  echo "  gh release create v$VERSION \"$DMG\" \"$ZIP\" --title \"Relay v$VERSION\" --notes \"…\""
fi
echo "Bump MARKETING_VERSION + CURRENT_PROJECT_VERSION in project.yml before each release."
