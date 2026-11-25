#!/bin/zsh
# Builds build/Orbit.app (ad-hoc signed). Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Orbit
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP=build/Orbit.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Orbit" "$APP/Contents/MacOS/Orbit"
cp -R "$BIN_DIR"/Orbit_OrbitApp.bundle "$APP/Contents/Resources/"
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
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
