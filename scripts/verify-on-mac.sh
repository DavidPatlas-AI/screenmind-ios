#!/bin/bash
set -euo pipefail
IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v xcodebuild >/dev/null; then
  echo "Xcode and the iOS SDK are required." >&2
  exit 1
fi
xcodebuild -project "$IOS_ROOT/ScreenMind.xcodeproj" -scheme ScreenMind -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$IOS_ROOT/build" CODE_SIGNING_ALLOWED=NO build
if [ -n "${SCREENMIND_TEST_DESTINATION:-}" ]; then
  xcodebuild -project "$IOS_ROOT/ScreenMind.xcodeproj" -scheme ScreenMind -configuration Debug \
    -destination "$SCREENMIND_TEST_DESTINATION" -derivedDataPath "$IOS_ROOT/build" CODE_SIGNING_ALLOWED=NO test
else
  echo "Simulator build completed. XCTest has NOT run."
  echo "Set SCREENMIND_TEST_DESTINATION='platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' to run the tests."
fi
