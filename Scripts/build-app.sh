#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/Scripts/swift-toolchain.sh"
posture_configure_swift_toolchain "$PROJECT_ROOT"

BIN_PATH="$PROJECT_ROOT/.build/app-bin"
APP_PATH="$PROJECT_ROOT/.build/PostureBar.app"
SOURCES=("$PROJECT_ROOT"/Sources/PostureBar/*.swift)
ARCHITECTURE_LIST="${POSTUREBAR_ARCHS:-$(uname -m)}"
ARCHITECTURES=("${(@s: :)ARCHITECTURE_LIST}")
BUILT_BINARIES=()

mkdir -p "$BIN_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"

for architecture in "${ARCHITECTURES[@]}"; do
    architecture_binary="$BIN_PATH/PostureBar-$architecture"
    swiftc \
        -O \
        -target "$architecture-apple-macosx13.0" \
        "${POSTURE_SWIFT_FLAGS[@]}" \
        -o "$architecture_binary" \
        "${SOURCES[@]}" \
        -framework AppKit \
        -framework AVFoundation \
        -framework CoreAudio \
        -framework Vision
    BUILT_BINARIES+=("$architecture_binary")
done

if (( ${#BUILT_BINARIES[@]} == 1 )); then
    cp "$BUILT_BINARIES[1]" "$APP_PATH/Contents/MacOS/PostureBar"
else
    lipo -create "${BUILT_BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/PostureBar"
fi
cp "$PROJECT_ROOT/App/Info.plist" "$APP_PATH/Contents/Info.plist"

plutil -lint "$APP_PATH/Contents/Info.plist"
codesign --force --sign - "$APP_PATH"

echo "$APP_PATH"
