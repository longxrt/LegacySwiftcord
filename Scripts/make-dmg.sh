#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) Release of Swiftcord and packages it as
# dist/Swiftcord-Sequoia-<version>.dmg for distribution.
# Usage: Scripts/make-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Building universal Release…"
xcodebuild build \
	-project Swiftcord.xcodeproj -scheme Swiftcord -configuration Release \
	-derivedDataPath "$WORK/build" -destination 'generic/platform=macOS' \
	ONLY_ACTIVE_ARCH=NO -quiet

APP="$WORK/build/Build/Products/Release/Swiftcord.app"
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$APP/Contents/Info.plist")
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/Swiftcord")"

STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Swiftcord.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/First Launch - Read Me.txt" <<EOF
Swiftcord Sequoia Edition $VERSION
Requires macOS $MIN_OS or later (Apple Silicon or Intel).

INSTALL
Drag Swiftcord into the Applications folder.

FIRST LAUNCH
This build is not notarized by Apple, so macOS blocks it the first time:
1. Open Swiftcord. macOS says it can't be opened. Click Done.
2. Open System Settings > Privacy & Security.
3. Scroll down and click "Open Anyway" next to the Swiftcord message.
4. Confirm with your password. After this it opens normally.

NOTE
Swiftcord logs in with your Discord account. Third-party clients aren't
permitted by Discord's Terms of Service; use at your own risk.

Source: https://github.com/longxrt/Swiftcord/tree/sequoia-legacy
EOF

mkdir -p dist
OUT="dist/Swiftcord-Sequoia-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -volname "Swiftcord Sequoia" -srcfolder "$STAGE" -fs HFS+ \
	-format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null

echo "Created $OUT ($(du -h "$OUT" | cut -f1))"
echo "SHA-256: $(shasum -a 256 "$OUT" | cut -d' ' -f1)"
