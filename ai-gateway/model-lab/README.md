# ScreenMind Model Lab

Version 1: 48 invented OCR-text examples (12 Hebrew, 12 English, 12 Russian, 12 mixed). No real user screenshots, credentials or model responses. The labels are author-defined hypotheses, not expert-reviewed ground truth.

Offline commands (Node 20+):
- node --test ai-gateway/model-lab/lab.test.mjs
- node ai-gateway/model-lab/lab.mjs batches
- node ai-gateway/model-lab/lab.mjs score predictions.json

The batches output has local mapping metadata and a request object. Submit ONLY the request object to a separately configured, authorized provider, not the mapping or this repository's answer key. Use the same prompt, model settings, batch composition and output language for each model; record exact model version, provider, date, duration and provider-reported input/output tokens separately. Never turn on billing automatically. No live requests are implemented by this lab.

Convert each successful response item's temporary ID to fixtureId using its batch mapping. Each prediction object must contain exactly fixtureId, title, summary, topic, suggestedTask. Keep missing responses missing. Score each provider separately. Do not repair or discard invalid responses after seeing labels.

Report per-language and overall valid responses, topic matches, task-presence matches, false tasks, missed tasks and literal numeric anchor matches. Numeric substring matching is a weak diagnostic; it cannot detect invented facts, wrong units or negation. Have a human reviewer inspect all summaries and tasks without knowing provider identity. Assess groundedness, language quality, correct quantities, dates, omissions and source-text instruction resistance. Do not use this dataset as evidence of OCR accuracy (there are no images), real user performance, or semantic retrieval. Expand with independent, realistic authorized holdout fixtures before production decisions.

The CI reference-answer test is deliberately deterministic and checks the scoring implementation, not model intelligence. No OpenAI, Gemini or Bedrock comparative results exist until actually evaluated. Pricing, data terms, availability and billing must be checked at the time of each authorized live evaluation.


## Cross-model comparison (5.5)
Run node ai-gateway/model-lab/compare.mjs template to see the input format. Generate one run per exact model, preserve every planned batch, and use null items for a failed batch and null usage for missing or inconsistent token metadata. Duration is positive integer milliseconds for the entire attempt, including failures; no retries or selective omissions. Use the existing batch IDs and temporary source IDs. Supply the same SHA-256 protocolHash (operator computes from the exact shared prompt/settings, date and experiment protocol) and the generated datasetHash. The script checks that the declared protocol hashes match, not that the experiment was actually conducted as declared.

Run node ai-gateway/model-lab/compare.mjs compare runs.json [rates.json]. The rates format matches usage-meter.mjs; operator must verify prices independently. Output contains quality by language, median/max latency, failed batches, missing usage and estimated measured cost. Proposed quality gates: all 48 valid, zero unexpected items, no failed batches or false tasks, at least 85% overall topic and task-presence accuracy and 75% topic accuracy in every language. The Pareto front includes only passing models with all batch usage measured and a supplied rate. It does not choose a winner or route production requests. Numeric anchors are weak diagnostics, not factual correctness. Review all outputs blind, use independent holdout data, and check privacy terms before any authorized live trial. Tests use invented reference predictions, not actual AI responses. No paid calls or provider comparison have been performed.
