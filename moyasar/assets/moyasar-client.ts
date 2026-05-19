/**
 * Moyasar API client — typed, Axios-based, framework-agnostic.
 *
 * Drop this into a Next.js / Node.js TypeScript project (e.g.
 * `src/lib/moyasar.ts`) and use it from SERVER code only — it carries the
 * secret key. Never import it into a Client Component, and never expose the
 * secret via a NEXT_PUBLIC_ env var.
 *
 *   import { createMoyasarClient } from "@/lib/moyasar";
 *   const moyasar = createMoyasarClient();            // reads MOYASAR_SECRET_KEY
 *   const payment = await moyasar.verifyPayment(id, { // throws if not safe
 *     expectedAmount: 1000, expectedCurrency: "SAR",
 *   });
 *
 * Only dependency: axios (`npm i axios`).
 */
import axios, {
  type AxiosInstance,
  type AxiosError,
  isAxiosError,
} from "axios";
import { timingSafeEqual } from "node:crypto";

export const MOYASAR_API_BASE = "https://api.moyasar.com/v1";
/** Aggregation *transfers* live on a different host (see settlements ref). */
export const MOYASAR_MIG_BASE = "https://apimig.moyasar.com/v1";

export type PaymentStatus =
  | "initiated"
  | "paid"
  | "authorized"
  | "failed"
  | "refunded"
  | "captured"
  | "voided"
  | "verified";

export type InvoiceStatus =
  | "initiated"
  | "paid"
  | "failed"
  | "refunded"
  | "canceled"
  | "on_hold"
  | "expired"
  | "voided";

/** Only these mean money is actually collected and the order can ship. */
export const FULFILLABLE_STATUSES: ReadonlySet<PaymentStatus> = new Set([
  "paid",
  "captured",
]);

export interface PaymentSource {
  type: string;
  message?: string | null;
  transaction_url?: string | null;
  [key: string]: unknown;
}

export interface Payment {
  id: string;
  status: PaymentStatus;
  amount: number;
  fee: number;
  currency: string;
  refunded: number;
  refunded_at: string | null;
  captured: number;
  captured_at: string | null;
  voided_at: string | null;
  description: string | null;
  amount_format: string;
  fee_format: string;
  refunded_format: string;
  captured_format: string;
  invoice_id: string | null;
  ip: string | null;
  callback_url: string | null;
  created_at: string;
  updated_at: string;
  metadata: Record<string, unknown> | null;
  source: PaymentSource;
  splits?: unknown[];
}

export interface Invoice {
  id: string;
  status: InvoiceStatus;
  amount: number;
  currency: string;
  description: string;
  logo_url: string | null;
  amount_format: string;
  url: string;
  callback_url: string | null;
  success_url: string | null;
  back_url: string | null;
  expired_at: string | null;
  created_at: string;
  updated_at: string;
  metadata: Record<string, unknown> | null;
  payments: Payment[];
}

export interface ListMeta {
  current_page: number;
  next_page: number | null;
  prev_page: number | null;
  total_pages: number;
  /** `null` for infinite-scroll lists (e.g. internal transactions). */
  total_count: number | null;
}

export interface PaymentList {
  payments: Payment[];
  meta: ListMeta;
}
export interface InvoiceList {
  invoices: Invoice[];
  meta: ListMeta;
}

export interface CreatePaymentInput {
  /** UUID v4 you generate. Becomes the payment id; enables safe retries. */
  given_id?: string;
  /** Smallest currency unit — integer. 1.00 SAR === 100. Use toMinorUnits(). */
  amount: number;
  currency: string;
  description?: string;
  /** Required when source.type is "creditcard" or "token". */
  callback_url?: string;
  source: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  apply_coupon?: boolean;
  splits?: unknown[];
  recipient?: Record<string, unknown>;
  sender?: Record<string, unknown>;
}

export interface CreateInvoiceInput {
  amount: number; // minimum 100
  currency: string;
  description: string;
  callback_url?: string;
  success_url?: string;
  back_url?: string;
  expired_at?: string;
  metadata?: Record<string, unknown>;
}

/** Shape of a Moyasar error body (`error.response.data`). */
export interface MoyasarErrorBody {
  type?: string;
  message?: string;
  // Observed live: `errors` is sometimes a per-field map, sometimes a plain
  // string (e.g. "save_card options can't be used with MOTO transaction"),
  // and often null. Don't assume the map shape.
  errors?: Record<string, string[]> | string | null;
}

/** Thrown for any non-2xx Moyasar response or transport failure. */
export class MoyasarApiError extends Error {
  readonly httpStatus?: number;
  readonly type?: string;
  /** Per-field map, a plain string, or null — Moyasar varies. */
  readonly fieldErrors?: Record<string, string[]> | string | null;
  /** True for 5xx / network / timeout — the only cases worth retrying. */
  readonly retryable: boolean;

