#!/bin/sh
# Builds and tests on the iOS Simulator. No signing identity and no development team are needed.
#
#   ios/scripts/test.sh            the app's tests (hosted in the app) and the AppCore package tests, via xcodebuild
#   ios/scripts/test.sh app        only the app's hosted tests
#   ios/scripts/test.sh package    only the package tests
#   ios/scripts/test.sh direct     the package tests run straight in the simulator with its own `xctest`, skipping
#                                  xcodebuild's test-runner handshake (for a machine where that handshake hangs:
#                                  "The test runner hung before establishing connection")
#
# Set IOS_SIMULATOR to a simulator name or UDID to choose one; build products go to ios/.derived-data/ (ignored).
set -eu
cd "$(dirname "$0")/.."
SIM="$(sh scripts/simulator.sh)"
DERIVED="$PWD/.derived-data"
MODE="${1:-all}"

app() {
  xcodebuild test -project App.xcodeproj -scheme App -destination "id=$SIM" -derivedDataPath "$DERIVED/app" \
    -onlyUsePackageVersionsFromResolvedFile
}
package() {
  (cd Packages/AppCore && xcodebuild test -scheme AppCore-Package -destination "id=$SIM" -derivedDataPath "$DERIVED/package" \
    -onlyUsePackageVersionsFromResolvedFile)
}
direct() {
  (cd Packages/AppCore && xcodebuild build-for-testing -scheme AppCore-Package -destination "id=$SIM" -derivedDataPath "$DERIVED/package" \
    -onlyUsePackageVersionsFromResolvedFile)
  PRODUCTS="$DERIVED/package/Build/Products/Debug-iphonesimulator"
  XCTEST="$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest"
  xcrun simctl boot "$SIM" 2>/dev/null || true
  xcrun simctl bootstatus "$SIM" -b > /dev/null
  SIMCTL_CHILD_DYLD_FRAMEWORK_PATH="$PRODUCTS:$PRODUCTS/PackageFrameworks" xcrun simctl spawn "$SIM" "$XCTEST" "$PRODUCTS/AppCoreTests.xctest"
}

case "$MODE" in
  all) app; package ;;
  app) app ;;
  package) package ;;
  direct) direct ;;
  *) echo "usage: scripts/test.sh [all|app|package|direct]" >&2; exit 2 ;;
esac
