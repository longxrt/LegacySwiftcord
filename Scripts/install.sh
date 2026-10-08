#!/bin/zsh
# Builds an optimized Release of Swiftcord and installs it to /Applications.
# Usage: Scripts/install.sh
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "Building Release…"
xcodebuild build \
	-project Swiftcord.xcodeproj -scheme Swiftcord -configuration Release \
	-derivedDataPath "$BUILD_DIR" -destination 'platform=macOS,arch=arm64' \
	-quiet

APP="$BUILD_DIR/Build/Products/Release/Swiftcord.app"
codesign --verify --deep --strict "$APP"

if pgrep -f "/Applications/Swiftcord.app/Contents/MacOS/Swiftcord" >/dev/null; then
	echo "Quitting running Swiftcord…"
	osascript -e 'quit app id "io.cryptoalgo.swiftcord.sequoia"' || true
	sleep 2
fi

rm -rf /Applications/Swiftcord.app
ditto "$APP" /Applications/Swiftcord.app
echo "Installed to /Applications/Swiftcord.app"
open /Applications/Swiftcord.app
