#!/usr/bin/env bash
# Sonic Screwdriver: the quick panel's Find phone button, first in its sliding
# row and enabled, in the watch's settings.
#
#   sonic/quickpanel-findphone.sh            add it
#   sonic/quickpanel-findphone.sh --undo     take it out again
#   sonic/quickpanel-findphone.sh --status   where it is
#
# It runs sonic/watch/quickpanel-findphone on the watch, which changes the
# user's dconf keys /desktop/asteroid/quickpanel/slider and enabled. The
# launcher follows at once, without a restart.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
watch=${SONIC_WATCH:-sonic-screwdriver}
ssh "$watch" sh -s -- "$@" < "$here/watch/quickpanel-findphone"
