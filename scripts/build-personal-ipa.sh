#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p personal-output/Payload ci-results
xcodebuild -project ScreenMind.xcodeproj -scheme ScreenMind -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build-personal \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
  2>&1 | tee ci-results/device-build.log
APP="build-personal/Build/Products/Release-iphoneos/ScreenMind.app"
test -f "$APP/ScreenMind"
test ! -d "$APP/PlugIns"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")" = "app.screenmind.next.personal"
file "$APP/ScreenMind" | grep -q arm64
ditto "$APP" personal-output/Payload/ScreenMind.app
(cd personal-output && zip -qry ScreenMind-Personal-unsigned.ipa Payload)
(cd personal-output && shasum -a 256 ScreenMind-Personal-unsigned.ipa > SHA256.txt)
echo "Device IPA built. Local signing through AltStore is still required." >> "$GITHUB_STEP_SUMMARY"

