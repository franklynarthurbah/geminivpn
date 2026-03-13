/**
 * Square Payment Service
 * ─────────────────────
 * Handles card, debit card, bank ACH, Apple Pay, and Google Pay via Square
 * Checkout Payment Links. No SDK dependency — pure REST via node-fetch.
 *
 * Why Square for unregistered businesses:
 *   - Free account creation at squareup.com/signup
 *   - No business entity required to start (personal account OK)
 *   - Sandbox available immediately at developer.squareup.com
 *   - Supports 30+ countries, 135+ currencies
 *
 * Supported payment methods (configured in Square Dashboard):
 *   - Credit card, debit card (Visa, Mastercard, Amex, Discover)
 *   - ACH / bank transfer (US only, via Square)
 *   - Apple Pay / Google Pay
 *   - Cash App Pay
 *
 * Webhook verification:
 *   Signature = Base64(HMAC-SHA256(notificationUrl + rawBody, sigKey))
 *   Header:     X-Square-Hmacsha256-Signature
 *
 * Dashboard:  https://developer.squareup.com/apps
 * Sandbox test card: 4111 1111 1111 1111 / any future date / any CVV
 */

import crypto from 'crypto';
import fetch from 'node-fetch';
import { v4 as uuidv4 } from 'uuid';
import { logger } from '../../utils/logger';
import type {
  IPaymentService, CreateCheckoutParams, CheckoutResult,
  CancelSubscriptionParams, CancelResult, NormalisedWebhookEvent,
} from './types';

// ─── Config ───────────────────────────────────────────────────────────────────

interface SquareConfig {
  accessToken: string;
  locationId:  string;
  baseUrl:     string;
}

function getConfig(): SquareConfig {
  const accessToken = process.env.SQUARE_ACCESS_TOKEN || '';
  const locationId  = process.env.SQUARE_LOCATION_ID  || '';
  if (!accessToken || accessToken === 'placeholder') {
    throw new Error(
      'SQUARE_ACCESS_TOKEN is not set. ' +
      'Get it from: https://developer.squareup.com/apps > Credentials',
    );
  }
  if (!locationId || locationId === 'placeholder') {
    throw new Error(
      'SQUARE_LOCATION_ID is not set. ' +
      'Get it from: Square Dashboard > Account & Settings > Business locations',
    );
  }
  const isSandbox = process.env.SQUARE_ENVIRONMENT !== 'production';
  return {
    accessToken,
    locationId,
    baseUrl: isSandbox
      ? 'https://connect.squareupsandbox.com'
      : 'https://connect.squareup.com',
  };
}

// ─── HTTP helper ──────────────────────────────────────────────────────────────

