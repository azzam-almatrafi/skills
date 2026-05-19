# Moyasar Form (hosted JS) — full configuration

The drop-in browser form. Quick start and the callback-verification flow are
in `references/frontend.md`; this file is the **complete config + lifecycle**
reference and the **custom-UI tokenization** path. The form runs client-side
with the **publishable key only** — card data goes straight to Moyasar.

Assets (pin the version you tested):

```html
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/moyasar-payment-form@2.2.9/dist/moyasar.css" />
<script src="https://cdn.jsdelivr.net/npm/moyasar-payment-form@2.2.9/dist/moyasar.umd.min.js"></script>
```

## Contents
- [Configuration keys](#configuration-keys)
- [Lifecycle callbacks](#lifecycle-callbacks)
- [Save the payment ID before 3DS](#save-the-payment-id-before-3ds)
- [Method-specific config](#method-specific-config)
- [Tokenization via the form](#tokenization-via-the-form)
- [Custom UI (build your own form)](#custom-ui-build-your-own-form)

## Configuration keys

`Moyasar.init({ … })`:

| Key | Req | Notes |
|---|---|---|
| `element` | yes | CSS selector or DOM element to mount into. |
| `amount` | yes | **Minor units**, min `100`. |
| `currency` | yes | ISO-4217 (e.g. `SAR`). |
| `description` | yes | Merchant reference; not shown to payer. |
| `publishable_api_key` | yes | `pk_test_`/`pk_live_` only. `pk_live_` requires HTTPS; `pk_test_` allows non-SSL for local dev. |
| `callback_url` | yes | Where the payer is redirected after payment / 3DS. |
| `methods` | no | Subset of `creditcard`,`applepay`,`samsungpay`,`stcpay` (default: all enabled). |
| `supported_networks` | no | `mada`,`visa`,`mastercard`,`amex`,`unionpay`. Default = all **except `amex`**. |
| `language` | no | `en`/`ar`/… ; inferred from `<html>` then falls back to `en`. |
| `translations` | no | Add/override strings (per language map). |
| `invoice_id` | no | Pay an existing unpaid invoice; the form `amount` must equal the invoice amount. |
| `metadata` | no | Searchable key/value pairs. |
| `fixed_width` | no | Form capped at 360px (default `true`); set `false` to disable. |
| `apply_coupon` | no | Set `false` to disable BIN coupon application (default applies if eligible — see `references/coupons.md`). |
| `statement_descriptor` | no | Text shown on the card statement. |
| `credit_card` | no | `{ save_card?: bool, manual?: bool }`. |
| `apple_pay` | if applepay | See [method-specific](#method-specific-config). |
| `samsung_pay` | if samsungpay | See [method-specific](#method-specific-config). |

## Lifecycle callbacks

All are optional async functions:

- **`on_initiating(): false | {} | {amount?,description?,callback_url?,metadata?}`**
  — fires before anything is sent to Moyasar. Return `false` to abort (last
  second validation), `true`/empty to proceed, or an object to override those
  config values for this attempt (e.g. VIP pricing / dynamic callback).
- **`on_completed(payment): Promise`** — fires when Moyasar has created the
  payment, *before* the 3DS redirect. Use it to persist the payment (see
  below). Can be async.
- **`on_failure(error)`** — handle a payment failure (string error).
- **`on_redirect(url)`** — intercept the final redirect to handle it yourself.

## Save the payment ID before 3DS

Optional but **strongly recommended**. The payer's connection can drop during
the 3DS redirect; if you saved the payment `id` (and `token`, when saving
cards) in `on_completed`, you can still verify and recover the order:

```js
Moyasar.init({
  /* …amount, currency, publishable_api_key, callback_url… */
  on_completed: async function (payment) {
    await savePaymentOnBackend(payment); // your endpoint; store payment.id
  },
});
```

Then verify server-side on the callback exactly as in `references/frontend.md`
(fetch by `id`, check `status`+`amount`+`currency`). `on_completed` does not
replace verification — it complements it.

## Method-specific config

**`apple_pay`** (required when `applepay` enabled): `country` (e.g. `SA`),
`label` (shown in the sheet), `validate_merchant_url` (your endpoint, or
`https://api.moyasar.com/v1/applepay/initiate` to use Moyasar Web
Registration — no Apple Developer account needed), optional `version`
(default 6), `merchant_capabilities` (default `supports3DS`,`supportsCredit`,
`supportsDebit`), `supported_countries` (default `['SA']`), `save_card`.

**`samsung_pay`** (required when `samsungpay` enabled): `service_id`,
`order_number` (unique; needed for refunds/chargebacks/Visa — surfaces as
`metadata.samsungpay_order_id` on success), `label`, `country`, `environment`
(`PRODUCTION` recommended even for testing — use test API key + test CSR;
`STAGE` only with a staging wallet APK), `save_card`.

**STC Pay** has no config object — just include `stcpay` in `methods`.

## Tokenization via the form

Add `credit_card: { save_card: true }` (or `apple_pay`/`samsung_pay:
{ save_card: true }`). On success the payment's `source.token` holds the saved
token; persist it in `on_completed`. Tokenization must be **enabled on the
account** for live (contact sales). Charge it later from the backend with a
`token` source — see `references/tokens.md`.

**`save_card` requires 3DS (verified live).** It cannot be combined with a
non-3DS / MOTO charge (`save_card` + `3ds:false` → `400` "save_card options
can't be used with MOTO transaction"). The form keeps 3DS on by default, so
this is only a trap if you build your own UI and disable 3DS — don't.

## Custom UI (build your own form)

Only if the hosted form can't meet your design needs. Cardholder data must
**never** post to your server — tokenize from the browser directly to Moyasar,
then charge from the backend:

1. Browser HTML form `POST`s to `https://api.moyasar.com/v1/tokens` with
   hidden fields `publishable_api_key` and `save_only=true`, plus visible
   `name`,`number`,`month`,`year`,`cvc`. (`action` must be exactly that URL.)
2. JS intercepts submit, creates the token, sends only `response.token` to
   your backend.
3. Backend creates a payment with a `token` source (secret key) and
   `callback_url`; if `status` is `initiated`, return
   `source.transaction_url` and redirect the payer there (3DS).
4. On return to `callback_url` (carrying `id`,`status`,`message`), **verify
   server-side** (fetch by `id`; check `status`+`amount`+`currency`) before
   fulfilling. Handle 4xx on token/payment creation and `failed` payments
   explicitly — error handling is your responsibility.

This is the same idempotency/verification discipline as everywhere else; see
SKILL.md and `references/tokens.md`.
