/**
 * Webhook Controller — GeminiVPN v3 (Combined)
 * ──────────────────────────────────────────────
 * Handles ALL four payment providers:
 *   Stripe   → POST /api/v1/webhooks/stripe
 *   Square   → POST /api/v1/webhooks/square
 *   Paddle   → POST /api/v1/webhooks/paddle
 *   Coinbase → POST /api/v1/webhooks/coinbase
 */

import { Request, Response } from 'express';
import { SubscriptionStatus, PaymentStatus, PaymentProvider } from '../lib/enums';

import prisma from '../lib/prisma';
import { logger } from '../utils/logger';

// V2 payment services
import { squareService, paddleService, coinbaseService } from '../services/payment';
import type { NormalisedWebhookEvent } from '../services/payment';

// ─── Stripe (lazy) ────────────────────────────────────────────────────────────
let _stripe: any | null = null;
const getStripe = (): any | null => {
  const key = process.env.STRIPE_SECRET_KEY || '';
  if (!key || key.includes('placeholder')) return null;
  if (!_stripe) {
    try {
      const Stripe = require('stripe');
      _stripe = new Stripe(key, { apiVersion: '2023-10-16' });
    } catch { return null; }
  }
  return _stripe;
};

export const handleStripeWebhook = async (req: Request, res: Response): Promise<void> => {
  try {
    const stripe = getStripe();
    if (!stripe) {
      logger.warn('Stripe webhook received but Stripe is not configured');
      res.status(200).json({ received: true, note: 'Stripe not configured' });
      return;
    }

    const signature = req.headers['stripe-signature'];
    if (!signature) { res.status(400).json({ success: false, message: 'Missing Stripe signature' }); return; }

    const secret = process.env.STRIPE_WEBHOOK_SECRET || '';
    let event: any;
    try {
      event = stripe.webhooks.constructEvent(req.body, signature, secret);
    } catch (err: any) {
      logger.error('Stripe webhook sig verification failed:', err.message);
      res.status(400).json({ success: false, message: `Webhook Error: ${err.message}` });
      return;
    }

    logger.info(`[Webhook/Stripe] ${event.type}`);

    switch (event.type) {
      case 'checkout.session.completed': await _stripeCheckoutCompleted(event.data.object); break;
      case 'invoice.payment_succeeded':  await _stripePaymentSucceeded(event.data.object);  break;
      case 'invoice.payment_failed':     await _stripePaymentFailed(event.data.object);     break;
      case 'customer.subscription.deleted': await _stripeSubCancelled(event.data.object);   break;
      default: logger.info(`[Webhook/Stripe] Unhandled: ${event.type}`);
    }
    res.json({ received: true });
  } catch (error) {
    logger.error('[Webhook/Stripe] Handler error:', error);
    res.status(500).json({ success: false, message: 'Webhook processing failed' });
  }
};

async function _stripeCheckoutCompleted(session: any) {
  const userId = session.metadata?.userId;
  const planType = session.metadata?.planType;
  if (!userId || !planType) { logger.warn('[Webhook/Stripe] Missing metadata'); return; }
  const days = ({ MONTHLY: 30, YEARLY: 365, TWO_YEAR: 730 } as any)[planType] || 30;
  const endsAt = new Date(Date.now() + days * 86400000);
  await prisma.user.update({
    where: { id: userId },
    data: {
      subscriptionStatus: SubscriptionStatus.ACTIVE,
      subscriptionEndsAt: endsAt,
      stripeSubscriptionId: session.subscription,
      paymentProvider: PaymentProvider.STRIPE,
    },
  });
  if (session.id) {
    await prisma.payment.updateMany({
      where: { stripePaymentId: session.id },
      data: { status: PaymentStatus.COMPLETED },
    });
  }
  logger.info(`[Webhook/Stripe] Checkout completed — user=${userId} plan=${planType}`);
}

async function _stripePaymentSucceeded(invoice: any) {
  const user = await prisma.user.findFirst({ where: { stripeCustomerId: invoice.customer } });
  if (!user) return;
  const endsAt = new Date(Math.max(Date.now(), user.subscriptionEndsAt?.getTime() || Date.now()) + 30 * 86400000);
  await prisma.user.update({ where: { id: user.id }, data: { subscriptionStatus: SubscriptionStatus.ACTIVE, subscriptionEndsAt: endsAt } });
  logger.info(`[Webhook/Stripe] Subscription renewed — user=${user.email}`);
}

async function _stripePaymentFailed(invoice: any) {
  const user = await prisma.user.findFirst({ where: { stripeCustomerId: invoice.customer } });
  if (!user) return;
  await prisma.user.update({ where: { id: user.id }, data: { subscriptionStatus: SubscriptionStatus.SUSPENDED } });
  logger.warn(`[Webhook/Stripe] Payment failed — user=${user.email}`);
}