  constructor(
    message: string,
    init: {
      httpStatus?: number;
      type?: string;
      fieldErrors?: Record<string, string[]> | string | null;
      retryable: boolean;
    },
  ) {
    super(message);
    this.name = "MoyasarApiError";
    this.httpStatus = init.httpStatus;
    this.type = init.type;
    this.fieldErrors = init.fieldErrors ?? null;
    this.retryable = init.retryable;
  }
}

export type VerificationFailureReason =
  | "status"
  | "amount"
  | "currency"
  | "not_found"
  | "http"
  | "network";

/**
 * Thrown by verifyPayment when a payment must NOT be treated as paid.
 * Inspect `reason` to decide messaging; never fulfill on this error.
 */
export class PaymentVerificationError extends Error {
  readonly reason: VerificationFailureReason;
  readonly payment?: Payment;
  constructor(
    message: string,
    reason: VerificationFailureReason,
    payment?: Payment,
  ) {
    super(message);
    this.name = "PaymentVerificationError";
    this.reason = reason;
    this.payment = payment;
  }
}

export interface MoyasarClientOptions {
  /** Defaults to process.env.MOYASAR_SECRET_KEY. Server-side only. */
  apiKey?: string;
  baseUrl?: string;
  timeoutMs?: number;
  /** Override the User-Agent (Cloudflare blocks unrecognized agents). */
  userAgent?: string;
}

/**
 * Convert a major-unit amount to the integer minor unit Moyasar expects.
 * 10.5 SAR -> 1050. Rounds to avoid float drift. Passing decimals to the API
 * is the single most common, costly Moyasar bug — always go through this.
 */
export function toMinorUnits(major: number, fractionDigits = 2): number {
  return Math.round(major * 10 ** fractionDigits);
}

function normalizeError(err: unknown): MoyasarApiError {
  if (isAxiosError(err)) {
    const ax = err as AxiosError<MoyasarErrorBody>;
    if (ax.response) {
      const { status, data } = ax.response;
      return new MoyasarApiError(
        data?.message ?? `Moyasar HTTP ${status}`,
        {
          httpStatus: status,
          type: data?.type,
          fieldErrors: data?.errors ?? null,
          // 5xx is ambiguous/transient; 4xx is a client bug — don't retry it.
          retryable: status >= 500,
        },
      );
    }
    // No response: DNS/connect/timeout. Outcome unknown — retryable.
    return new MoyasarApiError(
      `Network error contacting Moyasar: ${ax.code ?? ax.message}`,
      { retryable: true },
    );
  }
  return new MoyasarApiError(
    err instanceof Error ? err.message : "Unknown Moyasar client error",
    { retryable: false },
  );
}

export interface MoyasarClient {
  /** Generic typed escape hatch for endpoints without a dedicated method. */
  request<T>(
    method: "get" | "post" | "put" | "delete",
    path: string,
    body?: unknown,
    query?: Record<string, string | number | undefined>,
  ): Promise<T>;
  createPayment(input: CreatePaymentInput): Promise<Payment>;
  fetchPayment(id: string): Promise<Payment>;
  listPayments(
    query?: Record<string, string | number | undefined>,
  ): Promise<PaymentList>;
  updatePayment(
    id: string,
    body: { description?: string; metadata?: Record<string, unknown> },
  ): Promise<Payment>;
  refundPayment(id: string, amount?: number): Promise<Payment>;
  capturePayment(id: string, amount?: number): Promise<Payment>;
  voidPayment(id: string): Promise<Payment>;
  createInvoice(input: CreateInvoiceInput): Promise<Invoice>;
  fetchInvoice(id: string): Promise<Invoice>;
  listInvoices(
    query?: Record<string, string | number | undefined>,
  ): Promise<InvoiceList>;
  /**
   * Fetch a payment and assert it is safe to fulfill: status in
   * {paid, captured} AND amount === expectedAmount AND currency matches.
   * Pass the amount/currency from YOUR server-side order, never the client.
   * Resolves with the Payment or throws PaymentVerificationError.
   */
  verifyPayment(
    id: string,
    opts: { expectedAmount: number; expectedCurrency: string },
  ): Promise<Payment>;
}

