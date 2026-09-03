#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Start PostureBar
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ✅
# @raycast.packageName PostureBar
# @raycast.description Start or resume posture monitoring

set -euo pipefail

POSTUREBAR_APP="${POSTUREBAR_APP_PATH:-$HOME/Applications/PostureBar.app}"

if [[ ! -d "$POSTUREBAR_APP" ]]; then
    print -u2 "PostureBar is not installed at $POSTUREBAR_APP"
    exit 1
fi

/usr/bin/open "posturebar://resume"
