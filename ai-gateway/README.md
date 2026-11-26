# ScreenMind AI gateway — experimental private server

Provider is disabled by default. No cloud account, SDK or live API call is needed for the offline transport tests.

## Offline verification
`node --test ai-gateway/bedrock.test.mjs`
`node --check ai-gateway/server.mjs`

## Persistent pilot guard (required for any live provider)
Use a private persistent local directory owned by the gateway operator, outside the repository, with permissions 0700. Set SCREENMIND_PILOT_LEDGER to an absolute path in that directory. Initialize once with a deliberately small approved invocation ceiling (for example 20):
```sh
node --input-type=module -e 'import {initializePilotLedger} from "./ai-gateway/pilot-guard.mjs"; initializePilotLedger(process.argv[1],Number(process.argv[2]))' /absolute/private/pilot.json 20
```
The file must not already exist. Every provider attempt reserves one invocation durably before inference; failures count. Missing/corrupt/locked ledger stops requests. The limit persists across normal restarts and does not reset automatically. Never delete or recreate the ledger to bypass an agreed limit. If a crash leaves a lock, investigate before recovering it. This is a single-host pilot control, not a guaranteed dollar cap, distributed quota, or tamper-proof billing record. Keep AWS Budgets alerts and IAM restrictions as additional safeguards. Do not use ephemeral filesystem storage.

## Optional Bedrock pilot (not deployed)
Review AWS eligibility, model availability, pricing, region, inference logging/data retention and credentials first. Choose a directly invocable model in the approved region that supports Converse structured JSON output, system prompts, and the configured inference parameters. Install a reviewed version of `@aws-sdk/client-bedrock-runtime` in the gateway environment; the mock tests do not install it. Pin the dependency and lockfile before deployment.

Set server-only `SCREENMIND_PROVIDER=bedrock`, `SCREENMIND_ALLOW_LIVE_AI=yes`, `AWS_REGION`, `BEDROCK_MODEL_ID` and a cryptographically random `SCREENMIND_GATEWAY_TOKEN` of at least 32 characters. Use short-lived credentials or a dedicated IAM role limited to the selected model's InvokeModel permission. Never put AWS credentials into iOS, GitHub or chat. Do not enable request/response content logging. Check credit eligibility and billing separately.

OpenAI remains available only when `SCREENMIND_PROVIDER=openai` and `SCREENMIND_ALLOW_LIVE_AI=yes` are explicitly set, with server-side `OPENAI_API_KEY`.

The server binds to loopback; a private trusted HTTPS reverse proxy is needed. No automatic provider fallback, no tool execution, no upload of screenshot images. Only the previewed text fields are forwarded, at most 12 items/128 KiB per batch, max 4000 output tokens, 55-second timeout, one concurrent request and 20 requests per rolling hour. Limits are in-memory and reset on restart; these are not a billing cap or multi-tenant production authentication. Bedrock first-time schema compilation may exceed the timeout. No retry is performed; model/region compatibility and a synthetic live smoke test remain required.

Official API: https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html

## Previous gateway notes (historical; new explicit opt-in above supersedes startup commands)
# ScreenMind private AI gateway (experimental)

The iOS app works locally by default. This optional single-user gateway enables real generative text analysis on older iPhones without embedding an OpenAI API key in the IPA.

## Run privately
- Node.js 20+; set OPENAI_API_KEY and a high-entropy SCREENMIND_GATEWAY_TOKEN (at least 32 characters) using your host's secret manager. Never commit them. OPENAI_MODEL defaults to gpt-4o-mini; choose an available model supporting Responses structured outputs.
- Run node ai-gateway/server.mjs. It binds only to loopback, port 8787 by default. Configure an authenticated trusted HTTPS reverse proxy with rate limits; expose only POST /analyze. Do not deploy publicly without reviewing authentication and abuse controls.
- In the iPhone AI screen enter your own https://host/analyze and the gateway access token, not the OpenAI API key. The token is session-only. The app refuses redirects.
- Preview up to 12 OCR text excerpts. Remove sensitive items before explicitly sending. No image files, device photo IDs or local record IDs are sent; temporary batch IDs are used. No automatic upload.
- Provider calls may incur API charges. store:false is requested but is NOT a guarantee of zero provider retention. Review current provider data controls and organizational policies. Do not send classified, private or credential-bearing data.
- Results are proposals. The app validates the batch and saves AI metadata separately in one action, preserving OCR, manual titles, collections, tasks, and deletion approval. Edits invalidate stale analysis.

## Verification and limitations
No gateway deployed or live provider call performed in this development session. The code must be reviewed, tested with synthetic text and deployed privately before use. Rate limits are in-process, not suitable for production multi-user service. Production needs tenant isolation, stronger authentication, durable quotas, audit controls without content logging, redaction, privacy review and integration tests.

## Optional Gemini adapter (not deployed)
Uses Gemini Developer API generateContent structured JSON output. Explicitly set SCREENMIND_PROVIDER=gemini, SCREENMIND_ALLOW_LIVE_AI=yes, SCREENMIND_GEMINI_PAID_TERMS_REVIEWED=yes, server-only GEMINI_API_KEY, GEMINI_MODEL and the persistent pilot ledger. Select a currently supported model with structured output after reviewing terms, pricing, region and model compatibility. The terms flag is an operator attestation, not automatic billing-tier verification. Do not enable this adapter for private content until paid-service data terms, project billing and privacy obligations are verified. Free-tier content may be used to improve Google's products. No API keys in chat or iOS; no automatic fallback or retry. No live calls have been made. Offline tests use a fake transport. See https://ai.google.dev/gemini-api/terms and https://ai.google.dev/api/generate-content.
