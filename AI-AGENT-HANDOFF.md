# ScreenMind — AI collaboration handoff
Updated 2026-11-26. Use this as a shared brief in Gemini/Antigravity, Claude Code, Codex or other authorized developer tools. No tool is automatically connected to another account.
 
## Baseline and source of truth
- Stable verified native baseline: screenmind-v2-stories, commit 7196a4adacb3c01b791ad4a86bf1d9de1f43ed29; successful CI https://github.com/DavidPatlas-AI/screenmind-ios/actions/runs/45808621525.
- Experimental Bedrock transport: screenmind-v2-bedrock; pilot safety: screenmind-v2-pilot-guard. Check CI before using; no real AWS deployment or live inference has been verified.
- Business material: screenmind-startup-aws. No confirmed credit award, public domain, registered entity or live users.
- Work tracking: https://linear.app/david-patals/project/screenmind-mvp-and-aws-activate-3938d1e52d65

## Rules for all agents
Use a separate branch for changes, one issue per branch, no direct writes to main or force pushes. Read the current implementation before suggesting changes. Keep local-first and explicit consent defaults. Never send personal photos, military material, OCR contents, credentials, account identifiers or private user information to external AI. Use synthetic/authorized fixtures only. No paid provisioning, billing activation, automated original-photo deletion or public deployment without founder approval. Do not copy secrets to prompts or commits. Report precise test commands/results and unresolved risks. Do not claim mocked tests are live tests. Human review before merging.

## Task A — Gemini / Antigravity: independent read-only review
Review the verified iOS branch and experimental pilot-guard branch. Prioritize data loss, OCR/RTL, stale analyses, permission state, Swift concurrency, and network consent. Inspect Vault, NativeLibrary, AlbumScan, CleanupView, AIEnrichmentView and ai-gateway. Identify up to 10 actionable issues with file/function, reproduction, severity and minimum fix. Do not modify code yet. Never export real data. Return findings as Markdown suitable for Linear.

## Task B — Google AI Studio: multilingual evaluation
Build a synthetic benchmark of 60 text fixtures: Hebrew, Russian, English, mixed-language, ambiguous short text, dates, numbers and prompt-injection examples. Include expected topic, source-grounded summary, and whether a task is supported. Separate ambiguous items from scored examples. Evaluate only synthetic text, no live paid API calls unless explicitly approved. Return machine-readable JSON and scoring rubric. Compare retrieval/categorization quality without claiming production accuracy.

## Task C — Claude Code / Codex: backup and restore
Plan a versioned, integrity-checked export and restore, using current Vault schema. Address reduced scan images vs originals, interruption, corrupt archives, duplicate conflicts, metadata preservation, memory budget and transactional recovery. Write tests first on an isolated branch. Do not delete originals, change signing identity, or overwrite user data.

## Task D — Grok / Gemini research
Research current competitors, pricing, startup offers and availability with dated sources. Distinguish verified facts, estimates and hypotheses. No invented market size, traction, credit eligibility, endorsement or competitor claims.

## Task E — connected Replit, Canva, Figma
Replit: standalone synthetic web demonstration, no new paid deployment. Canva: editable English pitch deck. Figma: accessible iOS UI specification with clear local/cloud states. Keep actual application code separate from demonstration. Review all claims against native baseline.

## Activation checklist
1. Google Developer Program: https://developers.google.com/program — link eligible Google AI Pro plan and check actual credit balance.
2. Google AI Studio: https://aistudio.google.com/ — verify available subscription quota and distinct API billing before using.
3. Antigravity: https://antigravity.google/ — sign in and inspect entitlements; use authorized repository access only.
4. GitHub Education: https://education.github.com/pack — verify student eligibility and each provider's restrictions on commercial use.
5. No account credentials or API keys in this handoff. Never assume Pro subscription equals unlimited API usage.

## Agent output format
Task ID | base commit | branch | changes or findings | tests actually run | risks | costs incurred | next review needed. 
