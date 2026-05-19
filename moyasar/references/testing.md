# Sandbox testing data

Test mode (`pk_test_`/`sk_test_`) never touches real money or banking
networks. **Only the documented inputs below produce defined results — any
other card number, Apple/Samsung Pay amount, or STC mobile/OTP fails.**

## Contents
- [Card field rules](#card-field-rules)
- [Test cards](#test-cards)
- [Apple Pay / Samsung Pay test amounts](#apple-pay--samsung-pay-test-amounts)
- [STC Pay test mobiles & OTPs](#stc-pay-test-mobiles--otps)
- [Payout sandbox scenarios](#payout-sandbox-scenarios)
- [Completing the sandbox 3DS challenge (headless)](#completing-the-sandbox-3ds-challenge-headless)
- [Non-browser clients: Cloudflare / User-Agent](#non-browser-clients-cloudflare--user-agent)

## Card field rules

Non-card-number fields must be syntactically valid: **Name** = at least two
words; **Year** = any future year; **Month** = any month valid for that expiry
year; **CVC** = any 3 digits (4 for Amex).

## Test cards

`status` is what the payment resolves to (remember a declined card still
returns HTTP `201`). Response code is the ISO-8583 gateway code.

**mada**

| Number | Status | Message | Code |
|---|---|---|---|
| `4201320111111010` | paid | APPROVED | 00 |
| `4201320000013020` | failed | UNSPECIFIED FAILURE | 99 |
| `4201320000311101` | failed | INSUFFICIENT FUNDS | 51 |
| `4201320131000508` | failed | DECLINED: LOST CARD | 41 |
| `4201321234411220` | failed | DECLINED | 05 |
| `4201322267774310` | failed | DECLINED: EXPIRED CARD | 54 |
| `4201326324640570` | failed | DECLINED: EXCEEDS WITHDRAWAL LIMIT | 61 |
| `4201321144311528` | failed | DECLINED: STOLEN CARD | 43 |

**Visa** (3DS behaviour noted)

| Number | Status | Message / 3DS note |
|---|---|---|
| `4111111111111111` | paid | APPROVED (code 00) |
| `4111114005765430` | paid | APPROVED — frictionless authentication |
| `4111118250252531` | failed | 3DS attempted but not available (enable Online Purchase at bank) — ECI 06 |
| `4111113343111067` | failed | 3DS fails during enrollment check |
| `4111116611600661` | failed | Card not enrolled in 3DS |
| `4111112205628150` | failed | 3DS fails during authentication attempt |
| `4111115784228433` | failed | Authentication rejected by issuer |
| `4111115620358287` | failed | Authentication unavailable |
| `4123120000000000` | failed | UNSPECIFIED FAILURE (99) |
| `4123120001090000` | failed | INSUFFICIENT FUNDS (51) |
| `4123450131000508` | failed | DECLINED: LOST CARD (41) |
| `4123120001090109` | failed | DECLINED (05) |
| `4123128518640738` | failed | DECLINED: EXPIRED CARD (54) |
| `4123123033308648` | failed | DECLINED: EXCEEDS WITHDRAWAL LIMIT (61) |
| `4123125276780003` | failed | DECLINED: STOLEN CARD (43) |

**Mastercard**

| Number | Status | Message | Code |
|---|---|---|---|
| `5421080101000000` | paid | APPROVED | 00 |
| `5105105105105100` | failed | UNSPECIFIED FAILURE | 99 |
| `5457210001000092` | failed | INSUFFICIENT FUNDS | 51 |
| `5204010101000000` | failed | DECLINED: LOST CARD | 41 |
| `5204730000002514` | failed | DECLINED | 05 |
| `5105107550274126` | failed | DECLINED: EXPIRED CARD | 54 |
| `5105106475101067` | failed | DECLINED: EXCEEDS WITHDRAWAL LIMIT | 61 |
| `5105107304607225` | failed | DECLINED: STOLEN CARD | 43 |

**American Express** (CVC = 4 digits)

| Number | Status | Message | Code |
|---|---|---|---|
| `340000000900000` | paid | APPROVED | 00 |
| `371111111111114` | failed | UNSPECIFIED FAILURE | 99 |
| `340033000000000` | failed | INSUFFICIENT FUNDS | 51 |
| `340012340501000` | failed | DECLINED: LOST CARD | 41 |
| `340033000000133` | failed | DECLINED | 05 |
| `340000018441278` | failed | DECLINED: EXPIRED CARD | 54 |
| `340000753060788` | failed | DECLINED: EXCEEDS WITHDRAWAL LIMIT | 61 |
| `340000418501838` | failed | DECLINED: STOLEN CARD | 43 |

**UnionPay**

| Number | Status | Message | Code |
|---|---|---|---|
| `6200000000000005` | paid | APPROVED | 00 |
| `6200000000000013` | failed | UNSPECIFIED FAILURE | 99 |
| `6200000000000021` | failed | INSUFFICIENT FUNDS | 51 |
| `6200000000000039` | failed | DECLINED: LOST CARD | 41 |
| `6200000000000047` | failed | DECLINED | 05 |
| `6200000000000054` | failed | DECLINED: EXPIRED CARD | 54 |
| `6200000000000062` | failed | DECLINED: EXCEEDS WITHDRAWAL LIMIT | 61 |
| `6200000000000070` | failed | DECLINED: STOLEN CARD | 43 |

## Apple Pay / Samsung Pay test amounts

There are **no test cards** for wallets — a real card in the wallet plus
**test API keys**. The *amount* (minor units) drives the sandbox result
(identical table for Apple Pay and Samsung Pay). Simulator/emulator does not
work; use a supported real device.

| Amount (minor) | SAR | Status | Message | Code |
|---|---|---|---|---|
| 20000–30000 | 200–300 | paid | APPROVED | 00 |
| 100000–110000 | 1000–1100 | failed | UNSPECIFIED FAILURE | 99 |
| 110100–120000 | 1101–1200 | failed | INSUFFICIENT FUNDS | 51 |
| 120100–130000 | 1201–1300 | failed | DECLINED: LOST CARD | 41 |
| 130100–140000 | 1301–1400 | failed | DECLINED | 05 |
| 140100–150000 | 1401–1500 | failed | DECLINED: EXPIRED CARD | 54 |
| 150100–160000 | 1501–1600 | failed | DECLINED: EXCEEDS WITHDRAWAL LIMIT | 61 |
| 160100–170000 | 1601–1700 | failed | DECLINED: STOLEN CARD | 43 |

Any amount outside these ranges fails.

## STC Pay test mobiles & OTPs

STC Pay has two steps. The **mobile number** drives initiation:

| Mobile | Result |
|---|---|
| `0515555555` | failed — mobile not registered for STC Pay |
| `0515555556` | failed — update info in STC Pay app first |
| `0515555557` | failed — invalid account status |
| `0515555558` | failed — OTP attempts exhausted, wait 15 min |
| `0515555559` | failed — wait 60s before a new payment |
| anything else | initiated |

Once `initiated`, the **OTP value** drives the result:

| OTP | Result |
|---|---|
| `123456` or `000000` | paid |
| `111111` | failed — insufficient balance |
| `222222` | failed — daily transaction limit exceeded |
| `333333` | failed — max transaction amount exceeded |
| `444444` | failed — STC Pay timeout |
| anything else | failed — invalid OTP |

## Payout sandbox scenarios

Use the **test secret key**. The (purpose, amount) pair drives the outcome;
status changes can take up to 5 min (internal/IPS) or 10 min (SARIE).

| Scenario | Purpose | Amount |
|---|---|---|
| `failed` | `expenses_services` | any |
| `queued` → `paid` | `credit_card_loan` | 1000 |
| `queued` → transient error → `failed` | `credit_card_loan` | 1001 |
| `queued` → `failed` (retries exhausted) | `credit_card_loan` | 1005 |
| `initiated` → `paid` | `government_dues` | any |
| `initiated` → `failed` | `payroll_benefits` | any |
| `initiated` → transient error → `paid` | `investment_house` | 1000 |
| `initiated` → transient error → `failed` | `investment_house` | 1001 |

## Completing the sandbox 3DS challenge (headless)

A card payment (or `save_card` tokenization) with default `3ds:true` returns
`status: initiated` and `source.transaction_url`. In a browser the payer just
clicks through; for **automated/CI tests** the sandbox 3DS is a fixed,
scriptable chain (verified live with `4111111111111111`). From
`transaction_url` (`…/card_auth/<id>/prepare`):

1. **prepare** → HTML with a `deviceInfoForm` POSTing to
   `…/card_auth/<id>/authenticate`. POST it with any sane device fields
   (`color_depth`, `js_enabled=true`, `language`, `screen_height`,
   `screen_width`, `time_zone`).
2. → HTML with a hidden form POSTing `creq` to `…/card_auth/<id>/acs_emulator`.
   POST `creq` (value from that form).
3. → **ACS Emulator** page with a `<select name="auth_result">`. POST to
   `…/card_auth/<id>/set_auth_result` with the desired outcome:
   `AUTHENTICATED` (success / Y), `UNAUTHENTICATED`,
   `CANCELLED_AUTHENTICATION`, `AUTHENTICATION_NOT_AVAILABLE` (U),
   `AUTHENTICATION_REJECTED` (R), `AUTHENTICATION_SERVER_ERROR` (E).
4. → tiny auto-submit form POSTing (empty body) to `…/card_auth/<id>/acs_return`.
   POST it. The payment then settles: with `AUTHENTICATED` →
   `status: paid` / `source.message: APPROVED`, and any `save_card` token
   flips `initiated` → `active`.

Drive these with a cookie jar and follow each form's `action`. This is how to
get an **active token for recurring-billing tests** without a browser. Send a
`User-Agent` on every request (next section).

## Non-browser clients: Cloudflare / User-Agent

`api.moyasar.com` is behind Cloudflare. Verified live: the default
`Python-urllib/x.y` User-Agent gets **`403` (Cloudflare error 1010)** with an
HTML body (not Moyasar's JSON error), while the identical request with an
explicit `User-Agent` returns `200`. Always set a `User-Agent` from stdlib
HTTP clients, scripts, and CI. Under heavy automated bursts you may still hit
transient Cloudflare 403s even with a good UA — back off and retry; Create
Payment stays safe to retry via `given_id`. See `references/errors.md` →
Cloudflare / WAF.
