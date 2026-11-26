#!/bin/zsh
# Builds a signed, notarized, stapled Orbit-<version>.dmg in build/release/.
#
#   CODESIGN_IDENTITY="<Developer ID Application identity or its SHA-1>" \
#   NOTARY_PROFILE="<notarytool keychain profile>" \
#   scripts/release.sh
#
# One-time setup of the notary profile:
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-specific password>
# See docs/RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CODESIGN_IDENTITY:?set CODESIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile}"

VERSION="${VERSION:-$(tr -d '[:space:]' < Packaging/VERSION)}"
OUT="build/release"
DMG="$OUT/Orbit-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Building and signing Orbit $VERSION"
CODESIGN_IDENTITY="$CODESIGN_IDENTITY" VERSION="$VERSION" scripts/build-app.sh release
codesign -dv --verbose=2 build/Orbit.app 2>&1 | grep -E "Authority=Developer ID|flags=|TeamIdentifier"
lipo -archs build/Orbit.app/Contents/MacOS/Orbit

echo "==> Creating the disk image"
mkdir -p "$OUT"; rm -f "$DMG"
/usr/bin/ditto build/Orbit.app "$STAGE/Orbit.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Orbit $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG"

echo "==> Notarizing (this waits for Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
xcrun stapler staple build/Orbit.app
xcrun stapler validate build/Orbit.app

echo "==> Verifying with Gatekeeper"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
spctl --assess --type execute --verbose=4 build/Orbit.app

echo "==> Sparkle update archive and appcast"
# The archive is made from the stapled app. It is signed with the EdDSA key in the keychain (account "orbit").
REPO="${GITHUB_REPO:-08820048/Orbit}"
ZIP="$OUT/Orbit-$VERSION.zip"
BUILD="$(plutil -extract CFBundleVersion raw build/Orbit.app/Contents/Info.plist)"
rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build/Orbit.app "$ZIP"
SIGNATURE="$(.build/artifacts/sparkle/Sparkle/bin/sign_update --account "${SPARKLE_ACCOUNT:-orbit}" "$ZIP")"   # sparkle:edSignature="…" length="…"
PUB_DATE="$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')"
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Orbit</title>
    <item>
      <title>Orbit $VERSION</title>
      <link>https://github.com/$REPO/releases/tag/v$VERSION</link>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Orbit-$VERSION.zip" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML

echo
echo "Done. Upload these three files to the GitHub release v$VERSION:"
ls -lh "$DMG" "$ZIP" "$OUT/appcast.xml" | awk '{print "  " $5 "  " $9}'
