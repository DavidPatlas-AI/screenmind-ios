# ScreenMind V2 — experience foundation

## Implemented
- Local rule-based topic taxonomy with Hebrew, English, Russian, Spanish, French, German and Arabic vocabulary. Not semantic AI or full UI localization. Unknown or tied matches stay in open ideas.
- Derived automatic grouping of old and new captures, without overwriting manual collections, reviewed titles, text, or approval flags.
- Display titles derived from OCR text; no invented facts.
- Home prioritizes knowledge and makes manual review optional. Cleanup prompt no longer occupies every screen.
- Original photo dates are recorded separately from import dates; accessible existing photos can recover their dates.
- Added unit tests and adjusted existing graph and cleanup tests.

- Second pass: bounded topic cache; single-pass collection grouping; color-coded topic cards; automatic navigation to topics on completed scan; optional review secondary to finishing import. Tests added for cache and topic navigation.

## Release blockers
- Build and tests on macOS, test actual iPhone and existing libraries. Measure performance with thousands of captures. Current accuracy is not established.
- Genuine multilingual semantic AI, project inference, learned intent, tasks, stories, natural-language search, localized UI, and full 3D redesign are not implemented.
- No automatic deletion. Album scan currently stores reduced images, not always originals. Do not delete important originals without verified full-size backup.
- Preserve manual edits and ensure backward-compatible migration. No provider credentials embedded, no sending private captures without opt-in.
