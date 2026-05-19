# Invoices API

`…https://api.moyasar.com/v1/invoices…` (secret key for all invoice operations)

An Invoice is a Moyasar-hosted checkout / payment link. You create it, present
its `url` to the customer, and Moyasar handles the payment page. Use this when
you don't want to build a payment frontend.

## Contents
- [Create Invoice](#create-invoice)
- [The Invoice object](#the-invoice-object)
- [Bulk Create Invoices](#bulk-create-invoices)
- [List / Fetch / Update / Cancel](#list--fetch--update--cancel)
- [Invoice status reference](#invoice-status-reference)
- [Notes](#notes)

## Create Invoice

`POST /v1/invoices`. Body:

| Field | Type | Req | Notes |
|---|---|---|---|
| `amount` | integer | **yes** | Smallest unit, **minimum `100`**. |
| `currency` | string | **yes** | ISO-4217. |
| `description` | string | **yes** | Shown to the payer on the invoice. |
| `callback_url` | uri | no | Moyasar `POST`s the invoice object here when paid. **Notification only — not a redirect** (unlike payment `callback_url`). |
| `success_url` | uri | no | Where the payer is redirected after the invoice is `paid`. |
| `back_url` | uri | no | Redirect target when the payer clicks back. |
| `expired_at` | timestamp | no | ISO-8601 date or datetime. Date-only ⇒ `00:00:00` (expires at start of day). After expiry the payer can't pay. Default null (no expiry). |

Responses: `201`, `400`, `401`, `403`.

```bash
curl https://api.moyasar.com/v1/invoices \
  -u sk_test_xxxxxxxx: \
  -H 'Content-Type: application/json' \
  -d '{
    "amount": 100,
    "currency": "SAR",
    "description": "Radiator leak fix",
    "callback_url": "https://example.com/hooks/invoice-paid",
    "success_url": "https://example.com/thanks",
    "expired_at": "2038-01-19T03:14:07Z"
  }'
```

Present `response.url` (the Moyasar-hosted checkout) to the customer.

## The Invoice object

`id`, `status` (see table), `amount`, `currency`, `description`, `logo_url`
(entity logo from Dashboard), `amount_format`, `url` (hosted checkout — give
this to the payer), `callback_url`, `success_url`, `back_url`, `expired_at`,
`created_at`, `updated_at`, `metadata`, and `payments` — an array of Payment
objects (every attempt against this invoice; see `references/payments.md` for
their shape, including `source` and `splits`).

To confirm an invoice was really paid, still verify server-side: fetch the
invoice (or the underlying payment) and check `status` + `amount` + `currency`.

## Bulk Create Invoices

`POST /v1/invoices/bulk`. Body: `{ "invoices": [ {…}, … ] }` — each item has
the same fields as Create Invoice. **Max 50 per request.** Response:
`{ "invoices": [ <Invoice>, … ] }` (`201`).

## List / Fetch / Update / Cancel

- **List:** `GET /v1/invoices` — 40/page. Query: `page`, `id`, `status`,
  `created[gt]`, `created[lt]`, `metadata[<key>]`. Returns
  `{ "invoices": [...], "meta": {...} }`.
- **Fetch:** `GET /v1/invoices/:id` → Invoice object. `404` if missing.
- **Update:** `PUT /v1/invoices/:id` — body `{ "metadata": {…} }`. Only
  metadata is mutable.
- **Cancel:** `PUT /v1/invoices/:id/cancel` (no body) → status becomes
  `canceled`. `200`/`401`/`403`/`404`.

## Invoice status reference

`initiated`, `paid`, `failed`, `refunded`, `canceled`, `on_hold`, `expired`,
`voided`.

| Status | Meaning |
|---|---|
| `initiated` | Created, not yet paid. |
| `paid` | Paid successfully. |
| `failed` | Payment attempt(s) failed. |
| `refunded` | Underlying payment refunded. |
| `canceled` | Canceled via the cancel endpoint. |
| `on_hold` | Held (e.g. manual auth pending). |
| `expired` | Passed `expired_at`; can no longer be paid. |
| `voided` | Underlying payment voided. |

## Notes

- Invoice `callback_url` is a **server notification** (POST of the invoice),
  not a browser redirect. The browser redirect target is `success_url`.
- Minimum `amount` is `100` (validation `400` otherwise).
- Bulk is capped at 50; chunk larger batches client-side.
- Inspect `invoice.payments[]` to see the actual charge(s); a paid invoice's
  payment carries the `source`, RRN, etc.
