#!/bin/zsh
# Renders Packaging/AppIcon.svg (+ the simplified AppIconSmall.svg for 16-64 px) into Packaging/AppIcon.icns.
# Needs Google Chrome (headless, for a transparent background) and iconutil. Override the browser with CHROME=...
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[[ -x "$CHROME" ]] || { echo "Chrome not found at: $CHROME (set CHROME=...)"; exit 1; }
WORK="$(mktemp -d)"; SET="$WORK/AppIcon.iconset"; mkdir -p "$SET"

render() { # svg size out
  local page="$WORK/page-$2.html"
  echo "<html><body style=\"margin:0;background:transparent\"><img src=\"file://$PWD/Packaging/$1\" style=\"display:block;width:$2px;height:$2px\"></body></html>" > "$page"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size="$2,$2" --screenshot="$3" "file://$page" >/dev/null 2>&1
}

typeset -A files=(
  [16]=icon_16x16.png [32]=icon_16x16@2x.png [64]=icon_32x32@2x.png
  [128]=icon_128x128.png [256]=icon_128x128@2x.png [512]=icon_256x256@2x.png [1024]=icon_512x512@2x.png
)
for size in 16 32 64; do render AppIconSmall.svg $size "$SET/${files[$size]}"; done
for size in 128 256 512 1024; do render AppIcon.svg $size "$SET/${files[$size]}"; done
cp "$SET/icon_16x16@2x.png" "$SET/icon_32x32.png"      # 32 px is shared by 16@2x and 32@1x
cp "$SET/icon_128x128@2x.png" "$SET/icon_256x256.png"   # 256 px
cp "$SET/icon_256x256@2x.png" "$SET/icon_512x512.png"   # 512 px
iconutil -c icns "$SET" -o Packaging/AppIcon.icns
echo "Wrote Packaging/AppIcon.icns"
