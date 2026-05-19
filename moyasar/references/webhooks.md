# Webhooks API

`…https://api.moyasar.com/v1/webhooks…` (secret key)

Webhooks push payment events to your server in real time. They are a
notification mechanism — **not a substitute for server-side verification on the
callback**, but the right tool for asynchronous status changes.

## Contents
- [Create Webhook](#create-webhook)
- [Fetch / List / Delete](#fetch--list--delete)
- [Available events](#available-events)
- [The webhook event object](#the-webhook-event-object)
- [Verifying webhooks](#verifying-webhooks)
- [Handling rules & retry strategy](#handling-rules--retry-strategy)
- [Webhook attempts (delivery log)](#webhook-attempts-delivery-log)

## Create Webhook

`POST /v1/webhooks`. Body:

| Field | Notes |
|---|---|
| `http_method` | e.g. `post`. |
| `url` | Your HTTPS endpoint. |
| `shared_secret` | A secret you choose; echoed back to you as `secret_token` on each delivery so you can authenticate it. |
| `events` | Array of event names. **Omit `events` entirely** to subscribe to all current *and future* events (global listener). |

```bash
curl -X POST https://api.moyasar.com/v1/webhooks \
  -u sk_test_xxxxxxxx: \
  -H 'Content-Type: application/json' \
  -d '{
    "http_method": "post",
    "url": "https://example.com/hooks/moyasar",
    "shared_secret": "a-long-random-string",
    "events": ["payment_paid", "payment_failed"]
  }'
```

Response: `{ id, http_method, url, created_at, events }`.

## Fetch / List / Delete

- **Fetch:** `GET /v1/webhooks/:id` → the webhook
  (`{ id, http_method, url, created_at, events }`).
- **List:** `GET /v1/webhooks` → `{ "webhooks": [...] }`. **Not paginated —
  no `meta`** (unlike *webhook attempts*, which is). Don't write paging logic
  against this list.
- **Delete:** `DELETE /v1/webhooks/:id` → `{ "message": "Webhook was deleted successfully" }`.
- **Available events:** `GET /v1/webhooks/available_events` →
  `{ "events": [...] }`.

## Available events

`payment_paid`, `payment_failed`, `payment_refunded`, `payment_voided`,
`payment_authorized`, `payment_captured`, `payment_verified`,
`payment_abandoned` — plus `balance_transferred` (settlements; aggregation
merchants only).

| Event | Fires when |
|---|---|
| `payment_paid` | Payment processed successfully. |
| `payment_failed` | Payment attempt failed. |
| `payment_refunded` | Payment refunded to the customer. |
| `payment_voided` | Payment voided/canceled before settlement. |
| `payment_authorized` | Funds reserved (manual auth). |
| `payment_captured` | Authorized funds captured. |
| `payment_verified` | Card details verified (tokenization). |
| `payment_abandoned` | Payment abandoned. |
| `balance_transferred` | A settlement was transferred to the merchant bank (aggregation only). `data` is the transfer/settlement; transfer id at `data.id`. See `references/settlements.md`. |

`GET /v1/webhooks/available_events` returns exactly what your account can
subscribe to. For `balance_transferred`, `data` is a settlement/transfer
object (not a Payment) — verify by fetching the settlement, not a payment.

## The webhook event object

| Attr | Notes |
|---|---|
| `id` | Event's unique id. |
| `type` | Event type (`payment_paid`, …). |
| `created_at` | When the event object was created. |
| `secret_token` | The `shared_secret` you set on the webhook — use it to authenticate the call. |
| `account_name` | Account where the event occurred. |
| `live` | `true` = live mode, `false` = test mode. |
| `data` | The Payment payload for the event (a Payment object). |

## Verifying webhooks

The endpoint is public, so authenticate every incoming call:

1. Compare the delivered `secret_token` against your stored `shared_secret`
   using a **constant-time** comparison; reject on mismatch.
2. Check `live` matches the environment that endpoint expects (don't let test
   events drive live fulfillment).
3. Treat the webhook as a *trigger*, then **re-fetch the payment by `data.id`
   with the secret key and re-verify status + amount + currency** before
   changing order state — same rule as the callback. Don't trust the payload
   blindly.

## Handling rules & retry strategy

- **Return a `2xx` quickly**, before any heavy logic (DB writes, emails,
  ledger updates). Do the slow work after responding, or enqueue it. A
  timeout counts as a failed delivery.
- **Be idempotent, and dedupe on the right key.** The delivered webhook
  object's `id` is the **event id** and is **stable across all retries** of
  that event. Each (re)delivery is a separate *attempt* with its own attempt
  `id` and an incrementing `retry_number` — so **dedupe on the event `id`
  (the attempt's `event_id`), never on the attempt `id` or `retry_number`**.
  Making the same change twice for one event id must be a safe no-op.
- Retry schedule if you don't return `2xx`:

| Attempt | Sent | Wait before next |
|---|---|---|
| 1 | Immediately | 1 minute |
| 2 | +1 min | 10 minutes |
| 3 | +10 min | 30 minutes |
| 4 | +30 min | 1 hour |
| 5 | +1 hour | 2 hours |
| 6 | +2 hours | message dropped |

After 5 retries (6 attempts) the message is dropped — so reconcile
periodically via List Payments / settlements; never depend solely on webhooks.

## Webhook attempts (delivery log)

- **Fetch one:** `GET /v1/webhooks/attempts/:id`.
- **List:** `GET /v1/webhooks/attempts` → `{ "webhook_attempts": [...],
  "meta": {...} }`. **Paginated** (standard `meta`) — unlike List Webhooks.

Attempt object: `id` (the attempt — differs per retry), `webhook_id` (which
webhook), `event_id` (the event — **stable across retries**; this is your
dedupe key), `event_type`, `retry_number` (1 = first send), `result` (e.g.
`success`), `message`, `response_code`, `response_headers`, `response_body`,
`created_at`. `response_*` capture **your endpoint's** reply, so use this log
to debug failed/slow deliveries and to correlate retries of one event via
`event_id`.
