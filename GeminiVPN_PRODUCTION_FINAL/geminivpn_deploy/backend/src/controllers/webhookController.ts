/**
 * Webhook Controller — lazy Stripe instantiation (never throws on empty key)
 */
import { Request, Response } from 'express';
import Stripe from 'stripe';
import { PrismaClient, SubscriptionStatus, PaymentStatus } from '@prisma/client';
import { logger } from '../utils/logger';

const prisma = new PrismaClient();

// Lazy getter — only instantiates Stripe when a webhook actually arrives.
// Prevents crash-on-startup when STRIPE_SECRET_KEY is placeholder/empty.
let _stripe: Stripe | null = null;
const getStripe = (): Stripe | null => {
  const key = process.env.STRIPE_SECRET_KEY || '';
  if (!key || key === 'sk_placeholder') return null;
  if (!_stripe) _stripe = new Stripe(key, { apiVersion: '2023-10-16' });
  return _stripe;
};

const WEBHOOK_SECRET = (): string => process.env.STRIPE_WEBHOOK_SECRET || '';

export const handleStripeWebhook = async (req: Request, res: Response): Promise<void> => {
  try {
    const stripe = getStripe();
    if (!stripe) {
      logger.warn('Stripe webhook received but Stripe is not configured');
      res.status(503).json({ success: false, message: 'Payment not configured' });
      return;
    }

    const signature = req.headers['stripe-signature'];
    if (!signature) { res.status(400).json({ success: false, message: 'Missing Stripe signature' }); return; }

    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(req.body, signature, WEBHOOK_SECRET());
    } catch (err: any) {
      logger.error('Webhook signature verification failed:', err.message);
      res.status(400).json({ success: false, message: `Webhook Error: ${err.message}` }); return;
    }

    logger.info(`Processing Stripe webhook: ${event.type}`);

    switch (event.type) {
      case 'checkout.session.completed':
        await handleCheckoutCompleted(event.data.object as Stripe.Checkout.Session); break;
      case 'invoice.payment_succeeded':
        await handlePaymentSucceeded(event.data.object as Stripe.Invoice); break;
      case 'invoice.payment_failed':
        await handlePaymentFailed(event.data.object as Stripe.Invoice); break;
      case 'customer.subscription.deleted':
        await handleSubscriptionCancelled(event.data.object as Stripe.Subscription); break;
      default:
        logger.info(`Unhandled webhook event: ${event.type}`);
    }

    res.json({ received: true });
  } catch (error) {
    logger.error('Webhook handler error:', error);
    res.status(500).json({ success: false, message: 'Webhook processing failed' });
  }
};

async function handleCheckoutCompleted(session: Stripe.Checkout.Session) {
  const userId   = session.metadata?.userId;
  const planType = session.metadata?.planType;
  if (!userId || !planType) { logger.warn('Webhook: missing metadata in checkout.session.completed'); return; }
  const daysMap: Record<string, number> = { MONTHLY: 30, YEARLY: 365, TWO_YEAR: 730 };
  const durationDays     = daysMap[planType] || 30;
  const subscriptionEndsAt = new Date(Date.now() + durationDays * 86400 * 1000);
  await prisma.user.update({
    where: { id: userId },
    data:  { subscriptionStatus: SubscriptionStatus.ACTIVE, subscriptionEndsAt, stripeSubscriptionId: session.subscription as string },
  });
  if (session.id) {
    await prisma.payment.updateMany({ where: { stripePaymentId: session.id }, data: { status: PaymentStatus.COMPLETED } });
  }
  logger.info(`Checkout completed for user ${userId}, plan ${planType}`);
}

async function handlePaymentSucceeded(invoice: Stripe.Invoice) {
  const customerId = invoice.customer as string;
  const user = await prisma.user.findFirst({ where: { stripeCustomerId: customerId } });
  if (!user) return;
  const newEndsAt = new Date(Math.max(Date.now(), user.subscriptionEndsAt?.getTime() || Date.now()) + 30 * 86400 * 1000);
  await prisma.user.update({ where: { id: user.id }, data: { subscriptionStatus: SubscriptionStatus.ACTIVE, subscriptionEndsAt: newEndsAt } });
  logger.info(`Subscription renewed for user ${user.email}`);
}

async function handlePaymentFailed(invoice: Stripe.Invoice) {
  const customerId = invoice.customer as string;
  const user = await prisma.user.findFirst({ where: { stripeCustomerId: customerId } });
  if (!user) return;
  await prisma.user.update({ where: { id: user.id }, data: { subscriptionStatus: SubscriptionStatus.SUSPENDED } });
  logger.warn(`Payment failed for user ${user.email}`);
}

async function handleSubscriptionCancelled(subscription: Stripe.Subscription) {
  const user = await prisma.user.findFirst({ where: { stripeSubscriptionId: subscription.id } });
  if (!user) return;
  await prisma.user.update({ where: { id: user.id }, data: { subscriptionStatus: SubscriptionStatus.CANCELLED, stripeSubscriptionId: null } });
  logger.info(`Subscription cancelled for user ${user.email}`);
}