export function createMoyasarClient(
  options: MoyasarClientOptions = {},
): MoyasarClient {
  const apiKey =
    options.apiKey ?? process.env.MOYASAR_SECRET_KEY ?? undefined;
  if (!apiKey) {
    throw new Error(
      "Moyasar API key missing. Set MOYASAR_SECRET_KEY (server-side, NOT " +
        "NEXT_PUBLIC_) or pass { apiKey }.",
    );
  }

  const http: AxiosInstance = axios.create({
    baseURL: options.baseUrl ?? MOYASAR_API_BASE,
    timeout: options.timeoutMs ?? 15_000,
    // HTTP Basic Auth: API key as username, password MUST be empty.
    // Axios encodes this as base64("<key>:") — exactly what Moyasar requires.
    auth: { username: apiKey, password: "" },
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      // Moyasar's API is behind Cloudflare, which 403-blocks unrecognized /
      // default automation User-Agents (Cloudflare error 1010 — the body is
      // Cloudflare HTML, not Moyasar's JSON error envelope). Always send an
      // explicit User-Agent. Override via options if you have your own.
      "User-Agent": options.userAgent ?? "moyasar-client/1.0",
    },
  });

  async function request<T>(
    method: "get" | "post" | "put" | "delete",
    path: string,
    body?: unknown,
    query?: Record<string, string | number | undefined>,
  ): Promise<T> {
    try {
      const res = await http.request<T>({
        method,
        url: path,
        data: body,
        params: query,
      });
      return res.data;
    } catch (err) {
      throw normalizeError(err);
    }
  }

  async function fetchPayment(id: string): Promise<Payment> {
    try {
      return await request<Payment>("get", `/payments/${encodeURIComponent(id)}`);
    } catch (err) {
      if (err instanceof MoyasarApiError && err.httpStatus === 404) {
        throw new PaymentVerificationError(
          `Payment ${id} not found (404). Treat as NOT paid.`,
          "not_found",
        );
      }
      throw err;
    }
  }

  return {
    request,
    createPayment: (input) => request<Payment>("post", "/payments", input),
    fetchPayment,
    listPayments: (query) => request<PaymentList>("get", "/payments", undefined, query),
    updatePayment: (id, b) =>
      request<Payment>("put", `/payments/${encodeURIComponent(id)}`, b),
    refundPayment: (id, amount) =>
      request<Payment>(
        "post",
        `/payments/${encodeURIComponent(id)}/refund`,
        amount === undefined ? {} : { amount },
      ),
    capturePayment: (id, amount) =>
      request<Payment>(
        "post",
        `/payments/${encodeURIComponent(id)}/capture`,
        amount === undefined ? {} : { amount },
      ),
    voidPayment: (id) =>
      request<Payment>("post", `/payments/${encodeURIComponent(id)}/void`, {}),
    createInvoice: (input) => request<Invoice>("post", "/invoices", input),
    fetchInvoice: (id) =>
      request<Invoice>("get", `/invoices/${encodeURIComponent(id)}`),
    listInvoices: (query) =>
      request<InvoiceList>("get", "/invoices", undefined, query),

    async verifyPayment(id, { expectedAmount, expectedCurrency }) {
      if (!Number.isInteger(expectedAmount) || expectedAmount <= 0) {
        throw new PaymentVerificationError(
          "expectedAmount must be a positive integer in the smallest " +
            "currency unit (1.00 SAR === 100). Use toMinorUnits().",
          "amount",
        );
      }

      let payment: Payment;
      try {
        payment = await fetchPayment(id);
      } catch (err) {
        if (err instanceof PaymentVerificationError) throw err;
        if (err instanceof MoyasarApiError) {
          throw new PaymentVerificationError(
            err.message,
            err.retryable && err.httpStatus === undefined ? "network" : "http",
          );
        }
        throw err;
      }

      if (!FULFILLABLE_STATUSES.has(payment.status)) {
        const m = payment.source?.message;
        throw new PaymentVerificationError(
          `Payment ${id} status is "${payment.status}", not paid/captured.` +
            (m ? ` source.message: ${m}` : "") +
            " Do NOT fulfill.",
          "status",
          payment,
        );
      }
      if (payment.amount !== expectedAmount) {
        throw new PaymentVerificationError(
          `Amount mismatch for ${id}: Moyasar=${payment.amount}, ` +
            `expected=${expectedAmount} (minor units). Possible tampering — ` +
            "do NOT fulfill.",
          "amount",
          payment,
        );
      }
      if (
        (payment.currency ?? "").toUpperCase() !==
        expectedCurrency.toUpperCase()
      ) {
        throw new PaymentVerificationError(
          `Currency mismatch for ${id}: Moyasar="${payment.currency}", ` +
            `expected="${expectedCurrency.toUpperCase()}". Do NOT fulfill.`,
          "currency",
          payment,
        );
      }
      return payment;
    },
  };
}

/**
 * Constant-time comparison for authenticating webhook calls. Compare the
 * delivered `secret_token` against your configured shared secret with this,
 * not `===` (which leaks length/timing). Returns false on any length
 * mismatch without throwing.
 */
export function safeSecretEquals(a: string, b: string): boolean {
  const ab = Buffer.from(a, "utf8");
  const bb = Buffer.from(b, "utf8");
  if (ab.length !== bb.length) return false;
  return timingSafeEqual(ab, bb);
}

/** Minimal shape of the webhook event envelope Moyasar POSTs. */
export interface MoyasarWebhookEvent {
  id: string;
  type: string;
  created_at: string;
  secret_token: string;
  account_name: string;
  live: boolean;
  data: Payment;
}
