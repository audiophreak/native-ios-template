#!/bin/sh
# Copies the web project's contract (openapi/openapi.json at the project root) into ios/Contract/, records its
# checksum and regenerates the client. Run it after the web API changed (and after `npm run openapi:generate`).
# usage: ios/scripts/sync-contract.sh
set -eu
cd "$(dirname "$0")/.."
SOURCE="../openapi/openapi.json"
[ -f "$SOURCE" ] || { echo "No $SOURCE: this project's web part needs native_client=true." >&2; exit 1; }
cp "$SOURCE" Contract/openapi.json
shasum -a 256 Contract/openapi.json | cut -d' ' -f1 > Contract/openapi.sha256
sh scripts/generate-client.sh
echo "contract synced and client regenerated; commit Contract/ and the generated client together"
