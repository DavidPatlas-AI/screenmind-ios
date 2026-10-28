#!/bin/bash
set -euo pipefail
IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$IOS_ROOT"
mkdir -p ci-results
xcodebuild -version | tee ci-results/xcode-version.txt
xcrun simctl list devices available -j > ci-results/simulators.json
SIMULATOR_ID="$(python3 scripts/select_simulator.py ci-results/simulators.json)"
printf 'Selected simulator: %s\n' "$SIMULATOR_ID"
xcodebuild -project ScreenMind.xcodeproj -scheme ScreenMind -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath build -resultBundlePath ci-results/ScreenMind.xcresult \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tee ci-results/build-and-test.log
printf 'Swift compilation and XCTest completed successfully. This is not a signed iPhone installation.\n' \
  | tee ci-results/RESULT.txt
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<'SUMMARY'
## ScreenMind iOS verification
Swift compilation and XCTest completed successfully on an iPhone simulator.

The result bundle and build log are attached as **ScreenMind-iOS-verification**.
This run does not sign an IPA, publish to TestFlight, or verify real-device Photos/Files behavior.
SUMMARY
fi
