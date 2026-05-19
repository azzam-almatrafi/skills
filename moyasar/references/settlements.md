# Settlements & Transfers API (reconciliation)

Settlements describe money Moyasar pays out to the merchant's bank, with
per-transaction lines for accounting. All endpoints use the **secret key**.

> Two different hosts:
> - Settlements: `https://api.moyasar.com/v1/settlements…`
> - Aggregation **Transfers**: `https://apimig.moyasar.com/v1/transfers…`
>   (only for Moyasar **aggregation** merchants — a separate, legacy host).

Moyasar settles successful payments to the merchant bank account on a
schedule — by default **twice a week (Monday & Thursday)**, configurable per
agreement. Settlement data is delivered via **email** (CSV + PDF + invoice)
and via the **API** (JSON only — no PDF/invoice files). This is automatic;
you don't trigger it.

> **Aggregation vs facilitation.** These APIs and the `balance_transferred`
> webhook are for **aggregation** merchants. **Facilitation (direct bank)**
> merchants instead obtain a *Point of Sale (POS) Report* from their acquirer
> bank (with their Merchant ID) — not from Moyasar.

## Contents
- [List Settlements](#list-settlements)
- [Fetch Settlement](#fetch-settlement)
- [Settlement object](#settlement-object)
- [List Settlement Lines](#list-settlement-lines)
- [CSV file format](#csv-file-format)
- [Settlement notification webhook](#settlement-notification-webhook)
- [Aggregation Transfers](#aggregation-transfers)

## List Settlements

`GET /v1/settlements`. Query: `page`, `id`, `created[gt]`, `created[lt]`.
Returns `{ "settlements": [...], "meta": {...} }` (40/page).

## Fetch Settlement

`GET /v1/settlements/:id` → a Settlement object. `404` if missing.

## Settlement object

`id`, `recipient_type` (`Entity`|`Platform`|`Beneficiary`), `recipient_id`,
`currency`, `source_currency`, `invoicing_currency`, `amount` (gross, before
the bank-transfer fee), `fee` (settlement/bank-transfer fee incl. VAT), `tax`
(VAT), `invoicing_fee`, `invoicing_tax`, `invoicing_ex_rate` (float; converts
invoicing_fee → fee), `reference` (bank transfer ref; may be null until
available), `settlement_count` (number of transactions in it), `invoice_url`
(settlement invoice PDF), `csv_list_url`, `pdf_list_url` (transaction lists;
PDF not always present), `created_at`.

## List Settlement Lines

`GET /v1/settlements/:id/lines?page=N` → `{ "lines": [...], "meta": {...} }`.
Each line is one settled operation:

- `payment_id`, `type` — `payment`, `refund`, `void`, `fee`,
  `platform_duties`, `other_duties`, `chargeback`, `chargeback_penalty`,
  `installment` (definitions below).
- `currency`, `source_currency`, `invoicing_currency`.
- `payment_amount` (total payment), `amount` (net to merchant — can be
  negative), `settlement_amount` (net in settlement currency).
- `fee` (incl. tax), `tax`, `invoicing_fee`, `invoicing_tax`.
- `i_ex_rate` (fee → invoicing_fee), `r_ex_rate` (amount → settlement_amount).
- `reference_number` (RRN, 12 digits), `authorization_code` (6 digits), `ip`.
- `transacted_at` — when the settled transaction occurred: purchase ⇒
  `created_at`; capture ⇒ `captured_at`; refund ⇒ `refunded_at`; void ⇒
  `voided_at`.
- `splits` (currently always `null`), `custom_splits[]`, `is_custom_split`,
  `split_reference`, `split_description`.
- `source` (simplified: CreditCardSource / DevicePaymentSource (Apple/Samsung)
  / StcPaySource — issuer fields, masked PAN, etc.), `metadata`.

Line `type` meanings: `payment` = successful/captured charge; `refund` =
returned to payer; `void` = canceled, no fee; `fee` = platform processing fee;
`platform_duties` = charges from entity to platform; `other_duties` =
miscellaneous; `chargeback` = dispute refund; `chargeback_penalty` = penalty on
a lost dispute; `installment` = recurring loan-repayment deduction via partner.

## CSV file format

The emailed settlement CSV (UTF-8) columns: `payment_id`, `description`,
`scheme` (visa/mastercard/mada/amex/unionpay), `source` (Credit Card / Apple
Pay), `type` (same set as settlement-line `type`: pay, refund, void, fee,
platform_duties, other_duties, chargeback, chargeback_penalty, installment),
`currency`, `amount`, `net_amount` (after fees), `fee`, `vat`, `total_fee`
(fee incl. VAT), `transaction_date` (UTC), then one extra column per payment
metadata key. (Open in Excel via Data → Get Data → From Text, delimiter
`Comma`, file origin `Unicode (UTF-8)`.)

## Settlement notification webhook

Aggregation-only. Configure a **live** webhook subscribed to the
`balance_transferred` event (Dashboard → Settings → Webhooks). On each
settlement Moyasar POSTs the standard webhook envelope; the transfer id is at
`data.id`:

```json
{
  "id": "762760de-…", "type": "balance_transferred",
  "created_at": "2024-02-18T15:57:27+00:00",
  "secret_token": "…", "account_name": "Test Merchant", "live": true,
  "data": { "id": "10af7e38-…", "recipient_type": "Entity",
    "recipient_id": "…", "currency": "SAR", "amount": 561743,
    "fee": 0, "tax": 0, "reference": null, "transaction_count": 2,
    "created_at": "2023-09-06T15:46:35.518Z" }
}
```

Authenticate it exactly like payment webhooks (constant-time `secret_token`
check, `live` match, then fetch the settlement/transfer by `data.id` to
reconcile). See `references/webhooks.md`.

## Aggregation Transfers

Only for Moyasar **aggregation** merchants. Host: `https://apimig.moyasar.com`.
Auth: same Basic Auth with the secret key (`-u sk_xxx:` /
`Authorization: Basic base64("sk_xxx:")`). Paginated, 40/page.

- **List transfers:** `GET /v1/transfers` →
  `{ "transfers": [ { id, recipient_type, recipient_id, currency, amount,
  fee, tax, reference, transaction_count, created_at }, … ], "meta": {…} }`.
- **Show transfer:** `GET /v1/transfers/:id` → single transfer object.
- **List transfer lines:** `GET /v1/transfers/:id/lines` →
  `{ "lines": [ { payment_id, type, amount, fee, tax }, … ], "meta": {…} }`.

Auth failure on these returns
`{ "type": "authentication_error", "message": "Invalid authorization credentials", "errors": null }`.

These are read-only reconciliation endpoints — pull them on a schedule and
match `payment_id` / `reference_number` back to your orders.
