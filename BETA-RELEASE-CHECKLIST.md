# ScreenMind 5.0 — private beta candidate

Version 5.0.0 (build 50); personal bundle identifier remains app.screenmind.next.personal. This is a candidate, NOT a store release. Branch is based on the successful 4.9 build bd7c8e291bae18ad50df42382d077e9acb22ae66. Previous CI: https://github.com/DavidPatlas-AI/screenmind-ios/actions/runs/45995373128

## Release gates
- [ ] This exact commit passes gateway tests, iOS unit/UI tests and unsigned ARM64 IPA build; record run URL, commit, artifact and SHA256.
- [ ] On a separate test library, exercise encrypted export, wrong key, corrupt part, restore, repeat restore and verify original bytes and metadata.
- [ ] On actual iPhone, check upgrade with same signing identity; preserve an independently checked backup. Never uninstall to force an update.
- [ ] Check PhotoKit permissions, interrupted import, OCR quality, memory and battery with synthetic and explicitly approved non-sensitive inputs. No actual photo deletion in first beta.
- [ ] Test notifications, canceled reminders, accessibility, RTL and app backgrounding.
- [ ] Keep gateway disabled until provider, approved text-only consent, privacy review, retention, spending limits and HTTPS configuration are verified. No automatic cloud analysis.
- [ ] Review recovery-key display, app-switcher snapshots and screenshot auto-import; do not photograph or upload recovery keys.
- [ ] Resolve privacy manifest/API reasons and dependencies, export-encryption declaration and licensing, distribution eligibility, support contact and final privacy policy before external distribution.
- [ ] Signed installation and beta participant consent; no external release, payments or App Store claims until separately approved.

## Evidence and limitations
Version 4.6 tests covered synthetic metadata up to 10,000 records; not 10,000 actual photographs or physical-device performance. 4.9 passed its workflow. The parallel memory-answers branch is not included; its failed runs do not establish a defect in this branch. Only the personal edition is covered by these CI results, not the full share-extension build. Preserve the existing safe fallback branch and do not modify main.

## Artifacts
Use the successful run of this exact candidate. Download ScreenMind-Personal-iPhone and verify SHA256.txt locally. The IPA is unsigned and requires local signing. Follow INSTALL-IPHONE-WINDOWS.md. Keep verification artifacts with the run. No server credentials, actual screenshots, recovery keys or private user data in issue reports.
