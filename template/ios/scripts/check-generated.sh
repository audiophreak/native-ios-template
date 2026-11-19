#!/bin/sh
# Regenerates the client into a fresh temporary directory and requires zero difference from the committed
# client. Nothing is deleted: the temporary directory is left for the operating system to clear.
# usage: ios/scripts/check-generated.sh
set -eu
cd "$(dirname "$0")/.."
FRESH="$(mktemp -d "${TMPDIR:-/tmp}/api-client.XXXXXX")"
sh scripts/generate-client.sh "$FRESH" > "$FRESH.log" 2>&1 || { cat "$FRESH.log"; exit 1; }
if diff -r "$FRESH" Packages/AppCore/Sources/APIClient > "$FRESH.diff"; then
  echo "generated client is up to date"
else
  head -40 "$FRESH.diff"
  echo "The committed client differs from what the contract generates. Run ios/scripts/generate-client.sh and commit." >&2
  exit 1
fi
