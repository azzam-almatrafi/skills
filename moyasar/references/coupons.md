# Promo codes & coupons

**Read this first — there are two different things people call a "promo code",
and only one is a Moyasar feature:**

| You want… | Use |
|---|---|
| A discount that triggers automatically by **card BIN** (e.g. "all mada Rajhi cards get 15%") | **Path A — Moyasar coupon** (below) |
| A code the **customer types at checkout** (`SAVE10`, `WELCOME`, referral codes, % or fixed off, per-user limits) | **Path B — implement in your app** (below). Moyasar has no such feature. |

**There is no API to create a coupon in Moyasar.** No `POST /v1/coupons`.
Don't look for one. Moyasar coupons are BIN-based, provisioned by Moyasar
staff, and applied automatically — the `code` (e.g. `RAJHI15`) is an internal
label, **never entered by the customer**. Anything resembling a typed promo
code is entirely your application's responsibility (Path B).

## Path A — Moyasar (BIN-based) coupon

### Creating one
Not self-serve. Provide Moyasar (account manager / support) with: name,
internal `code`, discount % (1–100), max-discount cap, start/end dates, and
the applicable **BIN list**. Moyasar creates it; it then applies automatically.

### How application works
If a payment's card BIN is in the list and the date is within validity, the
discount is applied during Create Payment and the **charged amount is reduced**
(capped at max-discount). Example: 2000.00 SAR with 15% / max 150.00 SAR →
150.00 SAR off (15% = 300 but the cap wins).

**You must reconcile.** When a coupon applies, the amount actually charged is
**less than what you requested**. The payment response carries:

```json
{ "#coupon_id": "7848a897-…", "#coupon_code": "RAJHI15",
  "#coupon_discount": 15, "#coupon_original_amount": 200000,
  "#coupon_max_discount_amount": 15000 }
```

So in server-side verification **don't assume `payment.amount` == your order
total** when coupons are possible — branch on the `#coupon_*` keys and update
your order to the discounted figure, or your books and the gateway disagree.
(This interacts with the SKILL.md "verify amount server-side" rule — when
Path A is enabled, the authoritative paid amount is `payment.amount`, and the
`#coupon_*` fields explain the delta.)

### Disable per payment
Coupons apply by default when eligible. Send `apply_coupon: false` on Create
Payment (or the form's `apply_coupon: false`) to suppress it for a specific
payment (e.g. one-coupon-per-user-per-campaign). Omit / `true` = allow.

### BIN ranges differ by source
A card product has **different BINs for the physical card vs Apple Pay** (and
other wallets) — e.g. mada card BIN `48478312`, Apple Pay `50696822`. Give
Moyasar both so the coupon matches however the customer pays.

### Pre-check: Available Coupon endpoint
`POST /v1/payments/available_coupon` — check whether a coupon *would* apply
before charging (e.g. show "You'll save 15% with this card"). Auth: publishable
or secret key. Body: `type` (`creditcard`|`applepay`|`googlepay`|`samsungpay`)
plus `number` (card — only the BIN is used) or `token` (saved card).

```bash
curl https://api.moyasar.com/v1/payments/available_coupon \
  -u sk_test_xxxx: -d "type=creditcard" -d "number=4847831234567890"
```

Returns the coupon object, or `null` with HTTP `200` if none:

```json
{ "id": "...", "name": "Rajhi Card 15%", "code": "RAJHI15",
  "discount": 15, "max_discount_amount": 15000,
  "start_date": "2026-01-01T00:00:00.000Z",
  "end_date": "2026-12-31T23:59:59.000Z",
  "disabled_at": null, "active": true, "criteria": {} }
```

`max_discount_amount` is in minor units; `active` = not disabled and in
validity. **It only checks availability — it does not apply** the coupon;
application still happens automatically in Create Payment.

### PCI DSS note
Discounting on cardholder data (BIN/IIN) normally needs PCI DSS Level 1. Since
card data flows directly to Moyasar (publishable key / Form / SDK) and Moyasar
evaluates the BIN, API merchants don't need their own PCI cert for this. Never
build BIN logic that needs raw PANs on your server.

## Path B — customer-entered promo codes (your application)

Moyasar will not store, validate, or apply a typed code. The standard,
correct pattern: **discount on your side, then charge the final amount.**

1. **Own the promo table.** Store code, type (`percent`/`fixed`), value,
   min-order, start/end, global + per-user usage limits, status.
2. **Validate server-side at checkout.** The customer submits the code to
   *your* backend; you check it exists, is active/in-date, under its limits,
   and meets min-order. **Never trust a discount or final amount sent from the
   client** — recompute it from the order + promo on the server (this is the
   same "amount is authoritative server-side" rule as everywhere in this
   skill).
3. **Compute the final amount** = order total − promo discount (floor at 0 /
   your minimum; Moyasar invoice minimum is `100` minor units).
4. **Create the Moyasar payment/invoice for that already-discounted
   `amount`.** Moyasar just charges what you send — it has no concept of your
   code. Put your code in `metadata` (e.g. `metadata.promo_code`) for
   reconciliation and support (never sensitive data).
5. **Reserve/commit the redemption atomically** so retries or double-submits
   can't over-redeem. Tie this to the payment's idempotency: reuse the same
   `given_id` for the retry of one attempt, and only mark the code "consumed"
   once the payment is verified `paid`/`captured` server-side. If the payment
   fails, release the reservation.
6. **Refunds:** if you refund, decide whether the code becomes reusable; if
   you refund partially, the discount math is yours to track.

If Path A (a Moyasar BIN coupon) is *also* enabled, both can reduce the
amount: you discount to amount X, then Moyasar may discount X further by BIN.
Reconcile using `payment.amount` (authoritative) **and** the `#coupon_*`
fields, and set `apply_coupon: false` if you don't want them to stack.

There is no bundled helper for Path B because the promo rules are
business-specific; the integration touchpoint is simply "charge the
server-computed discounted `amount`", which the existing payment/invoice
references and `assets/moyasar-client.ts` already cover.
