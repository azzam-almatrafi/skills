# Payouts & Internal Transactions API

`…https://api.moyasar.com/v1/payout_accounts…`, `/payouts…`,
`/internal_transactions…` (secret key for all).

Payouts send money **out** to a beneficiary (bank IBAN or wallet). You first
register a payout *account* (the funding source), then create payouts from it.
Internal transactions move funds between Moyasar wallets you control.

> **Payouts ≠ settlements.** This API does **not** move your Moyasar balance to
> your own bank account — that is **Settlements**, which Moyasar runs
> automatically (see `references/settlements.md`). Payouts debit a registered
> payout account (your bank/wallet B2B account) and send to a beneficiary.

## Contents
- [Payout Accounts](#payout-accounts)
- [Create Payout](#create-payout)
- [The Payout object](#the-payout-object)
- [List / Fetch Payout](#list--fetch-payout)
- [Bulk Payout](#bulk-payout)
- [Internal Transactions](#internal-transactions)
- [Notes](#notes)

## Payout Accounts

**Create:** `POST /v1/payout_accounts`. Body: `account_type`
(`bank` | `wallet`, required), `properties` (object, required — public info,
e.g. `{ "iban": "SA84…" }`), `credentials` (object, required — secret info,
e.g. provider client id/secret). Response (`201`): `id`, `account_type`,
`currency`, `properties`, `created_at` (credentials are **not** echoed back).

**List:** `GET /v1/payout_accounts?page=N` → `{ "payout_accounts": [...],
"meta": {...} }`.

**Fetch:** `GET /v1/payout_accounts/:id` → the account object. `404` if missing.

## Create Payout

`POST /v1/payouts`. Body:

| Field | Type | Req | Notes |
|---|---|---|---|
| `source_id` | uuid | **yes** | The payout account id to debit. |
| `sequence_number` | string | no | 16-digit reference; Moyasar generates one if omitted. |
| `amount` | integer | **yes** | Smallest currency unit. |
| `purpose` | string | **yes** | Enum — see below. |
| `destination` | object | **yes** | Bank or wallet — see below. |
| `comment` | string | no | Shows on the payout. |
| `metadata` | object | no | |

`purpose` ∈ `bills_or_rent`, `expenses_services`, `purchase_assets`,
`saving_investment`, `government_dues`, `money_exchange`, `credit_card_loan`,
`gift_or_reward`, `personal`, `investment_transaction`, `family_assistance`,
`donation`, `payroll_benefits`, `online_purchase`, `hajj_and_umra`,
`dividend_payment`, `government_payment`, `investment_house`,
`payment_to_merchant`, `own_account_transfer`.

`destination` is one of:
- **Bank:** `{ "type": "bank", "iban", "name", "mobile", "country", "city" }`
  (all required).
- **Wallet:** `{ "type": "wallet", "mobile" }`.

```bash
curl https://api.moyasar.com/v1/payouts \
  -u sk_test_xxxxxxxx: \
  -H 'Content-Type: application/json' \
  -d '{
    "source_id": "ae50a35c-df42-4eff-ba26-f8bc28d2af81",
    "amount": 100,
    "purpose": "bills_or_rent",
    "destination": {
      "type": "bank", "iban": "SA5330400108057386290014",
      "name": "Faisal Alghurayri", "mobile": "0555555555",
      "country": "SA", "city": "Riyadh"
    },
    "comment": "Invoice 4471"
  }'
```

Responses: `201`, `400`, `401`, `403`.

## The Payout object

`id`, `source_id`, `sequence_number`, `channel`
(`internal` | `ips` | `sarie` — the rail used), `status`
(`queued` | `initiated` | `paid` | `failed` | `canceled` | `returned`),
`amount`, `currency`, `purpose`, `comment`, `destination`, `message`
(human-readable status), `failure_reason` (classification, if any),
`created_at`, `updated_at`, `metadata`.

## Channel, timeline & flow

Moyasar picks the `channel` automatically:

| Channel | When | Delivery |
|---|---|---|
| `internal` | Source & destination same bank/wallet | Instant |
| `ips` | ≤ 20,000 SAR and both sides support IPS | Semi-instant |
| `sarie` | > 20,000 SAR | Semi-instant, workdays 09:00–15:00 (else queued) |

`internal` is synchronous (status resolves on create); `ips`/`sarie` are
**asynchronous** — status moves `queued`/`initiated` → `paid`/`failed` later.
On a transient error (e.g. timeout to the bank) the flow also becomes async:
Moyasar retries for a few minutes, then marks `failed` if exhausted. **Poll
`GET /v1/payout/:id` every 5–10 minutes, or use a webhook**, rather than
assuming the create response is final.

**Idempotency:** because creation keys on `sequence_number`, retrying a
create with the *same* `sequence_number` will not double-send. Generate and
persist one per payout before sending; reuse it on retry. (Status changes can
take up to ~5 min internal/IPS, ~10 min SARIE.)

## List / Fetch Payout

- **List:** `GET /v1/payouts?page=N` → `{ "payouts": [...], "meta": {...} }`.
- **Fetch:** `GET /v1/payout/:id` (note: **singular** `payout`) → Payout
  object. `404` if missing.

## Bulk Payout

`POST /v1/payouts/bulk`. Body: `source_id` (uuid) + `payouts` array (each:
`sequence_number?`, `amount`, `purpose`, `destination`, `comment?`,
`metadata?`). Response: `{ "payouts": [ <Payout>, … ] }` (`201`).

## Internal Transactions

Transfer an amount from the caller's `current` wallet to a recipient's
`current` wallet (recipient may be an `Entity`, `Platform`, or `Beneficiary`).
**Result is instant — success or failure.** There is no revert; the recipient
must transfer back.

**Create:** `POST /v1/internal_transactions`. Body: `recipient_id` (uuid,
req), `currency` (req), `amount` (integer, req), `description` (string),
`metadata`. Response (`200`): `id`, `recipient_type`, `recipient_id`,
`currency`, `amount`, `transfer_id` (set once settled), `description`,
`created_at`, `updated_at`, `settled_at`, `metadata`.

**List:** `GET /v1/internal_transactions`. Query: `page`, `id`, `currency`,
`created_at[gt|lt]`, `updated_at[gt|lt]`, `settled_at[gt|lt]`. This is an
infinite-scroll list: `meta.total_count` is always `null` — page until
`next_page` is null.

## Notes
- Payout creation is irreversible from your side; double-check `iban`/`amount`/
  `purpose`. Use `sequence_number` (or `metadata`) for your own idempotency and
  reconciliation, and persist the returned `id`.
- Some transfer types are restricted by account configuration; a `400`/`403`
  may mean the operation isn't enabled for your account.
- `credentials` you send when creating a payout account are write-only and
  never returned — store your own copy securely if you need it. The exact
  `properties`/`credentials` keys are provider-specific and issued by your
  bank/wallet after B2B enablement: Al Rajhi (`iban` / `company_code`,`cert`,
  `key`), SNB (`iban`,`corporate_id` / `client_id`,`client_secret`,`key`),
  ANB (`iban` / `client_id`,`client_secret`), STC Pay wallet
  (`merchant_id` / `cert`,`key`). Supported today: Al Rajhi, SNB, ANB banks;
  STC Pay wallet (URPay coming).
- Use ISO country codes in `destination.country` (e.g. `SA`).
- Sandbox: outcome is driven by the (`purpose`,`amount`) pair — see
  `references/testing.md` → Payout sandbox scenarios.
