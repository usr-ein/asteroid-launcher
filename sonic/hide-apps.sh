#!/usr/bin/env bash
# Sonic Screwdriver: hide apps from the watch's app list, without uninstalling
# them.
#
#   sonic/hide-apps.sh                  hide Music, Calculator, Agenda and Settings
#   sonic/hide-apps.sh <id>...          hide these apps, by desktop file ID (asteroid-music)
#   sonic/hide-apps.sh --show <id>...   show these apps again
#   sonic/hide-apps.sh --undo           show again every app that this script hid
#   sonic/hide-apps.sh --status         list the hidden apps
#
# It runs sonic/watch/hide-apps on the watch, which writes or deletes the
# overrides in /usr/local/share/applications. The fork's launcher honours them
# at once, without a restart; the stock launcher ignores them. Nothing is
# uninstalled, and Settings stays in the quick panel.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
watch=${SONIC_WATCH:-sonic-screwdriver}
ssh "$watch" sh -s -- "$@" < "$here/watch/hide-apps"
