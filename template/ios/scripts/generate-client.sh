#!/bin/sh
# Regenerates the typed Swift API client from ios/Contract/openapi.json with the pinned generator
# (Tools/Generator, swift-openapi-generator, exact version). The output is committed; the app's own build never
# runs the generator. usage: ios/scripts/generate-client.sh [OUTPUT_DIRECTORY]
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-Packages/AppCore/Sources/APIClient}"
swift run --package-path Tools/Generator swift-openapi-generator generate \
  --config Contract/openapi-generator-config.yaml \
  --output-directory "$OUT" \
  Contract/openapi.json
