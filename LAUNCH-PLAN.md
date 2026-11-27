# ScreenMind 5.0 — launch kit

Status: private beta candidate. The exact 5.0 candidate passed the personal-edition workflow on 2026-11-27. It is not a signed public release.

## Audience and positioning
Initial audience hypothesis: people with hundreds or thousands of saved screenshots, especially Hebrew-speaking students, developers and knowledge workers. Validate with interviews and a small consenting pilot; no customer traction is claimed.
Product promise: find, connect and revisit saved knowledge. Local-first by default; optional explicitly approved text-only AI requests. No promise of perfect OCR, semantic understanding or automatic eligibility verification.

## Launch sequence
1. Validate upgrade, encrypted backup, restore and notification behavior on a separate test library on a real iPhone. Do not delete photos during initial beta.
2. Complete privacy and security review; select support contact and distribution method. No live AI until the server, provider terms, retention and spend controls are reviewed.
3. Preview the Hebrew and English static landing pages on desktop and mobile, including RTL, keyboard focus and search. Publish only the isolated static output after explicit approval.
4. Recruit a small opt-in pilot using synthetic or non-sensitive material. Record import and search success, task completion, recovery success, errors and user feedback without collecting screenshot content.
5. Evaluate willingness to pay before introducing subscriptions. Local-first core and an optional AI tier are hypotheses; no prices, payment integration or paid hosting have been approved.

## Website
startup-site/index.html (Hebrew), startup-site/en.html (English). Fictional sample data only. No signup, analytics, external calls or live AI. netlify.toml builds only these two pages into startup-site-dist. Hosting and domain are not configured by this change. Before publication, verify the actual deployed headers and behavior, hosting logs and final privacy/contact information.

## Release references
5.0 CI: https://github.com/DavidPatlas-AI/screenmind-ios/actions/runs/45998233385
Installation artifact: https://github.com/DavidPatlas-AI/screenmind-ios/actions/runs/45998233385/artifacts/15197900844
The IPA requires local signing; preserve the current app and verify backup before upgrade.
See BETA-RELEASE-CHECKLIST.md and BETA-PRIVACY-DRAFT-HE.md.
