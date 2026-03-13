/**
 * Paddle Payment Service
 * ──────────────────────
 * Handles recurring subscriptions, PayPal, and local payment methods
 * via Paddle Billing (the modern Paddle API, not Paddle Classic).
 *
 * Why Paddle for unregistered businesses:
 *   - Paddle is a Merchant of Record: they handle VAT, sales tax, and
 *     compliance globally. You never need to register a business in each
 *     country your customers are in.
 *   - Paddle account: https://vendors.paddle.com/signup (free)
 *   - Supports: Credit card, Debit card, PayPal, Apple Pay, Google Pay,
 *     iDEAL, Bancontact, and many more local methods (country-dependent).
 *   - Subscription management: Paddle handles retries, dunning, and renewals.
 *
 * Implementation: Direct REST API calls via node-fetch (no heavy SDK).
 * API docs: https://developer.paddle.com/api-reference
 *
 * Webhook signature:
 *   Header:  Paddle-Signature: ts=<unix>;h1=<hex_hmac>
 *   Verify:  HMAC-SHA256(<ts>:<rawBody>, PADDLE_WEBHOOK_SECRET) == h1
 *
 * Sandbox: https://sandbox-vendors.paddle.com
 *          Use sandbox API key (starts with test_)
 */

import crypto from 'crypto';
import fetch from 'node-fetch';
import { logger } from '../../utils/logger';
import type {
  IPaymentService, CreateCheckoutParams, CheckoutResult,
  CancelSubscriptionParams, CancelResult, NormalisedWebhookEvent,
} from './types';

// ─── Config ───────────────────────────────────────────────────────────────────

function getConfig() {
  const apiKey = process.env.PADDLE_API_KEY || '';
  if (!apiKey || apiKey === 'placeholder') {
    throw new Error(
      'PADDLE_API_KEY is not set. ' +
      'Get it from: Paddle Dashboard > Developer Tools > Authentication',
    );
  }
  const isSandbox = process.env.PADDLE_ENVIRONMENT !== 'production';
  return {
    apiKey,
    baseUrl: isSandbox
      ? 'https://sandbox-api.paddle.com'
      : 'https://api.paddle.com',
  };
}

// ─── HTTP helper ──────────────────────────────────────────────────────────────

async function paddleRequest<T>(
  method: 'GET' | 'POST' | 'PATCH',
  path: string,
  body?: object,
): Promise<T> {
  const { apiKey, baseUrl } = getConfig();

  const resp = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      Authorization:    `Bearer ${apiKey}`,
      'Content-Type':   'application/json',
      'Paddle-Version': '1',
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });

  const text = await resp.text();
  let data: any;
  try   { data = JSON.parse(text); }
  catch { data = { error: { detail: text } }; }

  if (!resp.ok) {
    const detail =
      data?.error?.detail ||
      data?.error?.type   ||
      `Paddle API ${resp.status}`;
    logger.error(`[Paddle] ${method} ${path} failed: ${detail}`, { status: resp.status });
    throw new Error(`Paddle: ${detail}`);
  }

  return data as T;
}

// ─── Service ──────────────────────────────────────────────────────────────────

export class PaddleService implements IPaymentService {

  /**
   * Creates a Paddle transaction with a hosted checkout URL.
   * The checkout page supports card, PayPal, Apple Pay, and local methods
   * automatically based on the customer's location.
   *
   * Requires a Paddle Price ID (pri_xxx) for each plan — create these in:
   *   Paddle Dashboard > Catalog > Products
   */
  async createCheckout(params: CreateCheckoutParams): Promise<CheckoutResult> {
    const { userId, userEmail, userName, plan, planType, successUrl, cancelUrl } = params;

    if (!plan.paddlePriceId) {
      throw new Error(
        `PADDLE_${planType}_PRICE_ID is not configured. ` +
        'Run: sudo bash geminivpn.sh --payment  to configure Paddle prices.',
      );
    }

    logger.info(`[Paddle] Creating transaction — user=${userId} plan=${planType}`);

    // Paddle Billing: create a transaction that generates a checkout URL.
    // https://developer.paddle.com/api-reference/transactions/create-transaction
    const resp = await paddleRequest<any>('POST', '/transactions', {
      items: [{ price_id: plan.paddlePriceId, quantity: 1 }],
      customer: {
        email: userEmail,
        ...(userName ? { name: userName } : {}),
      },
      custom_data: {
        userId,
        planType,
        service: 'geminivpn',
      },
      checkout: {
        url:        successUrl,
        cancel_url: cancelUrl,
      },
    });

    const txId      = resp?.data?.id;
    const checkoutUrl = resp?.data?.checkout?.url;

    if (!txId || !checkoutUrl) {
      logger.error('[Paddle] Response missing transaction id or checkout.url', resp);
      throw new Error('Paddle did not return a checkout URL');
    }

    logger.info(`[Paddle] Transaction created id=${txId}`);
    return {
      providerPaymentId: txId,
      checkoutUrl,
      provider: 'PADDLE',
    };
  }

