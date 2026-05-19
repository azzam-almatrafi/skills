---
name: moyasar
description: >-
  Integrate the Moyasar payment gateway (Saudi Arabia) over its REST API:
  creating, fetching, listing, updating, refunding, capturing, and voiding
  payments; invoices; payouts and payout accounts; settlements and settlement
  lines; card tokens; and webhooks. Use this skill whenever the user works with
  Moyasar or references it implicitly — api.moyasar.com / apimig.moyasar.com
  endpoints, pk_test_/sk_test_/pk_live_/sk_live_ API keys, Moyasar Form
  (moyasar.umd.min.js / Moyasar.init), the react-native-moyasar-sdk, or builds
  checkout, card payment, mada / Apple Pay / Samsung Pay / STC Pay, refund,
  payout, or payment-webhook flows for a Saudi merchant. Trigger it even when
  "Moyasar" is not said by name but these keys, hosts, or the hosted form
  appear, and follow its security and verification rules rather than improvising
  payment code.
---

# Moyasar Payment Gateway

Moyasar is a Saudi payment gateway. This skill encodes correct, secure
integration of its REST API. **Payment code is high-stakes**: a mistake can
double-charge a customer, leak a secret key, or mark an unpaid order as paid.
Follow the rules here rather than guessing; when a detail isn't covered, read
the relevant `references/` file before writing code.

## How to use this skill

1. Read this file fully — it carries the model, the security rules, and the
   end-to-end flows that apply to *every* integration.
2. For endpoint-level detail (every field, every status, every variant), open
   the matching reference file from the table below. Don't reconstruct request
   or response shapes from memory — they have subtle required fields.

| If the task involves… | Read |
|---|---|
| Payment object/status, sources, splits, AFT — endpoint field schemas | `references/payments.md` |
| *When/how* to authorize, capture, void, refund — time windows, ordering, failure playbooks | `references/payment-flows.md` |
| Hosted invoices / payment links, bulk invoices | `references/invoices.md` |
| Saving cards / tokenization, charging a saved card | `references/tokens.md` |
| Promo codes / coupons — creating & applying. Moyasar BIN coupons **and** customer-typed codes (no create-coupon API; typed codes are app-side) | `references/coupons.md` |
| Sending money out: payout accounts, payouts, channels/flows, internal transfers | `references/payouts.md` |
| Reconciliation: settlements, settlement lines, `balance_transferred`, transfers | `references/settlements.md` |
| Webhook setup, retries, verifying webhooks (incl. `balance_transferred`) | `references/webhooks.md` |
| HTTP/API error shapes, what to retry | `references/errors.md` |
| Interpreting a *failed* payment: gateway response codes, 3DS reasons, messages | `references/error-codes.md` |
| Moyasar Form full config + lifecycle callbacks + custom-UI tokenization | `references/moyasar-form.md` |
| React Native SDK, Apple Pay session, BIN/issuer lookup, callback page | `references/frontend.md` |
| Sandbox test cards / wallet amounts / STC mobiles & OTPs / payout scenarios | `references/testing.md` |
| **Node.js / TypeScript / Next.js (Axios)** — typed client, App Router route handlers, callback & webhook verification | `references/nodejs-typescript.md` + bundled `assets/moyasar-client.ts` |
| Verifying a payment server-side | `scripts/verify_payment.py` (Python — run it / port it); TS equivalent is `verifyPayment()` in `assets/moyasar-client.ts` |
| Recurring billing / subscriptions (charge a saved token on a schedule) | `scripts/recurring_charge.py` (verified live) + `references/tokens.md` → Recurring billing |

## The core model

- **Base URL:** `https://api.moyasar.com/v1` for everything except aggregation
  *transfers*, which use `https://apimig.moyasar.com/v1` (see settlements ref).
- **All requests over HTTPS.** Plain HTTP is rejected. No exceptions.
- **JSON** request and response bodies (form-encoded also accepted on input).
- **Amounts are integers in the smallest currency unit**, never decimals:
  - `1.00 SAR` → `100` (halalas)
  - `1.00 KWD` → `1000` (fils)
  - `1 JPY` → `1` (no minor unit)
  Compute as `round(major_amount * minor_factor)`. Passing `10.50` where `1050`
  is expected is a common, costly bug.
- **IDs are UUIDs** (except token IDs, which look like `token_…`).
- **Pagination:** list endpoints return 40 items/page plus a `meta` object
  (`current_page`, `next_page`, `prev_page`, `total_pages`, `total_count`). Pass
  `?page=N`. Newest first. Some lists (e.g. internal transactions) return
  `total_count: null` — treat them as infinite-scroll, page until `next_page`
  is null.
