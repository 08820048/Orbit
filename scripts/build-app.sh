#!/bin/zsh
# Builds build/Orbit.app (ad-hoc signed). Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
# SwiftUI macros need a full Xcode, not just the Command Line Tools. Set DEVELOPER_DIR to pick one;
# otherwise use whatever xcode-select points at.
if [[ -n "${DEVELOPER_DIR:-}" ]]; then export DEVELOPER_DIR; fi
CONFIG="${1:-release}"
[[ "$CONFIG" == "debug" || "$CONFIG" == "release" ]] || { echo "Usage: $0 [debug|release]"; exit 64; }

# Version: Packaging/VERSION is the marketing version; the build number is the commit count (always increases).
VERSION="${VERSION:-$(tr -d '[:space:]' < Packaging/VERSION)}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# Updates: the appcast is a release asset, so "latest" always points at the newest version's feed.
# The public key pairs with the private key in the maintainer's keychain (account "orbit"); see docs/RELEASING.md.
FEED_URL="${FEED_URL:-https://github.com/08820048/Orbit/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-Zr3hHUFdHvigb96LtdVJc8Vi4LOCWm/OsmzCKSBB4Mc=}"

# Release builds are universal (Apple silicon + Intel); debug builds are for this machine only.
ARCH_FLAGS=()
if [[ "$CONFIG" == "release" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --product Orbit
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"
APP=build/Orbit.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Orbit" "$APP/Contents/MacOS/Orbit"
cp -R "$BIN_DIR"/Orbit_OrbitApp.bundle "$APP/Contents/Resources/"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sparkle (software updates) lives next to the executable; point the executable at it.
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE_FW" ]] || { echo "Missing $SPARKLE_FW (run swift build first)"; exit 65; }
mkdir -p "$APP/Contents/Frameworks"
/usr/bin/ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Orbit" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
  <key>CFBundleIdentifier</key><string>app.orbit.mac</string>
  <key>CFBundleName</key><string>Orbit</string>
  <key>CFBundleDisplayName</key><string>Orbit</string>
  <key>CFBundleExecutable</key><string>Orbit</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUSendProfileInfo</key><false/>
</dict></plist>
PLIST
# Signing: set CODESIGN_IDENTITY (a Developer ID Application identity, ideally its SHA-1) for a release build with the
# hardened runtime; otherwise the app is ad-hoc signed and only runs on this machine.
if [[ -n "${CODESIGN_IDENTITY:-}" && "${CODESIGN_IDENTITY}" != "-" ]]; then
  sign() { codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$@" >/dev/null; }
  # Inside-out: nested code first, the app last (no --deep).
  FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  if [[ -d "$FW" ]]; then
    for xpc in "$FW"/XPCServices/*.xpc(N); do sign --preserve-metadata=entitlements "$xpc"; done
    sign "$FW/Updater.app"
    sign "$FW/Autoupdate"
    sign "$APP/Contents/Frameworks/Sparkle.framework"
  fi
  for bundle in "$APP"/Contents/Resources/*.bundle(N); do sign "$bundle"; done
  sign "$APP"
  codesign --verify --deep --strict "$APP"
  echo "Signed with Developer ID, version $VERSION ($BUILD)"
else
  codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
