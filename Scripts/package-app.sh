#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_PATH="$PROJECT_ROOT/.build/PostureBar.app"
DIST_PATH="$PROJECT_ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/App/Info.plist")"
ARCHIVE_PATH="$DIST_PATH/PostureBar-$VERSION-universal.zip"

POSTUREBAR_ARCHS="arm64 x86_64" zsh "$PROJECT_ROOT/Scripts/build-app.sh"

mkdir -p "$DIST_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

pushd "$DIST_PATH" >/dev/null
shasum -a 256 "${ARCHIVE_PATH:t}" > "${ARCHIVE_PATH:t}.sha256"
popd >/dev/null

echo "$ARCHIVE_PATH"
