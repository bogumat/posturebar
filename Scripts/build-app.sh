#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/Scripts/swift-toolchain.sh"
posture_configure_swift_toolchain "$PROJECT_ROOT"

BIN_PATH="$PROJECT_ROOT/.build/app-bin"
APP_PATH="$PROJECT_ROOT/.build/PostureBar.app"
SOURCES=("$PROJECT_ROOT"/Sources/PostureBar/*.swift)

mkdir -p "$BIN_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"

swiftc \
    -O \
    -target "$POSTURE_TARGET_TRIPLE" \
    "${POSTURE_SWIFT_FLAGS[@]}" \
    -o "$BIN_PATH/PostureBar" \
    "${SOURCES[@]}" \
    -framework AppKit \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework Vision

cp "$BIN_PATH/PostureBar" "$APP_PATH/Contents/MacOS/PostureBar"
cp "$PROJECT_ROOT/App/Info.plist" "$APP_PATH/Contents/Info.plist"

plutil -lint "$APP_PATH/Contents/Info.plist"
codesign --force --sign - "$APP_PATH"

echo "$APP_PATH"
