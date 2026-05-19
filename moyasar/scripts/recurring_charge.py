#!/usr/bin/env python3
"""
Reference recurring/subscription charge for Moyasar — the pattern verified
live against the sandbox (4/4 every-minute renewals, all paid).

What it encodes (all of these were confirmed against the real API):

  * Charge a saved card via a `token` source. An ALREADY-ACTIVE token charges
    frictionlessly (no 3DS) — ideal for merchant-initiated recurring billing.
    (Minting the token in the first place DOES require a 3DS challenge:
    `save_card` cannot be combined with `3ds:false`/MOTO.)
  * Idempotency done right: a fresh `given_id` (UUID v4) per renewal, which
    BECOMES the payment id. A duplicate `given_id` is REJECTED with
    `400 {"type":"used_given_id"}` — it is NOT replayed. So the robust
    recovery after any ambiguous failure is to GET /payments/{given_id}.
  * Server-side verification: status in {paid,captured} AND amount AND
    currency, fetched with the SECRET key.
  * Explicit User-Agent: api.moyasar.com is behind Cloudflare, which
    403-blocks the default urllib agent (error 1010).

Stdlib only. This is a *backend* job — it uses the secret key; never ship it
to a client. Env:
  MOYASAR_SECRET_KEY   sk_test_… / sk_live_…   (required)
  MOYASAR_TOKEN        token_…  saved card     (required)
  SUB_AMOUNT           minor units (default 1500)
  SUB_CURRENCY         ISO-4217  (default SAR)

  charge_subscription(token, amount, currency) -> (ok: bool, payment: dict)
"""
from __future__ import annotations

import base64
import json
import os
import time
import urllib.error
import urllib.request
import uuid

API_BASE = "https://api.moyasar.com/v1"
FULFILLABLE = {"paid", "captured"}
# Default urllib UA is Cloudflare-1010-blocked; this MUST be set.
USER_AGENT = "moyasar-recurring/1.0 (+https://api.moyasar.com)"
# Transient: outcome unknown / safe to retry the SAME given_id.
_TRANSIENT = {None, 403, 429, 500, 502, 503, 504}


def _request(method: str, path: str, secret_key: str, body: dict | None = None,
             timeout: float = 20.0):
    auth = base64.b64encode(f"{secret_key}:".encode()).decode()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API_BASE + path, data=data, method=method,
                                 headers={"Authorization": f"Basic {auth}",
                                          "Content-Type": "application/json",
                                          "Accept": "application/json",
                                          "User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            # Non-JSON body (e.g. Cloudflare HTML on a WAF 403).
            return e.code, {"_non_json": True}
    except urllib.error.URLError as e:
        return None, {"_transport": str(e.reason)}


def charge_subscription(token: str, amount: int, currency: str = "SAR", *,
                        secret_key: str | None = None,
                        callback_url: str = "https://example.com/callback",
                        description: str = "Subscription renewal",
                        max_attempts: int = 3) -> tuple[bool, dict]:
    """One renewal. Returns (ok, payment). ok == True only when the payment is
    fetched back and verified paid/captured for the exact amount+currency."""
    sk = secret_key or os.environ["MOYASAR_SECRET_KEY"]
    if not sk.startswith("sk_"):
        raise ValueError("Recurring charges are a backend op — use the SECRET key.")
    if not isinstance(amount, int) or amount <= 0:
        raise ValueError("amount must be a positive integer (minor units).")

    given_id = str(uuid.uuid4())  # persist this with your order BEFORE charging
    body = {"given_id": given_id, "amount": amount, "currency": currency,
            "description": description, "callback_url": callback_url,
            "source": {"type": "token", "token": token}}

    # Create, retrying ONLY transient/ambiguous failures with the same given_id.
    for attempt in range(1, max_attempts + 1):
        code, resp = _request("POST", "/payments", sk, body)
        if code == 400 and resp.get("type") == "used_given_id":
            break  # already created on a prior attempt — fall through to fetch
        if code in _TRANSIENT:
            time.sleep(2 * attempt)
            continue
        break

    # Source of truth: id == given_id, so verify by fetching it. This is
    # correct whether create returned 201, a transient error, or used_given_id.
    fcode, payment = _request("GET", f"/payments/{given_id}", sk)
    if fcode == 404:  # never created -> one more create then re-fetch
        _request("POST", "/payments", sk, body)
        time.sleep(2)
        fcode, payment = _request("GET", f"/payments/{given_id}", sk)

    if fcode != 200:
        return False, {"given_id": given_id, "fetch_code": fcode, **(payment or {})}
    ok = (
        payment.get("status") in FULFILLABLE
        and payment.get("amount") == amount
        and (payment.get("currency") or "").upper() == currency.upper()
    )
    return ok, payment


def _main() -> int:
    token = os.environ["MOYASAR_TOKEN"]
    amount = int(os.environ.get("SUB_AMOUNT", "1500"))
    currency = os.environ.get("SUB_CURRENCY", "SAR")
    ok, p = charge_subscription(token, amount, currency)
    pid = p.get("id")
    print(f"{'OK  ' if ok else 'FAIL'} status={p.get('status')} "
          f"id={pid} amount={p.get('amount')} {p.get('currency')} "
          f"src={p.get('source', {}).get('message')}")
    # Run this on your schedule (cron / a 60s loop / a job queue). Each call
    # uses its own given_id, so it is a distinct, idempotent renewal.
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(_main())
