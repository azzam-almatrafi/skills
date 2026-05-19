#!/usr/bin/env python3
"""
Verify a Moyasar payment server-side before fulfilling an order.

This encodes Moyasar's #1 integration rule: never trust the browser redirect
to your callback_url. Take the payment `id`, fetch it from your backend with
the SECRET key, and confirm status + amount + currency before marking an order
paid.

Stdlib only (urllib) — no pip install needed. Python 3.7+.

As a library:

    from verify_payment import verify_payment, VerificationError
    try:
        payment = verify_payment(
            payment_id, expected_amount=1000, expected_currency="SAR",
            secret_key=os.environ["MOYASAR_SECRET_KEY"],
        )
        # payment is the full payment dict; safe to fulfill the order
    except VerificationError as e:
        # e.reason in {"status", "amount", "currency", "not_found", "http", "network"}
        ...

As a CLI:

    export MOYASAR_SECRET_KEY=sk_test_xxxx
    python verify_payment.py <payment_id> --amount 1000 --currency SAR

Exit codes: 0 = verified & safe to fulfill; 2 = verification failed (do NOT
fulfill); 3 = usage/config error.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

API_BASE = "https://api.moyasar.com/v1"

# A payment is only safe to fulfill in these states. Note `201`/`200` HTTP does
# NOT imply paid — a declined card also returns 201 with status "failed".
FULFILLABLE_STATUSES = {"paid", "captured"}


class VerificationError(Exception):
    """Raised when a payment must NOT be treated as paid.

    `reason` is one of: status, amount, currency, not_found, http, network.
    `payment` holds the fetched payment dict when available (else None).
    """

    def __init__(self, message: str, reason: str, payment: dict | None = None):
        super().__init__(message)
        self.reason = reason
        self.payment = payment


def fetch_payment(payment_id: str, secret_key: str, *, timeout: float = 15.0,
                   api_base: str = API_BASE) -> dict:
    """GET /payments/:id with HTTP Basic Auth (key as username, EMPTY password).

    The empty password is required by Moyasar — the header is
    base64("<secret_key>:") with nothing after the colon.
    """
    if not payment_id or not isinstance(payment_id, str):
        raise VerificationError("payment_id is required", "http")
    if not secret_key or not secret_key.startswith("sk_"):
        # Only the secret key can fetch a payment; pk_* will 403.
        raise VerificationError(
            "A secret key (sk_test_/sk_live_) is required to verify payments; "
            "never do this with a publishable key or from client code.",
            "http",
        )

    url = f"{api_base}/payments/{urllib.parse.quote(payment_id, safe='')}"
    token = base64.b64encode(f"{secret_key}:".encode()).decode()
    req = urllib.request.Request(url, headers={
        "Authorization": f"Basic {token}",
        "Accept": "application/json",
        # Moyasar's API is fronted by Cloudflare, which 403-blocks the default
        # "Python-urllib/x.y" User-Agent (Cloudflare error 1010). Any non-browser
        # client MUST send an explicit User-Agent or every request fails with a
        # 403 whose body is Cloudflare HTML (not Moyasar's JSON error envelope).
        "User-Agent": "moyasar-verify/1.0 (+https://api.moyasar.com)",
    })

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        if e.code == 404:
            raise VerificationError(
                f"Payment {payment_id} not found (404). Treat as NOT paid.",
                "not_found",
            ) from e
        raise VerificationError(
            f"Moyasar returned HTTP {e.code} fetching the payment: {detail}",
            "http",
        ) from e
    except urllib.error.URLError as e:
        # Network/timeout: outcome unknown — do not fulfill; retry later.
        raise VerificationError(
            f"Network error contacting Moyasar: {e.reason}. Retry later; do "
            f"not assume paid.",
            "network",
        ) from e

    try:
        return json.loads(body)
    except json.JSONDecodeError as e:
        raise VerificationError(
            f"Could not parse Moyasar response as JSON: {body[:200]}", "http"
        ) from e


def verify_payment(payment_id: str, *, expected_amount: int,
                    expected_currency: str, secret_key: str,
                    timeout: float = 15.0, api_base: str = API_BASE) -> dict:
    """Fetch and validate a payment. Returns the payment dict if and only if it
    is safe to fulfill the order; otherwise raises VerificationError.

    Validates ALL of:
      - status is in FULFILLABLE_STATUSES (paid/captured)
      - amount exactly equals expected_amount (compare against YOUR stored
        order total, never a client-supplied value)
      - currency equals expected_currency (case-insensitive)
    """
    if not isinstance(expected_amount, int) or expected_amount <= 0:
        raise VerificationError(
            "expected_amount must be a positive integer in the smallest "
            "currency unit (e.g. 1.00 SAR == 100).",
            "amount",
        )

    payment = fetch_payment(payment_id, secret_key, timeout=timeout,
                            api_base=api_base)

    status = payment.get("status")
    if status not in FULFILLABLE_STATUSES:
        src_msg = (payment.get("source") or {}).get("message")
        raise VerificationError(
            f"Payment {payment_id} status is {status!r}, not paid/captured."
            + (f" source.message: {src_msg}" if src_msg else "")
            + " Do NOT fulfill.",
            "status", payment,
        )

    amount = payment.get("amount")
    if amount != expected_amount:
        raise VerificationError(
            f"Amount mismatch for {payment_id}: Moyasar={amount}, "
            f"expected={expected_amount} (minor units). Possible tampering — "
            f"do NOT fulfill.",
            "amount", payment,
        )

    currency = (payment.get("currency") or "").upper()
    if currency != expected_currency.upper():
        raise VerificationError(
            f"Currency mismatch for {payment_id}: Moyasar={currency!r}, "
            f"expected={expected_currency.upper()!r}. Do NOT fulfill.",
            "currency", payment,
        )

    return payment


def _main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Verify a Moyasar payment before fulfilling an order.")
    parser.add_argument("payment_id", help="The Moyasar payment id (from the callback `id`).")
    parser.add_argument("--amount", type=int, required=True,
                        help="Expected amount in the SMALLEST currency unit "
                             "(1.00 SAR == 100). Use your server-side order total.")
    parser.add_argument("--currency", required=True, help="Expected ISO-4217 currency, e.g. SAR.")
    parser.add_argument("--secret-key", default=os.environ.get("MOYASAR_SECRET_KEY"),
                        help="sk_test_/sk_live_ key. Prefer the MOYASAR_SECRET_KEY "
                             "env var over passing it on the command line.")
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--api-base", default=API_BASE)
    args = parser.parse_args(argv)

    if not args.secret_key:
        print("ERROR: no secret key. Set MOYASAR_SECRET_KEY or pass --secret-key.",
              file=sys.stderr)
        return 3

    try:
        payment = verify_payment(
            args.payment_id, expected_amount=args.amount,
            expected_currency=args.currency, secret_key=args.secret_key,
            timeout=args.timeout, api_base=args.api_base,
        )
    except VerificationError as e:
        print(f"NOT VERIFIED [{e.reason}]: {e}", file=sys.stderr)
        return 3 if e.reason == "http" and "secret key" in str(e) else 2

    print(f"VERIFIED: payment {payment['id']} status={payment['status']} "
          f"amount={payment['amount']} {payment['currency']} — safe to fulfill.")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
