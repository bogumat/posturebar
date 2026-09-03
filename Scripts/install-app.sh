#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
USER_APPLICATIONS="${POSTUREBAR_INSTALL_DIR:-$HOME/Applications}"
DESTINATION="$USER_APPLICATIONS/PostureBar.app"
SOURCE="$PROJECT_ROOT/.build/PostureBar.app"
LAUNCH_SERVICES_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$SOURCE" ]]; then
    print -u2 "PostureBar.app has not been built. Run 'make app' first."
    exit 1
fi

mkdir -p "$USER_APPLICATIONS"
ditto "$SOURCE" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
"$LAUNCH_SERVICES_REGISTER" -f "$DESTINATION"
chmod +x "$PROJECT_ROOT"/Raycast/*.sh

echo "$DESTINATION"
