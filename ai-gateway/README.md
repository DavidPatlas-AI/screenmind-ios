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
