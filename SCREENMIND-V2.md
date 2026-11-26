# ScreenMind V2 — experience foundation

## Implemented
- Local rule-based topic taxonomy with Hebrew, English, Russian, Spanish, French, German and Arabic vocabulary. Not semantic AI or full UI localization. Unknown or tied matches stay in open ideas.
- Derived automatic grouping of old and new captures, without overwriting manual collections, reviewed titles, text, or approval flags.
- Display titles derived from OCR text; no invented facts.
- Home prioritizes knowledge and makes manual review optional. Cleanup prompt no longer occupies every screen.
- Original photo dates are recorded separately from import dates; accessible existing photos can recover their dates.
- Added unit tests and adjusted existing graph and cleanup tests.

- Second pass: bounded topic cache; single-pass collection grouping; color-coded topic cards; automatic navigation to topics on completed scan; optional review secondary to finishing import. Tests added for cache and topic navigation.

- Projects branch: discovers groups of at least two screenshots with the same explicit GitHub repository or Netlify app address. Ambiguous multi-project screenshots are not assigned. Project cards open a source timeline and allow a text-only source draft export; no generated AI claims. Added project chronology and legacy-data decoding tests.

- Intelligence branch: private source-linked search using Apple's on-device Natural Language sentence embeddings when the language model is available. Searches all active records lexically and up to 250 recent records semantically, ranks exact matches first, and shows the search method. No cloud account, API key, or external data transfer. Hebrew and other languages without a suitable local model use the lexical fallback; no translation or generative answers. Added deterministic tests for relevance and vector similarity.

## Release blockers
- Build and tests on macOS, test actual iPhone and existing libraries. Measure performance with thousands of captures. Current accuracy is not established.
- Genuine multilingual semantic AI, broader project inference beyond explicit addresses, learned intent, tasks, stories, natural-language search, localized UI, and full 3D redesign are not implemented.
- No automatic deletion. Album scan currently stores reduced images, not always originals. Do not delete important originals without verified full-size backup.
- Preserve manual edits and ensure backward-compatible migration. No provider credentials embedded, no sending private captures without opt-in.
