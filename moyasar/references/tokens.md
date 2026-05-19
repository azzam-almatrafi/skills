# Tokens API (saved cards / tokenization)

`…https://api.moyasar.com/v1/tokens…`

A Token is a saved representation of a card that lets you charge it later
(recurring billing, one-click checkout) without handling card data. **Token
creation happens on the frontend, directly to Moyasar, with the publishable
key** — exactly like a payment, card data never touches your backend.
Fetch/delete use the secret key from the backend.

> **Account enablement:** tokenization must be enabled on your account before
> use in **live** (contact Moyasar sales). Tokenizable schemes: mada, Visa,
> Mastercard, UnionPay.

## Two ways to get a token

1. **Save-on-payment:** set `source.save_card: true` (card / Apple Pay /
   Samsung Pay) when creating a payment. On success the Payment's
   `source.token` holds the new token. (SDK: `tokenizeCard`/`saveCard` =
   `true`; `paymentResult.source.token`.)
2. **Save-only (no charge):** create a token directly. The card is verified
   (3DS) but not charged; token status goes `initiated` → `active`.

> **Tokenization requires 3DS (verified live).** `save_card: true` combined
> with `source.3ds: false` is rejected: `400 {"type":"invalid_request_error",
> "message":"Wrong number of parameters","errors":"save_card options can't be
> used with MOTO transaction"}`. So you cannot mint a token via a frictionless
> MOTO charge — the card must go through the 3DS challenge (which is what
> moves the token `initiated` → `active`). Subsequent *charges of an already-
> active token* are frictionless and need no 3DS (verified).

## Create Token

`POST /v1/tokens` with the **publishable key**, from the client:

```bash
curl -X POST https://api.moyasar.com/v1/tokens \
  -u pk_test_xxxxxxxx: \
  -d name="Mohammed Ali" \
  -d number="4111111111111111" \
  -d month="09" \
  -d year="27" \
  -d cvc="911" \
  -d callback_url="https://mystore.com/thanks"
```

Request fields: `name`, `number`, `month`, `year`, `cvc`, `callback_url`. A
2-digit `year` (e.g. `"27"`) is accepted and normalized to 4-digit (`"2027"`)
in responses.

On success the token comes back with `status: "initiated"` and a populated
`verification_url`: send the cardholder there (3DS) — `callback_url` is where
they return. The token only becomes `active`, and only then charges
successfully, after that verification completes.

**Create-Token errors do not use the standard error envelope.** A failed
create returns a bare `{ "message": "…" }` (no `type`, no `errors`). This is
unlike Fetch/Delete *not-found*, which return the standard
`{ "type": "api_error", "message": "Object not found", "errors": null }`. Code
the create path to read `message` directly and not assume `type`/`errors`
exist.

## The Token object

| Attr | Notes |
|---|---|
| `id` | `token_…` (not a UUID). |
| `status` | `initiated` \| `active` \| `inactive`. |
| `brand` | `visa`,`master`,`mada`,`amex`,`unionpay`. |
| `funding` | `credit` \| `debit`. |
| `country` | Issuing country. |
| `month`,`year` | Expiry. |
| `name` | Cardholder name. |
| `last_four` | Last 4 digits. |
| `verification_url` | The 3DS verification URL — populated on Create (`initiated`); `null` once verified and on Fetch. |
| `message` | Nullable human-readable note (e.g. `"Card stored successfully"`); `null` otherwise. |
| `metadata` | Default null. |
| `created_at`,`updated_at` | ISO-8601. |

### Token status reference
| Status | Meaning |
|---|---|
| `initiated` | Created; cardholder hasn't verified the card yet. |
| `active` | Cardholder completed verification — token is usable. |
| `inactive` | Verification failed or the card expired. |

## Fetch Token

`GET /v1/tokens/:id` with the **secret key**:

```bash
curl -X GET https://api.moyasar.com/v1/tokens/token_x6okRgkZJrhgDHyqJ9zztW2X1k \
  -u sk_test_xxxxxxxx:
```

Returns the Token object (with `verification_url: null`). Use this to check
`status` before charging and to show saved-card display fields. A missing
token → `{ "type": "api_error", "message": "Object not found", "errors": null }`.

## Delete Token

`DELETE /v1/tokens/:id` with the **secret key**. On success returns an empty
body with HTTP **`204`**. A missing/already-deleted token →
`{ "type": "api_error", "message": "Object not found", "errors": null }`.
Tokens also auto-invalidate (`inactive`) when the card expires.

## Charging a saved token

Create a payment with a `token` source (backend, secret key). `callback_url` is
**required** (token sources may still trigger 3DS):

```bash
curl https://api.moyasar.com/v1/payments \
  -u sk_test_xxxxxxxx: \
  -H 'Content-Type: application/json' \
  -d '{
    "amount": 5000, "currency": "SAR",
    "description": "Subscription renewal",
    "callback_url": "https://example.com/checkout/payer-return",
    "source": { "type": "token", "token": "token_x6okRgkZJrhgDHyqJ9zztW2X1k" }
  }'
```

Then verify the resulting payment server-side (status + amount + currency) like
any other payment — see `references/payments.md` and
`scripts/verify_payment.py`.

### Recurring billing / subscriptions (verified live)

Charging an **already-`active`** token is **frictionless — no 3DS** (verified:
`creditcard` source returns `status: paid`, `APPROVED`, no
`transaction_url`, with or without `3ds:false`). That makes
merchant-initiated recurring billing straightforward: on each cycle create a
payment with the `token` source, a **fresh `given_id` per renewal**, then
verify server-side. Because a duplicate `given_id` is *rejected*
(`used_given_id`), not replayed, recover from any ambiguous failure by
`GET /payments/{given_id}` (the id **is** the given_id). The bundled
**`scripts/recurring_charge.py`** implements exactly this pattern
(stdlib, env-driven, Cloudflare User-Agent set) and was validated with
back-to-back every-minute renewals all settling `paid`. Run it from cron / a
job queue / your scheduler. Minting the token still needs the one-time 3DS
challenge (see the note in [Two ways to get a token](#two-ways-to-get-a-token)).

## Notes
- Only `active` tokens can be charged successfully; check `status` before use.
- Token creation needs the **publishable** key and runs client-side; fetch and
  delete need the **secret** key server-side.
- Store only the `token` id and display fields (`brand`, `last_four`,
  expiry) — never anything more.
- Without the SDK/Form, build the save-only flow in the browser: an HTML form
  POSTing to `/v1/tokens` with hidden `publishable_api_key` + `save_only=true`.
  Full walkthrough: `references/moyasar-form.md` → Custom UI.
- Sandbox token testing uses the standard test cards
  (`references/testing.md`).
