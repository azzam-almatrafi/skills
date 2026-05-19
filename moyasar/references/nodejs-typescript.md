# Node.js / TypeScript / Next.js (Axios)

The official Moyasar docs paste raw, non-idiomatic Axios snippets (hardcoded
keys, `:id` placeholders, `axios.request(config)`, no types, no verification).
**Don't reproduce those.** Use the bundled typed client and the Next.js
patterns here — they bake in the auth, env, idempotency, and verification
rules so each call site stays small and correct.

## Contents
- [Setup & environment](#setup--environment)
- [The bundled client](#the-bundled-client)
- [Create a payment (server-side)](#create-a-payment-server-side)
- [Callback verification (App Router)](#callback-verification-app-router)
- [Webhook handler (App Router)](#webhook-handler-app-router)
- [Refund / capture / void](#refund--capture--void)
- [Client-side Moyasar Form in Next.js](#client-side-moyasar-form-in-nextjs)
- [Next.js-specific pitfalls](#nextjs-specific-pitfalls)

## Setup & environment

```bash
npm i axios
```

Copy `assets/moyasar-client.ts` from this skill into the project, e.g.
`src/lib/moyasar.ts`. Environment variables (`.env.local`):

```
MOYASAR_SECRET_KEY=sk_test_xxxxxxxxxxxxxxxxx
NEXT_PUBLIC_MOYASAR_PUBLISHABLE_KEY=pk_test_xxxxxxxxxxxxxxxxx
```

**The Next.js footgun:** anything prefixed `NEXT_PUBLIC_` is inlined into the
browser bundle. The **secret key must never be `NEXT_PUBLIC_`**, never imported
into a Client Component, and never returned from a Server Action to the client.
Only the publishable key (`pk_*`) may be `NEXT_PUBLIC_`. The client module
imports `node:crypto` and reads `process.env.MOYASAR_SECRET_KEY` — it is
server-only by construction; keep it that way.

## The bundled client

`createMoyasarClient()` returns a typed client. Auth is HTTP Basic with the key
as username and an **empty password** (Axios `auth: { username, password: "" }`
encodes exactly `base64("<key>:")` — the trailing colon Moyasar requires; the
manual `Buffer.from(...).toString("base64")` / `follow-redirects` dance in the
docs is unnecessary). Non-2xx and network failures throw `MoyasarApiError`
(`.httpStatus`, `.type`, `.fieldErrors`, `.retryable`); verification failures
throw `PaymentVerificationError` (`.reason`). Use `toMinorUnits(10.5)` → `1050`
rather than hand-multiplying.

```ts
import { createMoyasarClient } from "@/lib/moyasar";
const moyasar = createMoyasarClient(); // reads MOYASAR_SECRET_KEY
```

For any endpoint without a dedicated method (payouts, settlements, tokens,
internal transactions, issuer lookup), use the generic typed escape hatch:

```ts
const payouts = await moyasar.request<{ payouts: unknown[]; meta: unknown }>(
  "get", "/payouts", undefined, { page: 1 },
);
```

## Create a payment (server-side)

Generate `given_id` yourself, persist it on the order **before** the call, and
reuse it on retry so an ambiguous failure can't double-charge. `creditcard`
and `token` sources require `callback_url`. Only retry on `err.retryable`
(5xx / network / timeout) — never on a 4xx.

```ts
// app/api/checkout/route.ts
import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { createMoyasarClient, MoyasarApiError, toMinorUnits } from "@/lib/moyasar";

export const runtime = "nodejs"; // node:crypto + Buffer; not edge

export async function POST(req: Request) {
  const { cardSource } = await req.json(); // tokenized/source data from client
  const order = await getCurrentOrder();    // amount/currency live on YOUR server
  const moyasar = createMoyasarClient();

  const givenId = order.moyasarGivenId ?? randomUUID();
  await saveGivenIdOnOrder(order.id, givenId); // persist before charging

  try {
    const payment = await moyasar.createPayment({
      given_id: givenId,
      amount: toMinorUnits(order.totalSar), // e.g. 10.50 -> 1050
      currency: "SAR",
      description: `Order ${order.id}`,
      callback_url: `https://example.com/payment/callback?order=${order.id}`,
      source: cardSource,
      metadata: { order_id: order.id },
    });
    // 201 does NOT mean paid. Branch on status, never the HTTP code.
    if (payment.status === "initiated" && payment.source.transaction_url) {
      return NextResponse.json({ redirect: payment.source.transaction_url });
    }
    return NextResponse.json({ status: payment.status, id: payment.id });
  } catch (err) {
    if (err instanceof MoyasarApiError && err.retryable) {
      // Safe to retry with the SAME givenId (idempotent). Enqueue/backoff.
    }
    throw err;
  }
}
```

## Callback verification (App Router)

The browser redirect to `callback_url` is untrusted — its `status`/`message`
query params can be forged. Take only `id`, fetch with the secret key, and
assert status+amount+currency server-side. `verifyPayment` does all three and
throws `PaymentVerificationError` otherwise.

```ts
// app/payment/callback/route.ts
import { NextResponse } from "next/server";
import { createMoyasarClient, PaymentVerificationError } from "@/lib/moyasar";

export const runtime = "nodejs";
export const dynamic = "force-dynamic"; // never cache a verification

export async function GET(req: Request) {
  const url = new URL(req.url);
  const paymentId = url.searchParams.get("id");
  const orderId = url.searchParams.get("order");
  if (!paymentId || !orderId) {
    return NextResponse.redirect(new URL("/payment/failed", req.url));
  }

  const order = await getOrder(orderId); // server-side source of truth
  const moyasar = createMoyasarClient();

  try {
    const payment = await moyasar.verifyPayment(paymentId, {
      expectedAmount: order.amountMinorUnits,
      expectedCurrency: order.currency,
    });
    await markOrderPaid(order.id, payment.id); // MUST be idempotent — see below
    return NextResponse.redirect(new URL("/payment/success", req.url));
  } catch (err) {
    if (err instanceof PaymentVerificationError) {
      // err.reason: status | amount | currency | not_found | http | network
      return NextResponse.redirect(new URL("/payment/failed", req.url));
    }
    throw err;
  }
}
```

Make `markOrderPaid` idempotent (e.g. no-op if the order is already paid): the
payer may refresh this URL, and the webhook will also fire for the same
payment.

## Webhook handler (App Router)

Rules: return `2xx` **fast** (before heavy work), authenticate with a
constant-time `secret_token` check, re-fetch the payment and re-verify (don't
trust the payload), and dedupe by event `id` (events can repeat and retry up to
5×).

```ts
// app/api/webhooks/moyasar/route.ts
import { NextResponse } from "next/server";
import {
  createMoyasarClient,
  safeSecretEquals,
  type MoyasarWebhookEvent,
} from "@/lib/moyasar";

export const runtime = "nodejs"; // timingSafeEqual/Buffer need Node runtime

export async function POST(req: Request) {
  const event = (await req.json()) as MoyasarWebhookEvent;

  const expected = process.env.MOYASAR_WEBHOOK_SECRET ?? "";
  if (!event?.secret_token || !safeSecretEquals(event.secret_token, expected)) {
    return new NextResponse("unauthorized", { status: 401 });
  }
  if (event.live !== (process.env.NODE_ENV === "production")) {
    return new NextResponse("wrong mode", { status: 202 }); // ack, ignore
  }

  // Ack immediately, then process out of band so we never time out.
  queueMicrotask(async () => {
    try {
      if (await alreadyProcessed(event.id)) return; // dedupe by event id
      const moyasar = createMoyasarClient();
      const payment = await moyasar.fetchPayment(event.data.id); // re-verify
      const order = await getOrderByPaymentId(payment.id);
      if (order && payment.status === "paid" && payment.amount === order.amountMinorUnits) {
        await markOrderPaid(order.id, payment.id); // idempotent
      }
      await recordProcessed(event.id);
    } catch (e) {
      // Log; reconcile via List Payments / settlements as a safety net.
    }
  });

  return NextResponse.json({ received: true }); // fast 2xx
}
```

(If you run on a platform that kills the function after the response, do the
processing via a real queue/job instead of `queueMicrotask`.)

## Refund / capture / void

```ts
await moyasar.refundPayment(id);          // full refund
await moyasar.refundPayment(id, 500);     // partial (minor units)
await moyasar.capturePayment(id);         // capture an authorized (manual) payment
await moyasar.voidPayment(id);            // cancel before settlement (no fee)
```

`capturePayment`/`voidPayment` only apply to manual-auth/un-settled payments;
see `references/payments.md` for state rules (and the "authorized stays
authorized after issuer auto-void" caveat).

## Client-side Moyasar Form in Next.js

The form runs in the browser with the **publishable** key only and posts card
data straight to Moyasar — never to your server.

```tsx
"use client";
import Script from "next/script";
import { useEffect } from "react";

declare global { interface Window { Moyasar: any } }

export function Checkout({ amountMinor }: { amountMinor: number }) {
  useEffect(() => {
    if (!window.Moyasar) return;
    window.Moyasar.init({
      element: ".mysr-form",
      amount: amountMinor,            // smallest unit
      currency: "SAR",
      description: "Order #1001",
      publishable_api_key: process.env.NEXT_PUBLIC_MOYASAR_PUBLISHABLE_KEY,
      callback_url: "https://example.com/payment/callback",
      methods: ["creditcard"],
      supported_networks: ["mada", "visa", "mastercard", "amex", "unionpay"],
    });
  }, [amountMinor]);

  return (
    <>
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/moyasar-payment-form@2.2.9/dist/moyasar.css" />
      <Script src="https://cdn.jsdelivr.net/npm/moyasar-payment-form@2.2.9/dist/moyasar.umd.min.js" strategy="afterInteractive" />
      <div className="mysr-form" />
    </>
  );
}
```

After redirect, verification happens server-side via the callback route above.
See `references/frontend.md` for non-Next form/SDK details.

## Next.js-specific pitfalls

- **Never** `NEXT_PUBLIC_`-prefix the secret key, import `@/lib/moyasar` into a
  Client Component, or return it from a Server Action to the client. Keep all
  secret-key calls in Route Handlers / Server Actions / server code.
- Set `export const runtime = "nodejs"` on routes using the client/webhook
  helpers — the Edge runtime lacks `node:crypto` and `Buffer`.
- Set `export const dynamic = "force-dynamic"` on the callback route so a
  verification is never served from cache.
- Axios error detail is in `err.response.data` (`{ type, message, errors }`) —
  the client already normalizes this into `MoyasarApiError`; surface
  `.message` and `.fieldErrors`, and only retry when `.retryable`.
- Treat `markOrderPaid` as idempotent: callback refresh + webhook means it can
  run more than once for one payment.
- Don't rely on webhooks alone (a message can be dropped after 5 retries):
  reconcile periodically with `listPayments` / settlements.
- Use `toMinorUnits()` everywhere a major amount enters the API; never send
  decimals.
