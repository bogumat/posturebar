#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/Scripts/swift-toolchain.sh"
posture_configure_swift_toolchain "$PROJECT_ROOT"

TEST_BIN_PATH="$PROJECT_ROOT/.build/test-bin"
mkdir -p "$TEST_BIN_PATH"

# Type-check the complete application, including all platform integrations.
swiftc \
    -typecheck \
    -target "$POSTURE_TARGET_TRIPLE" \
    "${POSTURE_SWIFT_FLAGS[@]}" \
    "$PROJECT_ROOT"/Sources/PostureBar/*.swift

# Run the core behavior checks independently of the UI and camera hardware.
swiftc \
    -O \
    -target "$POSTURE_TARGET_TRIPLE" \
    "${POSTURE_SWIFT_FLAGS[@]}" \
    -o "$TEST_BIN_PATH/ClassifierSmoke" \
    "$PROJECT_ROOT/Sources/PostureBar/CameraSelectionPolicy.swift" \
    "$PROJECT_ROOT/Sources/PostureBar/PostureClassifier.swift" \
    "$PROJECT_ROOT/Sources/PostureBar/PostureAlertPolicy.swift" \
    "$PROJECT_ROOT/Sources/PostureBar/PostureAlertTracker.swift" \
    "$PROJECT_ROOT/Sources/PostureBar/PostureHistoryStore.swift" \
    "$PROJECT_ROOT/Tests/Smoke/ClassifierSmoke.swift"

"$TEST_BIN_PATH/ClassifierSmoke"
