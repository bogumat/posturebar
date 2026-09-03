#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stop PostureBar
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ⏹
# @raycast.packageName PostureBar
# @raycast.description Stop posture monitoring and release the camera

set -euo pipefail

if /usr/bin/pgrep -x PostureBar >/dev/null; then
    /usr/bin/open "posturebar://quit"
fi
