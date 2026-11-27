#!/bin/bash
set -euo pipefail
IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$IOS_ROOT"
mkdir -p ci-results/screenshots

# Use the newest Xcode installed on the runner.
python3 - <<'PY'
import plistlib
import subprocess
from pathlib import Path
apps = list(Path("/Applications").glob("Xcode*.app"))
def version(app):
    plist = app / "Contents/Info.plist"
    if not plist.exists():
        return (0,)
    with plist.open("rb") as handle:
        info = plistlib.load(handle)
    parts = []
    for part in str(info.get("CFBundleShortVersionString", "0")).split("."):
        parts.append(int(part) if part.isdigit() else 0)
    return tuple(parts)
if not apps:
    raise SystemExit("No Xcode.app was found.")
best = max(apps, key=version)
print(f"Selecting {best} {version(best)}")
subprocess.check_call(["sudo", "xcode-select", "-s", str(best)])
PY

xcodebuild -version | tee ci-results/xcode-version.txt
xcrun simctl list devices available -j > ci-results/simulators.json
SIMULATOR_ID="$(python3 scripts/select_simulator.py ci-results/simulators.json)"
printf 'Selected simulator: %s\n' "$SIMULATOR_ID" | tee ci-results/simulator.txt
python3 - <<PY
import json
from pathlib import Path
payload = json.loads(Path("ci-results/simulators.json").read_text())
wanted = "${SIMULATOR_ID}"
for devices in payload.get("devices", {}).values():
    for device in devices:
        if device.get("udid") == wanted:
            Path("ci-results/simulator.txt").write_text(device.get("name", wanted) + "\n" + wanted + "\n")
            print(device.get("name", wanted))
PY

# Hebrew locale for the simulator UI. The tests also pass -AppleLanguages he.
PREFS="$HOME/Library/Developer/CoreSimulator/Devices/$SIMULATOR_ID/data/Library/Preferences"
mkdir -p "$PREFS"
xcrun simctl boot "$SIMULATOR_ID" || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b || true
defaults write "$PREFS/.GlobalPreferences" AppleLanguages -array he || true
defaults write "$PREFS/.GlobalPreferences" AppleLocale -string he_IL || true
xcrun simctl shutdown "$SIMULATOR_ID" || true

# Point the UI tests at an absolute screenshot directory. The scheme value may still be unexpanded.
SCHEME="ScreenMind.xcodeproj/xcshareddata/xcschemes/ScreenMind.xcscheme"
python3 - <<PY
from pathlib import Path
path = Path("${SCHEME}")
text = path.read_text()
text = text.replace("\$(SRCROOT)/ci-results/screenshots", "${IOS_ROOT}/ci-results/screenshots")
path.write_text(text)
PY

set +e
# The same simulator is listed twice (arm64 and x86_64). Tesseract is arm64-only,
# so the destination and ARCHS stay on arm64.
xcodebuild -project ScreenMind.xcodeproj -scheme ScreenMind -configuration Debug \
  -destination "platform=iOS Simulator,arch=arm64,id=$SIMULATOR_ID" \
  -derivedDataPath build -resultBundlePath ci-results/ScreenMind.xcresult \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO test 2>&1 | tee ci-results/build-and-test.log
STATUS=${PIPESTATUS[0]}
set -e
if [ -d /tmp/screenmind-shots ]; then
  cp -f /tmp/screenmind-shots/*.png ci-results/screenshots/ 2>/dev/null || true
fi
python3 scripts/export-screenshots.py ci-results || true
# Preserve raw benchmark lines; timings are simulator observations, not device guarantees.
grep -E "INTEGRATED_SCALE|MEMORY_BENCHMARK|CANDIDATE_BENCHMARK" ci-results/build-and-test.log > ci-results/scale-benchmark.txt || true
SHOTS="$(find ci-results/screenshots -name '*.png' | wc -l | tr -d ' ')"
printf 'Swift test exit %s. Simulator screenshots: %s.\n' "$STATUS" "$SHOTS" | tee ci-results/RESULT.txt
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<SUMMARY
## ScreenMind iOS verification
Test exit: ${STATUS}
Simulator screenshots: ${SHOTS}

The xcresult bundle and PNGs are attached as workflow artifacts.
This run does not sign an IPA or publish to TestFlight.
SUMMARY
fi
if [ "$STATUS" -eq 0 ] && [ "$SHOTS" -eq 0 ]; then
  echo "Tests passed but no simulator screenshot was written." >&2
  exit 1
fi
exit "$STATUS"