- **Metadata:** optional key/value object on payments, invoices, payouts,
  tokens, internal transactions. Up to 30 keys, key ≤ 40 chars, value ≤ 500
  chars. Searchable via list endpoints' `metadata[key]=value` filter. Unset a
  key by sending it empty; unset all by sending empty metadata. **Never store
  card numbers, bank accounts, or any sensitive data in metadata.**

## Authentication — read this carefully

Moyasar uses **HTTP Basic Auth** with the **API key as the username and an
empty password**. The empty password matters: `Authorization: Basic base64("<key>:")`
(note the trailing colon, nothing after it).

```bash
curl https://api.moyasar.com/v1/payments -u sk_test_xxxxxxxx:
```

There are two key types, and confusing them is a security incident:

| Key | Prefix | Where it may live | What it can do |
|---|---|---|---|
| **Publishable** | `pk_test_` / `pk_live_` | Browser, mobile app, public HTML — safe to ship to clients | **Only** Create Payment / create token |
| **Secret** | `sk_test_` / `sk_live_` | Backend only — never in client code, repos, logs | Every operation |

Hard rules:

- **Never put an `sk_*` key in frontend code, mobile apps, HTML, query
  strings, or version control.** If a secret key is exposed, it must be
  regenerated in the Moyasar Dashboard immediately — treat exposure as a
  breach. Secret keys are shown only once on creation; only the ID stays
  visible afterward.
- **Cardholder data must never reach the merchant backend.** Sending raw card
  numbers to your server violates the Moyasar agreement and terminates service.
  Card data goes from the client directly to Moyasar via the publishable key
  (Moyasar Form, SDK, or a direct Create Payment call with `pk_*`).
- Use environment variables / a secrets manager for keys. Different keys per
  environment.

`pk_test_`/`sk_test_` = **test mode** (sandbox; no real money, no banking
network, no effect on live data). `pk_live_`/`sk_live_` = **live mode**. The
mode is determined entirely by the key used. Always build and verify against
test mode with the documented test cards before switching keys to live.

## Idempotency — prevents double charges

Network failures on Create Payment are ambiguous: a `5xx`/timeout/connection
error doesn't tell you whether the customer was charged. To make retries safe,
generate a UUID (v4) yourself and send it as `given_id` in the Create Payment
body. **That value becomes the payment's `id`.**

- Retry Create Payment (with the *same* `given_id`) only on: `5xx` response,
  network error, or open/read/write timeout. A `4xx` is a client error — fix
  the request, don't blind-retry. A `2xx` is conclusive — act on it.
- **A duplicate `given_id` is rejected, not replayed.** A second create with
  an already-used `given_id` returns `400 {"type":"used_given_id",
  "message":"The given_id provided has been already used with a different
  payment."}` (verified live — the older docs' *"Payment is already created."*
  is outdated). It does **not** return the original payment.
- **So the robust pattern is: verify by `given_id`.** Because `id ==
  given_id`, after an ambiguous failure don't re-interpret the create
  response — `GET /payments/{given_id}`: `200` → read its real `status`;
  `404` → not created, safe to (re)create with the same `given_id`. This is
  what `scripts/verify_payment.py` and the bundled subscription pattern do.

Generate `given_id` per payment attempt, persist it with your order before the
request, and reuse it across retries of that same attempt.

## Security best practices (this is the point of the skill)

These are non-negotiable for any production Moyasar integration:

1. **Verify every payment server-side before fulfilling the order.** The
   browser redirect to your `callback_url` (carrying `id`, `status`, `message`)
   is *not* trustworthy — it can be replayed or tampered with. On the callback,
   take the payment `id`, fetch it from your backend with the **secret key**,
   and confirm **all** of: `status == "paid"` (or `captured`), `amount` equals
   the order's expected amount, and `currency` matches. Only then mark paid.
   Use `scripts/verify_payment.py` or port its logic.
2. **A `201`/`200` does not mean "paid".** Moyasar returns `201` for a payment
   that was created but `failed` (e.g. card declined) — the failure is in
   `status` and `source.message`, not the HTTP code. Always branch on the
   `status` field, never on the HTTP status alone.
3. **Never trust client-supplied amounts for verification.** Compare the
   fetched payment's `amount`/`currency` against the order total stored on your
   server, not against anything from the browser.
4. **Use `given_id` idempotency** for every Create Payment so retries can't
   double-charge.
5. **Keep secret keys server-side only**; rotate immediately on exposure.
6. **Webhooks:** return a `2xx` *fast* (before heavy work), verify the
   `secret_token` against your configured shared secret, and make handlers
   idempotent — the same event can be delivered more than once and retried up
   to 5 times. Never rely on webhooks alone; also verify on the callback. See
   `references/webhooks.md`.
7. **Persist Moyasar payment IDs** (and `given_id`) on your orders for
   reconciliation, refunds, and support.
8. **Don't poll** when a webhook or callback will do; if you must poll a
   pending payment, back off and cap attempts.

