#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Posture Project
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🧑‍💻
# @raycast.packageName PostureBar
# @raycast.description Open the Posture project in a new Visual Studio Code window

set -euo pipefail

PROJECT_PATH="${POSTUREBAR_PROJECT_PATH:-${0:A:h:h}}"
VSCODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"

if [[ ! -d "$PROJECT_PATH" ]]; then
    print -u2 "Project not found at $PROJECT_PATH"
    exit 1
fi

if [[ ! -x "$VSCODE_CLI" ]]; then
    print -u2 "Visual Studio Code is not installed in /Applications"
    exit 1
fi

"$VSCODE_CLI" --new-window "$PROJECT_PATH"
