#!/bin/zsh

# The macOS 26 Command Line Tools can occasionally contain an SDK produced by
# the immediately preceding patch version of Swift. The compiler rejects that
# SDK unless told its interface version. Keep the workaround local and apply it
# only when the two versions actually differ.
posture_configure_swift_toolchain() {
    local project_root="$1"
    local sdk_path
    local sdk_interfaces
    local sdk_version_line
    local sdk_version_text
    local sdk_compiler_version
    local compiler_version_line
    local compiler_version_text
    local compiler_version
    local compiler_version_output

    export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
    mkdir -p "$CLANG_MODULE_CACHE_PATH"

    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
    sdk_interfaces=("$sdk_path"/usr/lib/swift/Swift.swiftmodule/*-apple-macos.swiftinterface(N))

    typeset -ga POSTURE_SWIFT_FLAGS
    POSTURE_SWIFT_FLAGS=(-module-cache-path "$CLANG_MODULE_CACHE_PATH")

    if (( ${#sdk_interfaces[@]} > 0 )); then
        sdk_version_line="$(sed -n '2p' "$sdk_interfaces[1]")"
        sdk_version_text="${sdk_version_line#*Apple Swift version }"
        sdk_compiler_version="${sdk_version_text%% *}"

        compiler_version_output="$(swiftc --version 2>&1)"
        compiler_version_line="$(sed -n '/Apple Swift version/{p;q;}' <<< "$compiler_version_output")"
        compiler_version_text="${compiler_version_line#*Apple Swift version }"
        compiler_version="${compiler_version_text%% *}"

        if [[ -n "$sdk_compiler_version" && "$compiler_version" != "$sdk_compiler_version" ]]; then
            POSTURE_SWIFT_FLAGS+=(
                -Xfrontend -interface-compiler-version
                -Xfrontend "$sdk_compiler_version"
            )
        fi
    fi

    typeset -gx POSTURE_TARGET_TRIPLE="$(uname -m)-apple-macosx13.0"
}
