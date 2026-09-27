# 06 — Claude API facts for SmartModeClient (authoritative, from the bundled claude-api skill)

Swift has no official Anthropic SDK → the app uses **raw HTTP via URLSession**. These facts override anything recalled from training data.

## Endpoint & headers
- `POST https://api.anthropic.com/v1/messages`
- Headers:
  - `content-type: application/json`
  - `x-api-key: <user key from Keychain>`
  - `anthropic-version: 2023-06-01`
  - `anthropic-beta: server-side-fallback-2026-07-01` **only when model == `claude-opus-5`** (paired with body field `"fallbacks": "default"`). Pairing this header with the array form of `fallbacks`, or sending the array header with `"default"`, returns 400. Do not send `fallbacks` for other models.

## Models (exact ids — never append date suffixes)
| Setting label (TR) | id | notes |
|---|---|---|
| "Claude Opus 5 (varsayılan, en akıllı)" | `claude-opus-5` | default. Thinking is adaptive by default (omit `thinking`). Use `output_config.effort` = `"low"` for parsing, `"medium"` for drafting/summaries. Include `"fallbacks": "default"` + beta header. |
| "Claude Sonnet 5 (dengeli)" | `claude-sonnet-5` | may use `output_config.effort` (`low`/`medium`). |
| "Claude Haiku 4.5 (en hızlı/ucuz)" | `claude-haiku-4-5` | **do NOT send `effort`** (errors on Haiku 4.5). Do not send `thinking`. |

The model is the **user's choice** in Settings; default is `claude-opus-5`.
Never send `temperature`, `top_p`, `top_k` (rejected on Opus 5 / Sonnet 5). Never send `thinking: {type:"enabled", budget_tokens}` (400). Never prefill an assistant turn (400).

## Structured JSON output (for parsing)
Body field:
```json
"output_config": {
  "effort": "low",
  "format": { "type": "json_schema", "schema": { ...JSON Schema... } }
}
```
(omit `effort` key for Haiku 4.5 — keep `format`).
Schema rules: supported = object/array/string/integer/number/boolean/null, `enum`, `const`, `anyOf`, `allOf`, `$ref`; string formats date-time/date/time. **Every object must have `"additionalProperties": false`.** NOT supported: `minimum`/`maximum`, `minLength`/`maxLength`, recursive schemas. Make all properties `required` and express optional values as nullable with `anyOf: [{"type":"string"},{"type":"null"}]`.
First request with a new schema has one-time compile latency (cached 24 h) → keep the schema a static constant (byte-identical every request).

## Request body shape (parse)
```json
{
  "model": "claude-opus-5",
  "max_tokens": 4096,
  "fallbacks": "default",
  "system": "<static Turkish-aware instructions>",
  "messages": [{"role":"user","content":"Şu an: 2026-09-27T10:30 (Pazar), saat dilimi Europe/Istanbul. Projeler: [...]. Yerler: [...]. Cümle: \"...\""}],
  "output_config": {"effort":"low","format":{"type":"json_schema","schema":{...}}}
}
```
Put volatile data (current time, utterance) only in the user message; keep `system` byte-stable.

## Response handling
- Response JSON: `{ "id", "model", "stop_reason", "content": [ {type:"thinking",...}, {type:"fallback",...}, {type:"text","text":"..."} ], "usage": {...} }`.
- Concatenate only blocks with `type == "text"`; ignore `thinking`, `fallback`, and unknown block types (decode `content` as an array of loosely-typed blocks: `type: String`, `text: String?`).
- Check `stop_reason` BEFORE reading content: `"refusal"` → treat as failure (show "Akıllı mod bu isteği işleyemedi"); `"max_tokens"` → output may be truncated → treat as failure for JSON parse.
- With structured outputs the text block is the JSON document → `JSONDecoder().decode(...)` of `text.data(using: .utf8)`.

## Errors
Error body: `{"type":"error","error":{"type":"<kind>","message":"..."}}`.
| HTTP | meaning | app behavior |
|---|---|---|
| 400 | invalid_request_error | no retry; log; fall back to on-device parse |
| 401 | authentication_error | "API anahtarı geçersiz" — prompt to fix key |
| 403 | permission_error | no retry |
| 404 | not_found_error (bad model id) | no retry |
| 413 | request too large | no retry |
| 429 | rate_limit_error | one retry after `retry-after` header seconds (cap 5 s) |
| 500 / 529 | api_error / overloaded_error | one retry after 1.5 s |
Network errors (URLError) → one retry, then fall back to on-device result.

## Timeouts
- Parse: `URLRequest.timeoutInterval = 25` s (Opus 5 at effort low typically a few seconds); UI never blocks — the on-device parse result is shown immediately and replaced/upgraded if Smart Mode returns something better.
- Draft/summary: 60 s, `max_tokens` 8000, `effort` "medium" (non-streaming is fine below ~16K).

## Privacy
Smart Mode is OFF by default. Only runs when the user has entered a key AND enabled it. Settings screen text must state that the spoken sentence (and for drafts, the item text) is sent to Anthropic.