async function squarePost<T>(path: string, body: object): Promise<T> {
  const { accessToken, baseUrl } = getConfig();
  const url = `${baseUrl}${path}`;

  const resp = await fetch(url, {
    method:  'POST',
    headers: {
      Authorization:  `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      'Square-Version': '2024-01-18',
    },
    body: JSON.stringify(body),
  });

  const text = await resp.text();
  let data: any;
  try   { data = JSON.parse(text); }
  catch { data = { errors: [{ detail: text }] }; }

  if (!resp.ok) {
    const detail = (data?.errors as any[])?.[0]?.detail || `Square API ${resp.status}`;
    logger.error(`[Square] POST ${path} failed: ${detail}`, { status: resp.status, data });
    throw new Error(`Square: ${detail}`);
  }

  return data as T;
}

// ─── Service ──────────────────────────────────────────────────────────────────

export class SquareService implements IPaymentService {

  /**
   * Creates a Square Payment Link (hosted checkout page).
   * The user is redirected to Square's page; no card details touch our server.
   */
  async createCheckout(params: CreateCheckoutParams): Promise<CheckoutResult> {
    const { userId, userEmail, plan, planType, successUrl } = params;
    const { locationId } = getConfig();

    logger.info(`[Square] Creating checkout — user=${userId} plan=${planType}`);

    const idempotencyKey = uuidv4();

    // Square Payment Links API
    // https://developer.squareup.com/reference/square/checkout-api/create-payment-link
    const resp = await squarePost<any>('/v2/online-checkout/payment-links', {
      idempotency_key: idempotencyKey,
      order: {
        location_id:  locationId,
        reference_id: userId,      // stored in Square; lets us identify user in webhooks
        line_items: [{
          name:             `GeminiVPN ${plan.name}`,
          quantity:         '1',
          base_price_money: {
            amount:   plan.amountCents,  // integer cents — no BigInt needed in plain JSON
            currency: 'USD',
          },
          note: `userId=${userId};planType=${planType};service=geminivpn`,
        }],
        metadata: {
          userId,
          planType,
          service: 'geminivpn',
        },
      },
      checkout_options: {
        redirect_url:                  successUrl,
        ask_for_shipping_address:      false,
        accepted_payment_methods: {
          apple_pay:   true,
          google_pay:  true,
          cash_app_pay: false,
        },
      },
      pre_populated_data: {
        buyer_email: userEmail,
      },
    });

    const linkId  = resp?.payment_link?.id;
    const linkUrl = resp?.payment_link?.url;

    if (!linkId || !linkUrl) {
      logger.error('[Square] Response missing payment_link.url', resp);
      throw new Error('Square did not return a checkout URL');
    }

    logger.info(`[Square] Payment link created id=${linkId}`);
    return {
      providerPaymentId: linkId,
      checkoutUrl:       linkUrl,
      provider:          'SQUARE',
    };
  }

  /**
   * Square Payment Links do not have server-side subscription management.
   * For GeminiVPN, Square payments are treated as one-time access grants.
   * Cancellation is recorded in the DB only.
   */
  async cancelSubscription(_params: CancelSubscriptionParams): Promise<CancelResult> {
    logger.info('[Square] cancelSubscription — payment-link-based, marking cancelled in DB');
    return { cancelled: true };
  }

  /**
   * Verifies and parses an incoming Square webhook.
   * Square signs with HMAC-SHA256(notificationUrl + rawBody, sigKey).
   *
   * Setup in Square Developer Dashboard:
   *   Apps > Webhooks > Add endpoint
   *   URL: https://geminivpn.zapto.org/api/v1/webhooks/square
   *   Events: payment.completed, order.updated
   */
  async parseWebhook(
    rawBody: Buffer | string,
    headers: Record<string, string | string[] | undefined>,
  ): Promise<NormalisedWebhookEvent | null> {
    const body      = typeof rawBody === 'string' ? rawBody : rawBody.toString('utf-8');
    const signature = String(headers['x-square-hmacsha256-signature'] || '');
    const notifUrl  = String(headers['x-square-notification-url']     || '');
    const sigKey    = process.env.SQUARE_WEBHOOK_SIGNATURE_KEY || '';

    if (!sigKey) {
      logger.warn('[Square] SQUARE_WEBHOOK_SIGNATURE_KEY not set — skipping signature check');
    } else {
      // Square spec: Base64(HMAC-SHA256(notificationUrl + body, sigKey))
      const expected = crypto
        .createHmac('sha256', sigKey)
        .update(notifUrl + body)
        .digest('base64');

      if (!safeCompare(signature, expected)) {
        logger.warn('[Square] Webhook signature verification failed');
        throw new Error('Invalid Square webhook signature');
      }
    }

    const payload = parseJson(body, 'Square');
    const eventType: string = payload.type || '';

    logger.info(`[Square] Webhook received — type=${eventType}`);

    switch (eventType) {

      case 'payment.completed': {
        const payment    = payload.data?.object?.payment || {};
        const metadata   = payload.data?.object?.order?.metadata || {};
        const lineNote   = (payment.line_items || [])[0]?.note || '';
        return {
          provider:  'SQUARE',
          type:      'payment.completed',
          userId:    metadata.userId    || extractNote(lineNote, 'userId'),
          planType:  metadata.planType  || extractNote(lineNote, 'planType'),
          paymentId: payment.id,
          customerId: payment.customer_id,
          rawPayload: payload,
        };
      }

      case 'payment.updated': {
        const payment = payload.data?.object?.payment || {};
        if (payment.status === 'FAILED' || payment.status === 'CANCELED') {
          return {
            provider:  'SQUARE',
            type:      'payment.failed',
            userId:    payment.reference_id,
            paymentId: payment.id,
            rawPayload: payload,
          };
        }
        return null;
      }

      case 'order.updated': {
        const orderUpdated = payload.data?.object?.order_updated || {};
        if (orderUpdated.state === 'COMPLETED') {
          const meta = orderUpdated.metadata || {};
          return {
            provider:  'SQUARE',
            type:      'payment.completed',
            userId:    meta.userId,
            planType:  meta.planType,
            paymentId: orderUpdated.order_id,
            rawPayload: payload,
          };
        }
        return null;
      }

      default:
        logger.info(`[Square] Unhandled event type: ${eventType}`);
        return null;
    }
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function safeCompare(a: string, b: string): boolean {
  try {
    return a.length === b.length &&
      crypto.timingSafeEqual(Buffer.from(a, 'base64'), Buffer.from(b, 'base64'));
  } catch {
    return false;
  }
}

/** Extracts key=value pairs from a note string like "userId=xxx;planType=MONTHLY" */
function extractNote(note: string, key: string): string | undefined {
  const m = note.match(new RegExp(`${key}=([^;\\s]+)`));
  return m?.[1];
}

function parseJson(body: string, provider: string): any {
  try { return JSON.parse(body); }
  catch { throw new Error(`${provider} webhook body is not valid JSON`); }
}

export const squareService = new SquareService();
