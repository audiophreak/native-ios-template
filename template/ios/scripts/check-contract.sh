#!/bin/sh
# Fails when ios/Contract/openapi.json is not the web project's current contract (or its recorded checksum is
# stale). usage: ios/scripts/check-contract.sh
set -eu
cd "$(dirname "$0")/.."
RECORDED="$(cat Contract/openapi.sha256)"
ACTUAL="$(shasum -a 256 Contract/openapi.json | cut -d' ' -f1)"
[ "$RECORDED" = "$ACTUAL" ] || { echo "Contract/openapi.sha256 does not match Contract/openapi.json" >&2; exit 1; }
if [ -f ../openapi/openapi.json ]; then
  cmp -s ../openapi/openapi.json Contract/openapi.json || { echo "ios/Contract/openapi.json differs from ../openapi/openapi.json: run ios/scripts/sync-contract.sh" >&2; exit 1; }
  echo "contract matches the web project's"
else
  echo "contract checksum is consistent (no ../openapi/openapi.json to compare with)"
fi
