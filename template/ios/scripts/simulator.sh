#!/bin/sh
# Picks the iOS Simulator the other scripts use: $IOS_SIMULATOR (a name or a UDID) if set, otherwise the first
# available iPhone. Prints its UDID. Nothing is created, booted or changed.
set -eu
WANT="${IOS_SIMULATOR:-}"
LIST="$(xcrun simctl list devices available)"
if [ -n "$WANT" ]; then
  printf '%s\n' "$LIST" | grep -F "$WANT" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1 | grep . || { echo "no available simulator matches IOS_SIMULATOR=$WANT" >&2; exit 1; }
else
  printf '%s\n' "$LIST" | grep -E '^ +iPhone ' | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1 | grep . || { echo "no iPhone simulator is installed (Xcode > Settings > Components)" >&2; exit 1; }
fi
