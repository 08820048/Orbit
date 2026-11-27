#!/bin/zsh
# Builds a styled disk image: dark Orbit background, the app on the left, the Applications shortcut on the right.
# Usage: scripts/make-dmg.sh <Orbit.app> <out.dmg> <volume name>
# Needs Finder (AppleScript) to lay out the window; the first run may ask for permission to control Finder.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"; OUT="$2"; VOL="$3"
BG="Packaging/DMGBackground.tiff"
[[ -f "$BG" ]] || swift scripts/make-dmg-background.swift "$BG"

WORK="$(mktemp -d)"; RW="$WORK/rw.dmg"
trap 'hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1 || true

hdiutil create -size 80m -fs HFS+ -volname "$VOL" -ov "$RW" >/dev/null
hdiutil attach "$RW" -noverify -noautoopen >/dev/null
MNT="/Volumes/$VOL"
/usr/bin/ditto "$APP" "$MNT/Orbit.app"
ln -s /Applications "$MNT/Applications"
mkdir "$MNT/.background"; cp "$BG" "$MNT/.background/background.tiff"

# Window 660 x 400 content area; icon centres match scripts/make-dmg-background.swift.
osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set background picture of opts to file ".background:background.tiff"
    set position of item "Orbit.app" of container window to {180, 196}
    set position of item "Applications" of container window to {480, 196}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
sync; sleep 2
chmod -Rf go-w "$MNT" 2>/dev/null || true
hdiutil detach "$MNT" >/dev/null
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
echo "Built $OUT"
