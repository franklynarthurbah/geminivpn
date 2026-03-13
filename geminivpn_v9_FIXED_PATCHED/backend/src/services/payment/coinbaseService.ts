/**
 * Coinbase Commerce Payment Service
 * ──────────────────────────────────
 * Handles cryptocurrency payments via Coinbase Commerce.
 *
 * Why Coinbase Commerce for unregistered businesses:
 *   - No business registration needed — just a free Coinbase Commerce account
 *   - Supports: Bitcoin (BTC), Ethereum (ETH), USDC, DAI, Litecoin, and more
 *   - Charges are one-time (no native subscription); we extend access on confirmation
 *   - Payments are global — no country restrictions
 *   - Account: https://commerce.coinbase.com
 *
 * Flow:
 *   1. We create a Charge with metadata (userId, planType)
 *   2. User is redirected to Coinbase Commerce hosted page
 *   3. User sends crypto from their wallet
 *   4. Coinbase fires webhook when payment is detected on-chain
 *   5. We activate the subscription on 'charge:confirmed' webhook
 *
 * IMPORTANT: Crypto confirmations can take minutes to hours.
 *   - charge:pending = payment sent, waiting for confirmations
 *   - charge:confirmed = enough confirmations — ACTIVATE subscription
 *   - charge:failed / charge:expired = user did not pay in time window
 *
 * Webhook verification:
 *   Header:  X-CC-Webhook-Signature: <hex_hmac>
 *   Verify:  HMAC-SHA256(rawBody, COINBASE_WEBHOOK_SECRET) == signature
 *
 * API docs: https://docs.cdp.coinbase.com/commerce-onchain/docs/api-overview
 */

import crypto from 'crypto';
import fetch from 'node-fetch';
import { logger } from '../../utils/logger';
import type {
  IPaymentService, CreateCheckoutParams, CheckoutResult,
  CancelSubscriptionParams, CancelResult, NormalisedWebhookEvent,
} from './types';

// ─── Config ───────────────────────────────────────────────────────────────────

function getApiKey(): string {
  const key = process.env.COINBASE_COMMERCE_API_KEY || '';
  if (!key || key === 'placeholder') {
    throw new Error(
      'COINBASE_COMMERCE_API_KEY is not set. ' +
      'Get it from: https://commerce.coinbase.com > Settings > Security',
    );
  }
  return key;
}

const COINBASE_API  = 'https://api.commerce.coinbase.com';
const API_VERSION   = '2018-03-22';

// ─── HTTP helper ──────────────────────────────────────────────────────────────

async function coinbasePost<T>(path: string, body: object): Promise<T> {
  const apiKey = getApiKey();

  const resp = await fetch(`${COINBASE_API}${path}`, {
    method:  'POST',
    headers: {
      'X-CC-Api-Key':  apiKey,
      'X-CC-Version':  API_VERSION,
      'Content-Type':  'application/json',
      'Accept':        'application/json',
    },
    body: JSON.stringify(body),
  });

  const text = await resp.text();
  let data: any;
  try   { data = JSON.parse(text); }
  catch { data = { error: { message: text } }; }

  if (!resp.ok) {
    const msg = data?.error?.message || `Coinbase Commerce API ${resp.status}`;
    logger.error(`[Coinbase] POST ${path} failed: ${msg}`, { status: resp.status });
    throw new Error(`Coinbase: ${msg}`);
  }

  return data as T;
}

// ─── Service ──────────────────────────────────────────────────────────────────

export class CoinbaseService implements IPaymentService {

