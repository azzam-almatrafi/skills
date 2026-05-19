# Frontend, SDK, Apple Pay & issuer lookup

The recurring rule: the **frontend collects payment data and sends it directly
to Moyasar with the publishable key**; the **backend verifies the result with
the secret key**. Card data must never hit your server.

## Contents
- [Moyasar Form (web)](#moyasar-form-web)
- [The callback page (server-side verification)](#the-callback-page-server-side-verification)
- [React Native SDK](#react-native-sdk)
- [Apple Pay Web session](#apple-pay-web-session)
- [Retrieve Issuer (BIN lookup)](#retrieve-issuer-bin-lookup)
- [Test cards & go-live](#test-cards--go-live)

## Moyasar Form (web)

Hosted, drop-in card form. Add assets in `<head>` (pin the version you tested):

```html
<link rel="stylesheet"
  href="https://cdn.jsdelivr.net/npm/moyasar-payment-form@2.2.9/dist/moyasar.css" />
<script
  src="https://cdn.jsdelivr.net/npm/moyasar-payment-form@2.2.9/dist/moyasar.umd.min.js"></script>
```

Container + init:

```html
<div class="mysr-form"></div>
<script>
  Moyasar.init({
    element: '.mysr-form',
    amount: 1000,                 // 10.00 SAR — smallest unit
    currency: 'SAR',
    description: 'Order #1001',
    publishable_api_key: 'pk_test_xxxxxxxxxxxxxxxxx',  // pk_* only — never sk_*
    callback_url: 'https://example.com/payment-result',
    methods: ['creditcard'],
    supported_networks: ['mada', 'visa', 'mastercard', 'amex', 'unionpay'],
  });
</script>
```

`amount` is in the minor unit. The form posts card data straight to Moyasar,
then redirects the browser to `callback_url` with the payment `id` (and
`status`, `message`) in the query string.

For the **full form configuration** (every config key, the
`on_initiating`/`on_completed`/`on_failure`/`on_redirect` lifecycle callbacks,
`invoice_id`, `credit_card`/`apple_pay`/`samsung_pay` objects, saving the
payment id before 3DS, and the custom-UI tokenization path) see
`references/moyasar-form.md`.

## The callback page (server-side verification)

The redirect is **not trustworthy** — query params can be replayed or edited.
Treat the page as "take `id`, verify on the backend". Read `id`, fetch the
payment with the **secret key**, and confirm `status == "paid"` (or
`captured`), `amount == ` your stored order amount, and `currency` matches.
Only then fulfill.

```js
// Node.js — callback handler
const paymentId = req.query.id;
const res = await fetch(`https://api.moyasar.com/v1/payments/${paymentId}`, {
  headers: { Authorization: `Basic ${Buffer.from('sk_test_xxx:').toString('base64')}` },
});
const p = await res.json();
if (p.status === 'paid' && p.amount === order.amount && p.currency === order.currency) {
  // mark order paid (idempotently — the user may refresh this page)
}
```

```python
# Python — callback handler
import requests
payment_id = request.args.get("id")
p = requests.get(f"https://api.moyasar.com/v1/payments/{payment_id}",
                  auth=("sk_test_xxx", "")).json()
if p["status"] == "paid" and p["amount"] == order.amount and p["currency"] == order.currency:
    ...  # mark order paid (idempotent)
```

Prefer the bundled `scripts/verify_payment.py` — it encodes the full check
(status set, amount, currency, plus mismatch reporting) so you don't re-derive
it. Make the "mark paid" step idempotent: the payer may reload the callback,
and a webhook may also fire (`references/webhooks.md`).

## React Native SDK

`react-native-moyasar-sdk` (peer deps: `react-native-webview`,
`react-native-svg`; Node ≥ v20.19/v22.12/v23.4; iOS `pod install`; Samsung Pay
needs `dataBinding true` in `android/app/build.gradle`).

Build a `PaymentConfig` with `publishableApiKey` (pk_*), `amount` (minor unit),
`currency`, `description`, optional `givenId` (UUID v4 — same idempotency rule:
reuse on retry after 5xx/network/timeout; reusing for a *different* payment →
`400 "Payment is already created"`), `supportedNetworks`, `creditCard`,
`applePay`, `samsungPay`, `metadata`, `splits` (array of `PaymentSplit`),
`applyCoupon`. Render `<CreditCard>` / `<ApplePay>` / `<SamsungPay>` /
`<StcPay>` with `paymentConfig` + `onPaymentResult`.

Handle the result by type: `PaymentResponse` (switch on `PaymentStatus`:
`paid`/`failed`/…), `TokenResponse` (save-only token flow), or an error
(`NetworkEndpointError`, `NetworkError`, `GeneralError`, `UnexpectedError`).
Dismiss the SDK component after a result. Build-your-own-UI APIs exist
(`createPayment`, `createToken`, `sendOtp`, `CreditCardRequestSource`,
`ApplePayRequestSource`, `SamsungPayRequestSource`, `StcPayRequestSource`,
`PaymentRequest`) — for STC Pay, after `initiated` collect the OTP and call
`sendOtp(otp, source.transactionUrl)`. Still verify server-side after the SDK
returns. Notes: Samsung Pay `orderNumber` → `metadata.samsungpay_order_id` on
success; tokenization (`saveCard`) puts the token in `source.token`. Check the
SDK changelog for migration when bumping versions.

## Apple Pay Web session

For Apple Pay on the web without an Apple Developer account (Moyasar Web
Merchant Registration). Start a session:

```bash
curl --location --request GET 'https://api.moyasar.com/v1/applepay/initiate' \
  --header 'Accept: application/json' \
  --data-raw '{"validation_url":"...","display_name":"...","domain_name":"...","publishable_api_key":"pk_..."}'
```

Returns the Apple merchant session JSON (`merchantSessionIdentifier`, `nonce`,
`signature`, …) to hand to Apple Pay JS. A `404` in `errors` typically means
the domain-association file is missing at
`https://yourdomain/.well-known/apple-developer-merchantid-domain-association`.

## Retrieve Issuer (BIN lookup)

`POST /v1/source/issuer`. Body: `{ "source": { "type": "creditcard",
"number": "4111111111111111" } }` (full PAN or just the BIN — `^\d{16,19}$`).
Response: `issuer_name`, `issuer_country` (ISO-3166 alpha-2),
`issuer_card_type` (`debit`|`credit`|`charge_card`|`unspecified`),
`issuer_card_category`, `first_digits`, `last_digits`. Useful for routing,
surcharging by funding type, or showing the bank name — call it server-side or
from the client per your data-handling policy.

## Test cards & go-live

- Test mode (`pk_test_`/`sk_test_`) needs the **documented test inputs** —
  random card numbers / wallet amounts / STC mobiles fail. The full tables
  (cards per network, Apple/Samsung Pay test amounts, STC Pay mobiles & OTPs,
  payout sandbox scenarios) are bundled in `references/testing.md`.
- Apple/Samsung Pay can't be tested on a simulator/emulator.
- Go-live checklist: swap to `pk_live_`/`sk_live_`, remove test keys from
  prod config, store keys in env/secret manager, enforce HTTPS everywhere,
  verify server-side before fulfillment, confirm callback + webhook endpoints
  are reachable on the production domain, and add logging/alerts for payment
  and webhook failures.