## End-to-end flows

### A. Hosted Moyasar Form (recommended for web card payments)
Frontend renders Moyasar Form with the **publishable** key → customer pays card
data directly to Moyasar (never your server) → Moyasar redirects the browser to
your `callback_url?id=…&status=…` → **your backend fetches the payment by `id`
with the secret key and verifies status+amount+currency** → mark order paid.
Details and snippet: `references/frontend.md`.

### B. API-direct card payment with 3-D Secure
Create Payment with a card `source` (from client, using `pk_*`) and a
`callback_url`. Response `status` is usually `initiated` with a
`source.transaction_url` — redirect the payer there for the 3DS challenge. They
return to `callback_url`; then verify server-side as in flow A. `creditcard`
and `token` sources **require** `callback_url`. See `references/payments.md`.

### C. Authorize then capture (delayed capture)
Create Payment with `source.manual: true` → `status: authorized` (funds held,
not taken). Capture (full or partial) **within the window — ~14 days on mada**,
longer on other schemes. If you don't capture or void in time the issuer
releases the hold, but the status **stays `authorized`** (not updated by
Moyasar), so reconcile by elapsed time, not status alone. Cancel a hold with
Void. See `references/payment-flows.md`.

### D. Payment link / no frontend
Create an Invoice → present its `url` to the customer (Moyasar-hosted checkout)
→ on payment Moyasar `POST`s the invoice to the invoice `callback_url`
(notification only, not a redirect) and redirects the payer to `success_url`.
Still verify server-side. See `references/invoices.md`.

### E. Reverse a charge — void vs refund
**Prefer void over refund** when the window is open: void is instant and has
no fees. A `paid`/`captured` payment can be **voided only ~2 hours** after the
transaction; after that you must **refund** (`POST /payments/:id/refund`,
optional `amount`, ≤ paid/captured; status → `refunded`; live aggregation
accounts need sufficient balance). See `references/payment-flows.md`.

## Common pitfalls

- Sending a decimal amount instead of the integer minor unit.
- Treating HTTP `201`/`200` as success without checking `status`.
- Trusting the callback's `status` query param without a server-side fetch.
- Putting `sk_*` in frontend/mobile/repo, or sending card data to your server.
- Forgetting `callback_url` for `creditcard`/`token` sources (required).
- Non-empty Basic Auth password (must be empty — key as username only).
- **Missing `User-Agent`** from a non-browser client: `api.moyasar.com` is
  behind Cloudflare, which `403`-blocks the default `Python-urllib` (and
  similar) agents — the body is Cloudflare HTML, not the JSON error envelope.
  Always send an explicit `User-Agent` (verified live; see
  `references/errors.md`).
- Combining `save_card: true` with `3ds: false` → `400` "save_card options
  can't be used with MOTO transaction". **Tokenization requires 3DS.**
- Blind-retrying Create Payment without `given_id` (double-charge risk); or
  expecting a duplicate `given_id` to replay the original (it returns `400
  used_given_id` — fetch by id instead).
- Assuming a webhook fires exactly once, or doing heavy work before the `2xx`.
- Using `apimig.moyasar.com` for normal APIs (only aggregation *transfers*),
  or `api.moyasar.com` for transfers.
- Invoice `amount` minimum is `100`; bulk invoices/payouts have batch caps.
- Refunding when a void would do (void is fee-free/instant), or assuming a
  `paid`/`captured` payment is voidable after ~2 hours (then it must be
  refunded).
- Ignoring an applied coupon: when `apply_coupon` isn't disabled the charged
  amount can be **less** than requested — reconcile the `#coupon_*` response
  metadata and don't hard-fail server-side verification on the mismatch (see
  `references/coupons.md`).
- Hunting for a create-coupon API, or treating a Moyasar coupon as a
  customer-typed promo code. There is **no `POST /v1/coupons`**: Moyasar
  coupons are BIN-based and provisioned by Moyasar staff; customer-entered
  codes (`SAVE10`) must be validated in your app, which then charges the
  already-discounted `amount` (`references/coupons.md` → Path B).
- Confusing payouts with settlements (settlements are automatic; the payouts
  API does not move your Moyasar balance to your bank).
- Testing with non-documented cards / wallet amounts / STC mobiles — they
  fail; use `references/testing.md`.

Keep examples in the user's stack and idioms. The references use `curl` plus
Python/Node where the official docs do; the wire contract is identical across
languages, so translate faithfully. **For Node.js / TypeScript / Next.js, do
not paste the docs' raw Axios/`follow-redirects` snippets** (hardcoded keys,
`:id` placeholders, no verification) — use the bundled, typed
`assets/moyasar-client.ts` and the patterns in `references/nodejs-typescript.md`
instead; they encode the auth, idempotency, and server-side verification rules
above.