  /**
   * Creates a Coinbase Commerce charge with a hosted checkout page.
   * The user chooses their cryptocurrency on Coinbase's page.
   * The charge expires after 1 hour by default.
   */
  async createCheckout(params: CreateCheckoutParams): Promise<CheckoutResult> {
    const { userId, userEmail, plan, planType, successUrl, cancelUrl } = params;

    logger.info(`[Coinbase] Creating charge — user=${userId} plan=${planType}`);

    // https://docs.cdp.coinbase.com/commerce-onchain/reference/creates-a-charge
    const resp = await coinbasePost<any>('/charges', {
      name:        `GeminiVPN ${plan.name}`,
      description: plan.description,
      local_price: {
        amount:   plan.price.toFixed(2),
        currency: 'USD',
      },
      pricing_type: 'fixed_price',
      metadata: {
        userId,
        planType,
        userEmail,
        service: 'geminivpn',
      },
      redirect_url: successUrl,
      cancel_url:   cancelUrl,
    });

    const chargeId  = resp?.data?.id;
    const code      = resp?.data?.code;
    const hostedUrl = resp?.data?.hosted_url;

    if (!chargeId || !hostedUrl) {
      logger.error('[Coinbase] Response missing charge id or hosted_url', resp);
      throw new Error('Coinbase did not return a charge URL');
    }

    logger.info(`[Coinbase] Charge created code=${code} id=${chargeId}`);
    return {
      providerPaymentId: chargeId,
      checkoutUrl:       hostedUrl,
      provider:          'COINBASE',
    };
  }

  /**
   * Coinbase Commerce has no subscription model.
   * Cancellation is handled at the DB level only.
   */
  async cancelSubscription(_params: CancelSubscriptionParams): Promise<CancelResult> {
    logger.info('[Coinbase] cancelSubscription — charge-based, marking cancelled in DB');
    return { cancelled: true };
  }

  /**
   * Verifies Coinbase Commerce webhook and returns normalised event.
   *
   * Setup in Coinbase Commerce Dashboard:
   *   Settings > Webhook subscriptions > Add an endpoint
   *   URL: https://geminivpn.zapto.org/api/v1/webhooks/coinbase
   *   Events: charge:confirmed, charge:failed, charge:expired, charge:pending
   */
  async parseWebhook(
    rawBody: Buffer | string,
    headers: Record<string, string | string[] | undefined>,
  ): Promise<NormalisedWebhookEvent | null> {
    const body      = typeof rawBody === 'string' ? rawBody : rawBody.toString('utf-8');
    const signature = String(headers['x-cc-webhook-signature'] || '');
    const secret    = process.env.COINBASE_WEBHOOK_SECRET || '';

    if (!secret) {
      logger.warn('[Coinbase] COINBASE_WEBHOOK_SECRET not set — skipping signature check');
    } else {
      const expected = crypto
        .createHmac('sha256', secret)
        .update(body)
        .digest('hex');

      if (!safeHexCompare(signature, expected)) {
        logger.warn('[Coinbase] Webhook signature verification failed');
        throw new Error('Invalid Coinbase Commerce webhook signature');
      }
    }

    const payload    = parseJson(body, 'Coinbase');
    const event      = payload.event || {};
    const eventType: string = event.type || '';
    const charge     = event.data || {};
    const meta       = charge.metadata || {};

    logger.info(`[Coinbase] Webhook received — type=${eventType}`);

    switch (eventType) {

      // Payment fully confirmed on blockchain
      case 'charge:confirmed':
      case 'charge:resolved':  // resolved = Coinbase manually resolved partial payment
        return {
          provider:   'COINBASE',
          type:       'charge.confirmed',
          userId:     meta.userId,
          planType:   meta.planType,
          paymentId:  charge.id || charge.code,
          rawPayload: payload,
        };

      // Charge expired (user never paid) or payment was flagged
      case 'charge:failed':
      case 'charge:expired':
        return {
          provider:   'COINBASE',
          type:       'charge.failed',
          userId:     meta.userId,
          planType:   meta.planType,
          paymentId:  charge.id || charge.code,
          rawPayload: payload,
        };

      // Payment detected on blockchain but not yet confirmed — do nothing yet
      case 'charge:pending':
        logger.info(
          `[Coinbase] Charge pending — user=${meta.userId} awaiting blockchain confirmation`,
        );
        return null;

      // charge:created — informational, no action needed
      case 'charge:created':
        return null;

      default:
        logger.info(`[Coinbase] Unhandled event type: ${eventType}`);
        return null;
    }
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function safeHexCompare(a: string, b: string): boolean {
  try {
    if (a.length !== b.length) return false;
    return crypto.timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
  } catch {
    return false;
  }
}

function parseJson(body: string, provider: string): any {
  try { return JSON.parse(body); }
  catch { throw new Error(`${provider} webhook body is not valid JSON`); }
}

export const coinbaseService = new CoinbaseService();
