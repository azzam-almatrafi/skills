# Payments API

`POST/GET/PUT https://api.moyasar.com/v1/payments…`

A Payment represents a single charge attempt against a card or wallet. The
`source` object decides the payment method.

## Contents
- [Create Payment](#create-payment)
- [Request source objects](#request-source-objects)
- [The Payment object (response)](#the-payment-object-response)
- [Response source objects](#response-source-objects)
- [Splits](#splits)
- [Fetch Payment](#fetch-payment)
- [List Payments](#list-payments)
- [Update Payment](#update-payment)
- [Refund Payment](#refund-payment)
- [Capture Payment](#capture-payment)
- [Void Payment](#void-payment)
- [Payment status reference](#payment-status-reference)
- [Gotchas](#gotchas)

## Create Payment

`POST /v1/payments` — start a Card, Apple Pay, Samsung Pay, STC Pay, or
token-based payment. Auth: publishable key (`pk_*`) is allowed for this one
operation, so it can be called from the client; secret key also works from the
backend.

Body:

| Field | Type | Req | Notes |
|---|---|---|---|
| `given_id` | string (UUID v4) | no | Idempotency key; **becomes the payment `id`** (verified live). Strongly recommended. Reusing it → `400 {"type":"used_given_id","message":"The given_id provided has been already used with a different payment."}` (rejected, *not* replayed → recover by `GET /payments/{given_id}`). |
| `amount` | integer | **yes** | Smallest currency unit (e.g. `100` = 1.00 SAR). |
| `currency` | string | **yes** | ISO-4217, e.g. `SAR`. |
| `description` | string | no | Merchant-facing only; not shown to payer. |
| `callback_url` | uri | conditionally | URL the payer is redirected back to. **Required when `source.type` is `creditcard` or `token`.** |
| `source` | object | **yes** | Payment method — see below. |
| `metadata` | object | no | ≤30 keys; no sensitive data. |
| `apply_coupon` | boolean | no | Defaults to applying the coupon. Send `false` only to *prevent* coupon application. |
| `splits` | object[] | no | Split the amount across recipients / collect platform fee. See [Splits](#splits). |
| `recipient` | object | for AFT | Required for AFT (Account Funding Transaction) payments. |
| `sender` | object | for AFT | Required for AFT payments. |

Responses: `201` (created — see status caveat in [Gotchas](#gotchas)), `400`
(validation), `401` (bad key), `403` (key lacks permission).

```bash
curl https://api.moyasar.com/v1/payments \
  -u sk_test_xxxxxxxx: \
  -H 'Content-Type: application/json' \
  -d '{
    "given_id": "a1168bd1-47a4-4b97-8a50-dd5caaccacf2",
    "amount": 100,
    "currency": "SAR",
    "description": "Kindle Whitepaper",
    "callback_url": "https://example.com/checkout/payer-return",
    "source": {
      "type": "creditcard",
      "name": "John Doe",
      "number": "4111111111111111",
      "month": 8, "year": 2030, "cvc": 123,
      "statement_descriptor": "Century Store",
      "3ds": true, "manual": false, "save_card": false
    },
    "metadata": { "order_id": "23432" }
  }'
```

After creation, if `status` is `initiated` you must complete the challenge in
`source.transaction_url` (3DS for cards, OTP for STC Pay — see source objects).

## Request source objects

Choose `source.type`:

**`creditcard`** — `name`, `number`, `month`, `year`, `cvc` (all required),
plus optional `statement_descriptor`, `3ds` (bool, default true — keep true in
production), `manual` (bool — `true` = authorize only, capture later),
`save_card` (bool — tokenize this card on success; token returned in
`source.token`).

**`token`** — `token` (a saved card token, `token_…`), optional `cvc`,
`3ds`, `manual`. Requires `callback_url`. Charge a previously saved card from
the backend; see `references/tokens.md`.

**`applepay`** — `token` = the Apple Pay payment token obtained from Apple Pay
JS / iOS APIs; optional `manual`, `save_card`.

**`samsungpay`** — `token` = the Samsung Pay payment token; optional `manual`,
`save_card`.

**`stcpay`** — `mobile` (payer MSISDN); optional `cashier`, `branch`. Response
returns `source.transaction_url`; collect the OTP from the user and `POST` it
to that URL with body param `otp_value` to complete.

> Card data must come from the client (publishable key), never your backend.

## The Payment object (response)

Returned by create/fetch/list/update/refund/capture/void:

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | Equals `given_id` if you sent one. |
| `status` | string | `initiated`,`paid`,`authorized`,`failed`,`refunded`,`captured`,`voided`,`verified`. **Branch on this, not HTTP code.** |
| `amount` | integer | Minor unit. |
| `fee` | integer | Estimated fee incl. VAT. |
| `currency` | string | ISO-4217. |
| `refunded` / `refunded_at` | integer / ts | Amount refunded so far. |
| `captured` / `captured_at` | integer / ts | Amount captured so far. |
| `voided_at` | ts | |
| `description` | string | |
| `amount_format`,`fee_format`,`refunded_format`,`captured_format` | string | Human-readable, e.g. `"1.00 SAR"`. |
| `invoice_id` | uuid | Set if this payment paid an invoice. |
| `ip` | string | Payer IPv4, captured from the connection that created the payment — so create payments from the client device for accuracy. |
| `callback_url` | uri | |
| `created_at`,`updated_at` | ts | |
| `metadata` | object | |
| `source` | object | Response source — see below. |
| `splits` | object[] | Returned only for entities created after 2025-10 (contact support to enable). |

## Response source objects

`source` is one of (keyed by `type`):

**CreditCardResponse** — `type:"creditcard"`, `company`
(`mada`|`visa`|`master`|`amex`), `name`, `number` (masked, first6+last4),
`gateway_id`, `token` (if saved), `message` (human-readable result),
`transaction_url` (3DS URL — present only while `initiated`),
`reference_number` (RRN, 12 digits; not unique across schemes; useful for
statement tracing), `authorization_code` (6 digits, on approval),
`response_code` (ISO-8583 2-digit; `00` = approved), `issuer_name`,
`issuer_country` (ISO-3166 alpha-2), `issuer_card_type`
(`debit`|`credit`|`charge_card`|`unspecified`), `issuer_card_category`.

**ApplePayResponse / SamsungPayResponse** — `type:"applepay"|"samsungpay"`,
`name` (null for Apple Pay), `company`, `number` (last4 only), `dpan` (masked
device PAN), `gateway_id`, `reference_number`, `message`, `token`,
`response_code`, `authorization_code`, issuer fields. For Samsung Pay,
`orderNumber` (if provided) surfaces in `metadata.samsungpay_order_id` on
success — needed for refunds/chargebacks/Visa.

**StcPayResponse** — `type:"stcpay"`, `mobile`, `reference_number`, `cashier`,
`branch`, `transaction_url` (OTP challenge — POST `otp_value` here), `message`.

## Splits

Distribute a payment across recipients or collect a platform fee. Each split
object (request): `amount` (integer, non-zero), `recipient_id` (uuid),
`reference` (≤255), `description` (≤255), `fee_source` (bool — which split
absorbs processing fees), `refundable` (bool, default `true` — whether this
split reverses on refund). Response adds `recipient_type`
(`Entity`|`Platform`|`Beneficiary`).

## Fetch Payment

`GET /v1/payments/:id` (secret key). Returns the Payment object. `404` if not
found. This is the call your backend uses to **verify** a payment after the
callback — see `scripts/verify_payment.py`.

## List Payments

`GET /v1/payments` (secret key). 40/page, newest first. Query params: `page`,
`id`, `status`, `created[gt]`, `created[lt]`, `updated[gt]`, `updated[lt]`,
`metadata[<key>]`, `card_last_digits` (`^\d{4}$`; scheme payments only),
`receipt_no` (RRN, `^\d{12}$`). Response: `{ "payments": [...], "meta": {...} }`.

## Update Payment

`PUT /v1/payments/:id` (secret key). Only `description` and `metadata` are
mutable. Cannot change amount/currency/status. Returns the updated Payment.

## Refund Payment

`POST /v1/payments/:id/refund` (secret key). Body: optional `amount` (≤ paid /
captured; omit = full refund). Refunds a `paid` or `captured` payment; status
→ `refunded`. `splits` with `refundable:false` are not reversed. Errors: `400`
(e.g. already refunded / amount too high), `404`.

## Capture Payment

`POST /v1/payments/:id/capture` (secret key). Body: optional `amount` (≤
authorized; omit = full). Captures an `authorized` (manual) payment; status →
`captured`. Capture before the issuer's hold expires — see void/auth note in
[Gotchas](#gotchas).

## Void Payment

`POST /v1/payments/:id/void` (secret key, no body). Cancels a `paid`,
`authorized`, or `captured` payment **only while funds aren't settled yet**;
status → `voided`. Use void (no fee) instead of refund when the amount hasn't
settled.

## Payment status reference

| Status | Meaning |
|---|---|
| `initiated` | Created but payer hasn't completed payment (action needed: 3DS / OTP via `source.transaction_url`). |
| `paid` | Cardholder paid successfully. |
| `failed` | Payer/merchant error; reason in `source.message`. |
| `authorized` | `manual:true` hold; funds reserved, not captured. Capture later or it auto-voids. |
| `captured` | An authorized payment was captured successfully. |
| `refunded` | A paid/captured payment was refunded. |
| `voided` | A paid/authorized/captured payment was canceled before settlement. |
| `verified` | Card verified during tokenization (no charge). |

## Gotchas

- **`201`/`200` ≠ paid.** A declined card still returns `201`; the outcome is
  in `status` (+ `source.message`). Always switch on `status`.
- **`callback_url` is required** for `creditcard` and `token` sources; omitting
  it is a validation error.
- **`initiated` needs follow-up:** redirect to `source.transaction_url` (3DS)
  or POST `otp_value` (STC Pay). Don't treat `initiated` as done or as failed.
- **Manual auth expiry:** if an `authorized` payment isn't captured in time the
  issuer voids it, but Moyasar **keeps `status: authorized`** (not updated).
  Reconcile manual auths by elapsed time, not status alone.
- **`ip` accuracy:** the stored payer IP is the connection that hit Create
  Payment — create from the client device, not a server proxy, if you rely on
  it.
- **`reference_number` (RRN) is not globally unique** across schemes; don't use
  it as a primary key.
- Always verify with a server-side Fetch before fulfilling — never trust the
  browser redirect's `status` param.
