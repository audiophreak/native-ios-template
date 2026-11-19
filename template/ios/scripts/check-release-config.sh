#!/bin/sh
# Proves what the Release build allows: builds Release for the simulator SDK without signing and inspects the
# built Info.plist. It must require https (APIScheme), have NO App Transport Security entry at all (so the system
# default, https with valid certificates, applies) and name the configured host. usage: ios/scripts/check-release-config.sh
set -eu
cd "$(dirname "$0")/.."
SIM="$(sh scripts/simulator.sh)"
xcodebuild build -project App.xcodeproj -scheme App -configuration Release -destination "id=$SIM" \
  -derivedDataPath .derived-data/release -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO > .derived-data-release.log 2>&1 \
  || { tail -30 .derived-data-release.log; exit 1; }
PLIST=".derived-data/release/Build/Products/Release-iphonesimulator/App.app/Info.plist"
SCHEME="$(plutil -extract APIScheme raw -o - "$PLIST")"
HOST="$(plutil -extract APIHost raw -o - "$PLIST")"
[ "$SCHEME" = "https" ] || { echo "Release APIScheme is '$SCHEME', not https" >&2; exit 1; }
if plutil -extract NSAppTransportSecurity raw -o - "$PLIST" > /dev/null 2>&1; then
  echo "Release Info.plist has an NSAppTransportSecurity entry" >&2
  exit 1
fi
echo "Release: https://$HOST, no App Transport Security exception"