  /**
   * Cancels a Paddle subscription at the end of the current billing period.
   * The user keeps access until the period ends; no immediate revocation.
   */
  async cancelSubscription(params: CancelSubscriptionParams): Promise<CancelResult> {
    const { paddleSubscriptionId, userId } = params;

    if (!paddleSubscriptionId) {
      logger.warn(`[Paddle] No paddleSubscriptionId found for user=${userId}`);
      return { cancelled: false };
    }

    logger.info(`[Paddle] Cancelling subscription=${paddleSubscriptionId} user=${userId}`);

    // https://developer.paddle.com/api-reference/subscriptions/cancel-subscription
    const resp = await paddleRequest<any>(
      'POST',
      `/subscriptions/${paddleSubscriptionId}/cancel`,
      { effective_from: 'next_billing_period' },
    );

    const effectiveAt: string | undefined =
      resp?.data?.scheduled_change?.effective_at;

    logger.info(
      `[Paddle] Subscription ${paddleSubscriptionId} cancelled. Effective: ${effectiveAt}`,
    );

    return {
      cancelled: true,
      endsAt:    effectiveAt ? new Date(effectiveAt) : undefined,
    };
  }

  /**
   * Verifies Paddle webhook signature and returns normalised event.
   *
   * Signature format: "ts=<unix_timestamp>;h1=<hex_hmac>"
   * Verification: HMAC-SHA256(ts + ':' + rawBody, PADDLE_WEBHOOK_SECRET)
   *
   * Setup in Paddle Dashboard:
   *   Developer Tools > Notifications > Add endpoint
   *   URL: https://geminivpn.zapto.org/api/v1/webhooks/paddle
   *   Events: transaction.completed, transaction.payment_failed,
   *           subscription.activated, subscription.updated, subscription.cancelled
   */
  async parseWebhook(
    rawBody: Buffer | string,
    headers: Record<string, string | string[] | undefined>,
  ): Promise<NormalisedWebhookEvent | null> {
    const body      = typeof rawBody === 'string' ? rawBody : rawBody.toString('utf-8');
    const sigHeader = String(headers['paddle-signature'] || '');
    const secret    = process.env.PADDLE_WEBHOOK_SECRET || '';

    if (!secret) {
      logger.warn('[Paddle] PADDLE_WEBHOOK_SECRET not set — skipping signature check');
    } else {
      // Parse "ts=xxx;h1=yyy"
      const parts: Record<string, string> = {};
      sigHeader.split(';').forEach(segment => {
        const idx = segment.indexOf('=');
        if (idx > 0) {
          parts[segment.slice(0, idx).trim()] = segment.slice(idx + 1).trim();
        }
      });

      if (!parts.ts || !parts.h1) {
        throw new Error('Paddle webhook: malformed Paddle-Signature header');
      }

      // Replay attack protection: reject events older than 5 minutes
      const ts = parseInt(parts.ts, 10);
      if (Math.abs(Date.now() / 1000 - ts) > 300) {
        throw new Error('Paddle webhook timestamp too old (possible replay attack)');
      }

      const expected = crypto
        .createHmac('sha256', secret)
        .update(`${parts.ts}:${body}`)
        .digest('hex');

      if (!crypto.timingSafeEqual(
        Buffer.from(parts.h1,  'hex'),
        Buffer.from(expected,  'hex'),
      )) {
        logger.warn('[Paddle] Webhook signature verification failed');
        throw new Error('Invalid Paddle webhook signature');
      }
    }

    const payload    = parseJson(body, 'Paddle');
    const eventType: string = payload.event_type || '';
    const data       = payload.data || {};
    const custom     = data.custom_data || {};

    logger.info(`[Paddle] Webhook received — event_type=${eventType}`);

    switch (eventType) {

      case 'transaction.completed':
        return {
          provider:       'PADDLE',
          type:           'payment.completed',
          userId:         custom.userId,
          planType:       custom.planType,
          paymentId:      data.id,
          customerId:     data.customer_id || data.customer?.id,
          subscriptionId: data.subscription_id,
          rawPayload:     payload,
        };

      case 'transaction.payment_failed':
        return {
          provider:   'PADDLE',
          type:       'payment.failed',
          userId:     custom.userId,
          planType:   custom.planType,
          paymentId:  data.id,
          customerId: data.customer_id || data.customer?.id,
          rawPayload: payload,
        };

      case 'subscription.activated':
      case 'subscription.updated':
        return {
          provider:       'PADDLE',
          type:           'subscription.renewed',
          subscriptionId: data.id,
          customerId:     data.customer_id || data.customer?.id,
          userId:         custom.userId,
          planType:       custom.planType,
          rawPayload:     payload,
        };

      case 'subscription.cancelled':
        return {
          provider:       'PADDLE',
          type:           'subscription.cancelled',
          subscriptionId: data.id,
          customerId:     data.customer_id || data.customer?.id,
          userId:         custom.userId,
          rawPayload:     payload,
        };

      default:
        logger.info(`[Paddle] Unhandled event_type: ${eventType}`);
        return null;
    }
  }
}

function parseJson(body: string, provider: string): any {
  try { return JSON.parse(body); }
  catch { throw new Error(`${provider} webhook body is not valid JSON`); }
}

export const paddleService = new PaddleService();
