# Payment flows: purchase, authorize, capture, void, refund

This is the **operational lifecycle** — *when* to capture/void/refund and the
*time windows* that constrain you. For request/response field schemas use
`references/payments.md`; this file is the decision and timing guide.

## Contents
- [Two flows](#two-flows)
- [Authorization](#authorization)
- [Capture](#capture)
- [Void vs refund — choose correctly](#void-vs-refund--choose-correctly)
- [Refund](#refund)
- [Failure playbooks](#failure-playbooks)
- [Quick reference](#quick-reference)

## Two flows

- **Purchase (default):** authorize + capture in one step. Card charged
  immediately, `status: paid`. Use when you fulfill right away.
- **Authorization:** hold funds only (`source.manual: true`) →
  `status: authorized`. Capture later (charge) or void (release). Use when you
  fulfill later (stock check, ship-then-charge, pre-auth).

## Authorization

Create the payment with `source.manual: true`. Create Payment accepts the
**publishable key** (it's the one create operation `pk_*` may call), so the
hold can be initiated client-side; everything after (capture/void/refund)
needs the **secret key** server-side.

Response is `status: authorized` instead of `paid`. **Capture window: 14 days
on the mada scheme**; other schemes (Visa/Mastercard/…) may allow longer. If
you neither capture nor void in time, the issuer releases the hold and the
funds return to the cardholder — and Moyasar **keeps `status: authorized`**
(it is not auto-updated). So reconcile manual auths by elapsed time, not by
status alone.

## Capture

`POST /v1/payments/:id/capture` (secret key), only from `authorized`.
- No body → full authorized amount captured.
- `{ "amount": <minor units> }` → partial capture; **cannot exceed the
  authorized amount**. Status → `captured`.

## Void vs refund — choose correctly

**Prefer void over refund whenever the void window is still open.** A void
releases the hold instantly and incurs **no processing fees**; a refund moves
money back through the network (slower, and fees already incurred on the
original capture are not recovered).

`POST /v1/payments/:id/void` (secret key, no body) → `status: voided`. Void
applies to `authorized`, `paid`, or `captured` — but only while funds are
**not settled yet**:

| What you're voiding | Window |
|---|---|
| `authorized` hold | ~14 days on mada (longer on other schemes); after that the issuer auto-releases it |
| `paid` / `captured` | **Only ~2 hours** from the original transaction. After that, **use a refund instead** |

## Refund

`POST /v1/payments/:id/refund` (secret key), from `paid` or `captured`.
- No body → full charged amount refunded.
- `{ "amount": <minor units> }` → partial; cannot exceed the charged amount.
- Max refundable: for `paid`, the full `amount`; for `captured`, the
  `captured` amount.
- Status → `refunded`.
- **Live aggregation accounts:** your Moyasar balance must be sufficient to
  cover the refund.
- Splits with `refundable: false` are not reversed (see `references/payments.md`).

## Failure playbooks

For all three, the recovery shape is the same: re-`GET /v1/payments/:id`,
check status, retry **once**, then fall back.

- **Capture fails:** if still `authorized`, retry capture once. Still failing →
  ask the cardholder for a different card and create a new payment.
- **Void fails:** if still voidable, retry once. Still failing → for an
  `authorized` payment, do nothing (the hold expires on its own and funds
  return); for `paid`/`captured`, issue a refund instead.
- **Refund fails:** if still `paid`/`captured`, retry once. Still failing →
  contact Moyasar support with the payment ID.

Don't loop-retry; one retry then the documented fallback. Persist the payment
ID so support and reconciliation are possible.

## Quick reference

| Operation | Endpoint | Auth | Allowed from status |
|---|---|---|---|
| Authorize | `POST /v1/payments` with `source.manual: true` | Publishable (or secret) | — |
| Capture | `POST /v1/payments/:id/capture` | Secret | `authorized` |
| Void | `POST /v1/payments/:id/void` | Secret | `authorized`, `paid`, `captured` |
| Refund | `POST /v1/payments/:id/refund` | Secret | `paid`, `captured` |

See `references/error-codes.md` for `failure_reason` / `message` /
gateway-response-code interpretation when any of these fail at the bank.
