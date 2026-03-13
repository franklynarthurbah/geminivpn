/**
 * Payment Service — Shared Types & Plan Definitions
 *
 * All three providers (Square, Paddle, Coinbase) implement IPaymentService.
 * The controller never calls a provider SDK directly — it calls this interface.
 * This makes provider swaps, testing, and additions trivial.
 */

// ─── Plan registry ────────────────────────────────────────────────────────────

export interface PlanDefinition {
  /** URL-safe ID used in API: 'monthly' | 'yearly' | 'two-year' */
  id: string;
  name: string;
  description: string;
  /** Display price in dollars, e.g. 11.99 */
  price: number;
  /** Amount in cents for payment APIs, e.g. 1199 */
  amountCents: number;
  currency: string;
  /** How many days this plan extends the subscription */
  intervalDays: number;
  features: string[];
  /** Paddle Billing price ID (pri_xxx). Required only for Paddle provider. */
  paddlePriceId: string;
}

export const PLANS: Record<string, PlanDefinition> = {
  monthly: {
    id:           'monthly',
    name:         'Monthly',
    description:  'Billed monthly. Cancel anytime.',
    price:        11.99,
    amountCents:  1199,
    currency:     'USD',
    intervalDays: 30,
    features:     ['10 devices', '10 Gbps servers', 'No logs', 'Kill switch', '24/7 support'],
    paddlePriceId: process.env.PADDLE_MONTHLY_PRICE_ID || '',
  },
  yearly: {
    id:           'yearly',
    name:         '1-Year',
    description:  'Save 58%. Billed annually.',
    price:        59.88,
    amountCents:  5988,
    currency:     'USD',
    intervalDays: 365,
    features:     ['10 devices', '10 Gbps servers', 'No logs', 'Kill switch', '24/7 support', 'Priority servers'],
    paddlePriceId: process.env.PADDLE_YEARLY_PRICE_ID || '',
  },
  'two-year': {
    id:           'two-year',
    name:         '2-Year',
    description:  'Save 71%. Best value.',
    price:        83.76,
    amountCents:  8376,
    currency:     'USD',
    intervalDays: 730,
    features:     ['10 devices', '10 Gbps servers', 'No logs', 'Kill switch', '24/7 support', 'Priority servers', 'Dedicated IP'],
    paddlePriceId: process.env.PADDLE_TWO_YEAR_PRICE_ID || '',
  },
};

/** Normalise any planType variant to PLANS key. Returns null if unknown. */
export function normalisePlanId(raw: string): string | null {
  const map: Record<string, string> = {
    MONTHLY:    'monthly',
    monthly:    'monthly',
    YEARLY:     'yearly',
    yearly:     'yearly',
    TWO_YEAR:   'two-year',
    'two-year': 'two-year',
  };
  return map[raw] ?? null;
}

// ─── Checkout ─────────────────────────────────────────────────────────────────

export interface CreateCheckoutParams {
  userId:     string;
  userEmail:  string;
  userName:   string | null;
  plan:       PlanDefinition;
  /** Normalised DB enum string: 'MONTHLY' | 'YEARLY' | 'TWO_YEAR' */
  planType:   string;
  successUrl: string;
  cancelUrl:  string;
}

export interface CheckoutResult {
  /** Provider-side payment/charge/transaction ID stored in DB */
  providerPaymentId: string;
  /** Hosted checkout URL — redirect the user here */
  checkoutUrl:       string;
  provider: 'SQUARE' | 'PADDLE' | 'COINBASE';
}

// ─── Subscription management ──────────────────────────────────────────────────

export interface CancelSubscriptionParams {
  userId:               string;
  paddleSubscriptionId?: string | null;
}

export interface CancelResult {
  cancelled: boolean;
  /** When the subscription will actually end (Paddle returns this) */
  endsAt?:   Date;
}

// ─── Normalised webhook event ─────────────────────────────────────────────────

/**
 * Every provider's webhook handler translates its native event into this
 * common shape. The webhookController only needs to handle this one type.
 */
export interface NormalisedWebhookEvent {
  provider: 'SQUARE' | 'PADDLE' | 'COINBASE';
  type:
    | 'payment.completed'      // one-time payment confirmed
    | 'payment.failed'         // payment declined / expired
    | 'subscription.renewed'   // recurring payment succeeded (Paddle)
    | 'subscription.cancelled' // subscription ended (Paddle)
    | 'charge.confirmed'       // crypto payment confirmed on-chain (Coinbase)
    | 'charge.failed';         // crypto charge expired / unresolved (Coinbase)
  /** GeminiVPN user UUID from metadata we attached at checkout creation */
  userId?:         string;
  /** Plan type enum string ('MONTHLY' | 'YEARLY' | 'TWO_YEAR') */
  planType?:       string;
  /** Provider-side customer identifier */
  customerId?:     string;
  /** Provider-side subscription ID (Paddle only) */
  subscriptionId?: string;
  /** Provider-side payment/charge ID */
  paymentId?:      string;
  /** Raw provider payload — for debugging, never trust for business logic */
  rawPayload:      unknown;
}

// ─── Provider interface ───────────────────────────────────────────────────────

export interface IPaymentService {
  /**
   * Create a hosted checkout session.
   * All three providers redirect the user to their own payment page.
   */
  createCheckout(params: CreateCheckoutParams): Promise<CheckoutResult>;

  /**
   * Cancel an active subscription.
   * Only Paddle supports true server-side recurring cancellation.
   * Square/Coinbase return { cancelled: true } immediately (DB-level only).
   */
  cancelSubscription(params: CancelSubscriptionParams): Promise<CancelResult>;

  /**
   * Verify webhook signature and return normalised event.
   * Throws an Error if the signature is invalid.
   * Returns null for event types we don't handle.
   */
  parseWebhook(
    rawBody: Buffer | string,
    headers: Record<string, string | string[] | undefined>,
  ): Promise<NormalisedWebhookEvent | null>;
}