async function _stripeSubCancelled(subscription: any) {
  const user = await prisma.user.findFirst({ where: { stripeSubscriptionId: subscription.id } });
  if (!user) return;
  await prisma.user.update({ where: { id: user.id }, data: { subscriptionStatus: SubscriptionStatus.CANCELLED, stripeSubscriptionId: null } });
  logger.info(`[Webhook/Stripe] Subscription cancelled — user=${user.email}`);
}

// ─── Square ────────────────────────────────────────────────────────────────────
export const handleSquareWebhook = async (req: Request, res: Response): Promise<void> => {
  try {
    const event = await squareService.parseWebhook(req.body as Buffer, req.headers as any);
    if (event) await _dispatchEvent(event);
    res.json({ received: true });
  } catch (error: any) {
    logger.error('[Webhook/Square] Error:', { message: error.message });
    res.status(error.message?.includes('signature') ? 400 : 200).json({ success: false, message: error.message });
  }
};

// ─── Paddle ────────────────────────────────────────────────────────────────────
export const handlePaddleWebhook = async (req: Request, res: Response): Promise<void> => {
  try {
    const event = await paddleService.parseWebhook(req.body as Buffer, req.headers as any);
    if (event) await _dispatchEvent(event);
    res.json({ received: true });
  } catch (error: any) {
    logger.error('[Webhook/Paddle] Error:', { message: error.message });
    res.status(error.message?.includes('signature') ? 400 : 200).json({ success: false, message: error.message });
  }
};

// ─── Coinbase ──────────────────────────────────────────────────────────────────
export const handleCoinbaseWebhook = async (req: Request, res: Response): Promise<void> => {
  try {
    const event = await coinbaseService.parseWebhook(req.body as Buffer, req.headers as any);
    if (event) await _dispatchEvent(event);
    res.json({ received: true });
  } catch (error: any) {
    logger.error('[Webhook/Coinbase] Error:', { message: error.message });
    res.status(error.message?.includes('signature') ? 400 : 200).json({ success: false, message: error.message });
  }
};

// ─── Shared event dispatcher ───────────────────────────────────────────────────
async function _dispatchEvent(event: NormalisedWebhookEvent): Promise<void> {
  logger.info(`[Webhook] provider=${event.provider} type=${event.type}`, {
    userId: event.userId, planType: event.planType,
  });

  switch (event.type) {
    case 'payment.completed':
    case 'charge.confirmed':
    case 'subscription.renewed':
      await _handlePaymentSuccess(event); break;
    case 'payment.failed':
    case 'charge.failed':
      await _handlePaymentFailure(event); break;
    case 'subscription.cancelled':
      await _handleSubCancelled(event); break;
    default:
      logger.info(`[Webhook] No handler for: ${event.type}`);
  }
}

async function _handlePaymentSuccess(event: NormalisedWebhookEvent): Promise<void> {
  const { userId, planType, paymentId, subscriptionId, customerId, provider } = event;
  if (!userId) { logger.warn('[Webhook] Success event missing userId'); return; }
  const days = ({ MONTHLY: 30, YEARLY: 365, TWO_YEAR: 730 } as any)[planType || 'MONTHLY'] || 30;
  const endsAt = new Date(Date.now() + days * 86400000);
  await prisma.user.update({
    where: { id: userId },
    data: {
      subscriptionStatus:  SubscriptionStatus.ACTIVE,
      subscriptionEndsAt:  endsAt,
      paymentProvider:     provider,
      ...(customerId     ? { paymentCustomerId:    customerId    } : {}),
      ...(subscriptionId ? { paddleSubscriptionId: subscriptionId } : {}),
    },
  });
  if (paymentId) {
    await prisma.payment.updateMany({
      where: { providerPaymentId: paymentId },
      data:  { status: PaymentStatus.COMPLETED },
    });
  }
  logger.info(`[Webhook] Subscription activated — user=${userId} plan=${planType} provider=${provider}`);
}

async function _handlePaymentFailure(event: NormalisedWebhookEvent): Promise<void> {
  const { userId, paymentId } = event;
  if (!userId) return;
  await prisma.user.update({ where: { id: userId }, data: { subscriptionStatus: SubscriptionStatus.SUSPENDED } });
  if (paymentId) {
    await prisma.payment.updateMany({ where: { providerPaymentId: paymentId }, data: { status: PaymentStatus.FAILED } });
  }
}

async function _handleSubCancelled(event: NormalisedWebhookEvent): Promise<void> {
  const { subscriptionId, userId } = event;
  let user: { id: string } | null = null;
  if (subscriptionId) {
    user = await prisma.user.findFirst({ where: { paddleSubscriptionId: subscriptionId }, select: { id: true } });
  }
  if (!user && userId) user = { id: userId };
  if (!user) return;
  await prisma.user.update({
    where: { id: user.id },
    data: { subscriptionStatus: SubscriptionStatus.CANCELLED, paddleSubscriptionId: null },
  });
}
