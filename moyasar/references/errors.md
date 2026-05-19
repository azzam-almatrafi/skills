# Errors & retry semantics

Moyasar uses conventional HTTP status codes, but with one critical exception
(see the 201 caveat below). Read this before writing retry/error-handling code.

## HTTP status codes

| Code | Meaning |
|---|---|
| 200 | OK — worked as expected. |
| 201 | Created — resource created. **But a created payment may have `status: failed`** (see below). |
| 400 | Bad Request — invalid/missing parameter, charge validation failed. |
| 401 | Unauthorized — no/invalid API key. |
| 403 | Forbidden — **two distinct cases**: (a) JSON `{type:"authentication_error"…}` = credentials lack permission (e.g. `pk_*` on a non-create op); (b) **Cloudflare HTML body (error 1010)** = your client's User-Agent was WAF-blocked. See the Cloudflare note below. |
| 404 | Not Found — resource doesn't exist. |
| 405 | Method Not Allowed — entity not activated for live. |
| 429 | Too Many Requests — rate limited. |
| 500 | Internal Server Error — Moyasar-side; rare. Retry later. |
| 503 | Service Unavailable — maintenance; retry later. |

## The 201-with-failure caveat (most important)

> When a request is valid but the payment doesn't complete (e.g. the bank
> declines the card), Moyasar returns the **normal `201`** with the failure
> detailed in the response body.

So **never infer success from the HTTP code for payments**. Always branch on
the payment `status` field (`paid`/`captured` = good; `failed` = declined;
`initiated` = needs 3DS/OTP) and read `source.message` / `source.response_code`
for the reason. This is the single most common integration bug.

## Error response shapes

**Authentication error (`401`):**
```json
{ "type": "authentication_error", "message": "Invalid authorization credentials", "errors": null }
```

**Validation error (`400`):** a top-level `message` plus `errors`. **`errors`
is not always a per-field map** — live it is sometimes a map, sometimes a
plain string, often `null`:
```json
{ "type": "invalid_request_error", "message": "Validation Failed",
  "errors": { "amount": ["must be an integer"] } }
```
```json
{ "type": "invalid_request_error", "message": "Wrong number of parameters",
  "errors": "save_card options can't be used with MOTO transaction" }
```

**Duplicate `given_id` (`400`)** — verified live; note the type/message
(the older docs' `"Payment is already created."` is **outdated**):
```json
{ "type": "used_given_id",
  "message": "The given_id provided has been already used with a different payment.",
  "errors": null }
```
A duplicate is **rejected, not replayed**. Since `id == given_id`, the correct
recovery is to `GET /payments/{given_id}` and read its real status — do not
expect the create call to return the original payment. (SKILL.md → Idempotency.)

**Generic API error:**
```json
{ "type": "api_error", "message": "Object not found", "errors": null }
```

Always surface `message`. Treat `errors` defensively: it may be an object
(iterate per field), a string (show as-is), or null.

### Error `type` values

| Type | Meaning |
|---|---|
| `invalid_request_error` | Invalid parameters in the request. |
| `authentication_error` | Auth incorrect — check key + empty-password Basic Auth. |
| `rate_limit_error` | Too many requests too fast. |
| `api_connection_error` | Failed to connect to Moyasar's API. |
| `account_inactive_error` | Account not activated for real payments — contact Moyasar sales. |
| `api_error` | Other problems (e.g. resource not found). Rare. |
| `3ds_auth_error` | Card payment failed — cardholder failed 3DS authentication. |
| `used_given_id` | The `given_id` was already used for a different payment (`400`). Fetch the payment by id (== given_id) instead of retrying. |

## What to retry

- **Retry** (with backoff): `5xx`, `429` (respect rate limits), network /
  connection errors, and open/read/write timeouts.
- **For Create Payment specifically**, only retry the ambiguous cases (`5xx`,
  network error, timeout) and **only with the same `given_id`** so a charge
  that actually went through isn't duplicated. See SKILL.md → Idempotency.
- **Do not blind-retry** `4xx` — fix the request first (`400` = bad data,
  `401` = bad key, `403` = wrong key type/permission, `404` = wrong id).
- A conclusive `2xx`/`201` ends the retry loop — then inspect `status`.

Use exponential backoff with jitter and a max attempt cap; log the Moyasar
`type`/`message` for diagnostics.

## Cloudflare / WAF — the 403 that is *not* a credentials error

Moyasar's API (`api.moyasar.com`) sits behind **Cloudflare**. Verified live:
a request with the **default `Python-urllib/x.y` User-Agent gets `403`**
(Cloudflare error 1010, "browser/device banned"), while the *identical*
request with an explicit User-Agent succeeds with `200`. The 403 body is
**Cloudflare HTML**, not Moyasar's JSON `{type,message,errors}` envelope.

Implications:
- **Always send an explicit `User-Agent`** from any non-browser client
  (stdlib `urllib`, some HTTP libs, scrapers). The bundled
  `scripts/verify_payment.py` and `assets/moyasar-client.ts` already do.
- Detect this case: a `403` whose body does **not** parse as the JSON error
  envelope = WAF/UA block, **not** a key/permission problem. Fix the
  User-Agent; don't waste time rotating keys.
- Under heavy automated bursts from one IP you may still see transient
  Cloudflare 403s even with a good UA — back off and retry. Because Create
  Payment is idempotent via `given_id`, retrying it after such a 403 is safe
  (the request never reached payment processing; same `given_id` can't
  double-charge).
