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
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST
# Signing: set CODESIGN_IDENTITY (a Developer ID Application identity, ideally its SHA-1) for a release build with the
# hardened runtime; otherwise the app is ad-hoc signed and only runs on this machine.
if [[ -n "${CODESIGN_IDENTITY:-}" && "${CODESIGN_IDENTITY}" != "-" ]]; then
  sign() { codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$@" >/dev/null; }
  # Inside-out: nested code first, the app last (no --deep).
  find "$APP/Contents" -type d \( -name "*.framework" -o -name "*.bundle" -o -name "*.xpc" \) -prune -print0 | while IFS= read -r -d '' nested; do sign "$nested"; done
  sign "$APP"
  codesign --verify --deep --strict "$APP"
  echo "Signed with Developer ID, version $VERSION ($BUILD)"
else
  codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
