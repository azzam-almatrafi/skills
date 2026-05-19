# Response codes: gateway, 3DS, payment messages

This is for interpreting a payment that **failed at the bank** — i.e. the
request succeeded (HTTP `201`) but `status` is `failed`. For HTTP/API-level
errors (`400/401/403/404`, error `type`, retry rules) use
`references/errors.md` instead.

Where to look on a failed payment object:
- `source.message` — human-readable result.
- `source.response_code` — two-digit gateway code (card / Apple Pay; `null`
  for non-scheme or when not sent through the acquirer).
- `failure_reason` — set for 3DS failures (and payouts).

## Contents
- [Gateway response codes](#gateway-response-codes)
- [3DS failure reasons](#3ds-failure-reasons)
- [Payment error messages](#payment-error-messages)

## Gateway response codes

Two-digit ISO-8583 codes. `00` (and `08`,`10`,`11`,`16` per the scheme) =
approved; everything else = declined. Treat anything other than the approved
set as failure and surface `source.message` to the merchant, not the raw code
to the payer.

| Code | Reason | Result |
|---|---|---|
| 00 | Transaction approved | paid |
| 01 | Refer to issuer | failed |
| 02 | Refer to issuer, special | failed |
| 03 | No merchant (invalid merchant ID) | failed |
| 04 | Pick up card | failed |
| 05 | Do not honour (security / funds) | failed |
| 06 | Error (card number error) | failed |
| 07 | Pick up card, special | failed |
| 08 | Honour with identification | paid |
| 09 | Request in progress | failed |
| 10 | Approved for partial amount | paid |
| 11 | Approved, VIP | paid |
| 12 | Invalid transaction | failed |
| 13 | Invalid amount | failed |
| 14 | Invalid card number | failed |
| 15 | No issuer | failed |
| 16 | Approved, update track 3 | paid |
| 19 | Re-enter last transaction | failed |
| 21 | No action taken | failed |
| 22 | Suspected malfunction | failed |
| 23 | Unacceptable transaction fee | failed |
| 25 | Unable to locate record on file | failed |
| 30 | Format error | failed |
| 31 | Bank not supported by switch | failed |
| 33 | Expired card, capture | failed |
| 34 | Suspected fraud, retain card | failed |
| 35 | Card acceptor contact acquirer, retain card | failed |
| 36 | Restricted card, retain card | failed |
| 37 | Contact acquirer security dept, retain card | failed |
| 38 | PIN tries exceeded, capture | failed |
| 39 | No credit account | failed |
| 40 | Function not supported | failed |
| 41 | Lost card | failed |
| 42 | No universal account | failed |
| 43 | Stolen card | failed |
| 44 | No investment account | failed |
| 51 | Insufficient funds | failed |
| 52 | No cheque account | failed |
| 53 | No savings account | failed |
| 54 | Expired card | failed |
| 55 | Incorrect PIN | failed |
| 56 | No card record | failed |
| 57 | Function not permitted to cardholder | failed |
| 59 | Suspected fraud | failed |
| 60 | Acceptor contact acquirer | failed |
| 61 | Exceeds withdrawal limit | failed |
| 62 | Restricted card | failed |
| 63 | Security violation | failed |
| 64 | Original amount incorrect | failed |
| 65 | Exceeds withdrawal frequency | failed |
| 66 | Acceptor contact acquirer, security | failed |
| 67 | Capture card (suspected counterfeit) | failed |
| 75 | PIN tries exceeded | failed |
| 79 | Life cycle (Mastercard; invalid card data) | failed |
| 82 | CVV validation error | failed |
| 90 | Cutoff in progress | failed |
| 91 | Card issuer unavailable | failed |
| 92 | Unable to route transaction | failed |
| 93 | Cannot complete, violation of law | failed |
| 94 | Duplicate transaction | failed |
| 96 | System error | failed |

Actionable groupings: `51/61/65` = funds/limits (ask for another card);
`41/43/34/35/36/37/59/63/67` = lost/stolen/fraud (do not retry, ask for
another card); `54/33` = expired (recheck expiry); `55/75/38` = PIN; `82` =
CVV; `90/91/92/96` = transient (retry later).

## 3DS failure reasons

When 3-D Secure fails, `failure_reason` is one of the below and `source.message`
explains it.

| failure_reason | Meaning |
|---|---|
| `3ds_timeout` / `3ds_open_timeout` | Request / connection timed out |
| `3ds_dns_error` / `3ds_connection_error` | DNS / service connection failed |
| `3ds_authentication_error` | Authentication error occurred |
| `3ds_ds_timeout` / `3ds_ds_connection_error` | Directory Server timeout / connection error |
| `3ds_ptsp_invalid_request` / `3ds_ptsp_invalid_data` | Invalid request/data to processor |
| `3ds_ptsp_authentication_failed` | Auth with processor failed |
| `3ds_ptsp_missing_required_field` | Missing required field |
| `3ds_service_error` / `3ds_service_busy` | 3DS service error / busy |
| `3ds_acs_error` / `3ds_ds_error` | Error at ACS / Directory Server |
| `3ds_unsupported_device` / `3ds_unsupported_transaction` | Device / transaction type unsupported |
| `3ds_declined_exceeds_frequency_limit` | Exceeds auth frequency limit |
| `3ds_declined_expired_card` / `3ds_declined_invalid_card` | Expired / invalid card |
| `3ds_invalid_transaction` | Invalid transaction |
| `3ds_declined_card_unregistered` | Card not enrolled in 3DS |
| `3ds_blocked_security_failure` | Security failure |
| `3ds_blocked_stolen_card` / `3ds_blocked_suspected_fraud` | Stolen / suspected fraud |
| `3ds_confidence_issue` | Confidence issue with authentication |
| `3ds_declined_exceeds_acs_max_challenges` | Exceeds ACS max challenges |
| `3ds_decoupled_issue` | Decoupled authentication issue |
| `3ds_declined_authentication_failed` | Card authentication declined |
| `3ds_declined_challenge_bypassed` | Challenge bypassed, declined |
| `3ds_rejected_transaction` | Rejected by issuer bank |
| `3ds_unavailable_transaction` | Authentication unavailable, retry later |
| `3ds_expiration_check` | Authentication session expired |
| `3ds_unspecified` | Unspecified 3DS error |

Most 3DS failures are not retryable in place; prompt the payer to retry or use
another card, and advise contacting their bank to enable online purchase / 3DS
if it persists.

## Payment error messages

Common `source.message` strings and what they mean (show a friendly message,
not the raw string):

- **INSUFFICIENT FUNDS** — not enough balance; try another card.
- **DECLINED** — issuer declined; use an alternate card.
- **BLOCKED** — acquirer blocked (possible fraud suspicion).
- **Allowed time frame for transaction has been expired** — flow took > ~15
  min (delayed OTP SMS or slow payer); restart payment.
- **UNSPECIFIED FAILURE** — issuer declined, undefined cause; alternate card.
- **EXPIRED CARD** — card expired.
- **TIMED OUT** — could not reach issuer; retry.
- **Invalid secure code length** — wrong CVC/CVV entry.
- **REFERRED** — issuer indicates a card-number problem.
- **3-D Secure transaction attempt failed (…)** — many variants:
  `AUTHENTICATION_FAILED` (not authenticated / canceled),
  `AUTHENTICATION_ATTEMPTED` / `AUTHENTICATION_NOT_AVAILABLE` (cardholder or
  issuer not 3DS-enrolled), `CARD_NOT_ENROLLED` (enable online payment with
  bank, or card number mistyped), `Relationship not found for merchantID …
  card type VC/MC` (merchant not configured for Visa/Mastercard), `Amount
  exceeds maximum allowed limit`, `Cannot determine card brand` /
  `Unable to determine card payment` (card number mistyped),
  `Missing parameter` (authentication error).
