/**
 * Payment Controller — GeminiVPN v3 (Combined)
 * Supports: Stripe · Square · Paddle · Coinbase
 */
import { Response } from 'express';
import { SubscriptionStatus, PlanType, PaymentStatus, PaymentProvider } from '../lib/enums';

import prisma from '../lib/prisma';
import { logger } from '../utils/logger';
import { AuthenticatedRequest } from '../types';
import { getPaymentService, PLANS, normalisePlanId, type ProviderKey } from '../services/payment';

// Lazy Stripe for getPlans (needs publishable key)
const getStripePK = () => process.env.STRIPE_PUBLISHABLE_KEY?.includes('placeholder') ? null : process.env.STRIPE_PUBLISHABLE_KEY;

// ─── GET /plans ───────────────────────────────────────────────────────────────
export const getPlans = async (_req: AuthenticatedRequest, res: Response): Promise<void> => {
  const plans = Object.values(PLANS).map(p => ({
    id:           p.id,
    name:         p.name,
    description:  p.description,
    price:        p.price,
    currency:     p.currency,
    intervalDays: p.intervalDays,
    features:     p.features,
  }));

  const availableProviders = [
    process.env.STRIPE_SECRET_KEY && !process.env.STRIPE_SECRET_KEY.includes('placeholder') ? 'stripe' : null,
    process.env.SQUARE_ACCESS_TOKEN && process.env.SQUARE_ACCESS_TOKEN !== 'placeholder' ? 'square' : null,
    process.env.PADDLE_API_KEY && process.env.PADDLE_API_KEY !== 'placeholder' ? 'paddle' : null,
    process.env.COINBASE_COMMERCE_API_KEY && process.env.COINBASE_COMMERCE_API_KEY !== 'placeholder' ? 'coinbase' : null,
  ].filter(Boolean);

  res.json({ success: true, data: plans, providers: availableProviders });
};

// ─── POST /checkout ────────────────────────────────────────────────────────────
export const createCheckout = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) { res.status(401).json({ success: false, message: 'Authentication required' }); return; }

    const { planType, provider = 'stripe', successUrl, cancelUrl } = req.body;

    // Resolve plan
    const planId = normalisePlanId(planType);
    if (!planId) { res.status(400).json({ success: false, message: `Invalid planType: "${planType}"` }); return; }
    const plan = PLANS[planId];

    // Handle Stripe separately (uses its own SDK not the service interface)
    if (provider === 'stripe') {
      await _createStripeCheckout(req, res, plan, planId, successUrl, cancelUrl);
      return;
    }

    // Non-Stripe providers
    let svc: any;
    try {
      svc = getPaymentService(provider);
    } catch {
      res.status(400).json({ success: false, message: `Unknown provider "${provider}". Use: stripe, square, paddle, coinbase` });
      return;
    }

    const dbPlanType = _planIdToEnum(planId);
    logger.info(`[Payment] Checkout — user=${req.user.id} plan=${planType} provider=${provider}`);

    const result = await svc.createCheckout({
      userId:    req.user.id,
      userEmail: req.user.email,
      userName:  req.user.name,
      plan,
      planType:  dbPlanType,
      successUrl,
      cancelUrl,
    });

    await prisma.payment.create({
      data: {
        userId:            req.user.id,
        providerPaymentId: result.providerPaymentId,
        provider:          result.provider,
        amount:            plan.amountCents,
        currency:          'usd',
        status:            PaymentStatus.PENDING,
        planType:          dbPlanType,
        metadata:          JSON.stringify({ provider, planId }),
      },
    });

    res.json({ success: true, data: { sessionId: result.providerPaymentId, checkoutUrl: result.checkoutUrl, provider: result.provider } });
  } catch (error: any) {
    logger.error('[Payment] createCheckout error:', { message: error.message, user: req.user?.id });
    res.status(500).json({ success: false, message: error.message || 'Failed to create checkout session' });
  }
};

async function _createStripeCheckout(req: any, res: Response, plan: any, planId: string, successUrl: string, cancelUrl: string) {
  const sk = process.env.STRIPE_SECRET_KEY || '';
  if (!sk || sk.includes('placeholder')) {
    res.status(503).json({ success: false, message: 'Stripe not configured. Please choose: square, paddle, or coinbase' });
    return;
  }
  try {
    const Stripe = require('stripe');
    const stripe = new Stripe(sk, { apiVersion: '2023-10-16' });

    const priceMap: Record<string, string | undefined> = {
      monthly:    process.env.STRIPE_MONTHLY_PRICE_ID,
      yearly:     process.env.STRIPE_YEARLY_PRICE_ID,
      'two-year': process.env.STRIPE_TWO_YEAR_PRICE_ID,
    };
    const priceId = priceMap[planId];
    if (!priceId || priceId.includes('placeholder')) {
      res.status(503).json({ success: false, message: 'Stripe price IDs not configured. Run: sudo bash geminivpn.sh --stripe' });
      return;
    }

    const session = await stripe.checkout.sessions.create({
      customer_email: req.user.email,
      line_items: [{ price: priceId, quantity: 1 }],
      mode: 'subscription',
      success_url: successUrl || `${process.env.FRONTEND_URL}/payment/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url:  cancelUrl  || `${process.env.FRONTEND_URL}/pricing`,
      metadata: { userId: req.user.id, planType: _planIdToEnum(planId) },
    });

    await prisma.payment.create({
      data: {
        userId:          req.user.id,
        stripePaymentId: session.id,
        provider:        PaymentProvider.STRIPE,
        amount:          plan.amountCents,
        currency:        'usd',
        status:          PaymentStatus.PENDING,
        planType:        _planIdToEnum(planId),
      },
    });

    res.json({ success: true, data: { sessionId: session.id, checkoutUrl: session.url, provider: 'STRIPE' } });
  } catch (err: any) {
    logger.error('[Payment] Stripe checkout error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
}

// ─── GET /subscription ─────────────────────────────────────────────────────────
export const getSubscriptionStatus = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) { res.status(401).json({ success: false, message: 'Authentication required' }); return; }
    const user = await prisma.user.findUnique({
      where:  { id: req.user.id },
      select: { subscriptionStatus: true, trialEndsAt: true, subscriptionEndsAt: true, paymentProvider: true },
    });
    if (!user) { res.status(404).json({ success: false, message: 'User not found' }); return; }
    let status = user.subscriptionStatus;
    if (status === SubscriptionStatus.TRIAL && user.trialEndsAt && new Date() > user.trialEndsAt) {
      status = SubscriptionStatus.EXPIRED;
      await prisma.user.update({ where: { id: req.user.id }, data: { subscriptionStatus: SubscriptionStatus.EXPIRED } });
    }
    res.json({
      success: true,
      data: {
        subscriptionStatus: status, trialEndsAt: user.trialEndsAt,
        subscriptionEndsAt: user.subscriptionEndsAt, paymentProvider: user.paymentProvider,
        isActive: status === SubscriptionStatus.ACTIVE || status === SubscriptionStatus.TRIAL,
      },
    });
  } catch (error) { res.status(500).json({ success: false, message: 'Failed to get subscription status' }); }
};

// ─── GET /history ──────────────────────────────────────────────────────────────
export const getPaymentHistory = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) { res.status(401).json({ success: false, message: 'Authentication required' }); return; }
    const payments = await prisma.payment.findMany({
      where: { userId: req.user.id }, orderBy: { createdAt: 'desc' }, take: 20,
      select: { id: true, provider: true, amount: true, currency: true, status: true, planType: true, createdAt: true },
    });
    res.json({ success: true, data: payments });
  } catch (error) { res.status(500).json({ success: false, message: 'Failed to get payment history' }); }
};

// ─── POST /cancel ──────────────────────────────────────────────────────────────
export const cancelSubscription = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) { res.status(401).json({ success: false, message: 'Authentication required' }); return; }
    const user = await prisma.user.findUnique({
      where: { id: req.user.id }, select: { paddleSubscriptionId: true, paymentProvider: true },
    });
    if (!user) { res.status(404).json({ success: false, message: 'User not found' }); return; }

    if (user.paymentProvider === PaymentProvider.PADDLE && user.paddleSubscriptionId) {
      try {
        const svc = getPaymentService('paddle');
        const result = await svc.cancelSubscription({ userId: req.user.id, paddleSubscriptionId: user.paddleSubscriptionId });
        await prisma.user.update({
          where: { id: req.user.id },
          data: { subscriptionStatus: SubscriptionStatus.CANCELLED, ...(result.endsAt ? { subscriptionEndsAt: result.endsAt } : {}) },
        });
        res.json({ success: true, message: result.endsAt ? `Subscription will end on ${result.endsAt.toISOString()}` : 'Subscription cancelled', data: { endsAt: result.endsAt } });
        return;
      } catch (err: any) { logger.error('[Payment] Paddle cancel failed:', err.message); }
    }

    await prisma.user.update({ where: { id: req.user.id }, data: { subscriptionStatus: SubscriptionStatus.CANCELLED } });
    res.json({ success: true, message: 'Subscription cancelled' });
  } catch (error: any) { res.status(500).json({ success: false, message: 'Failed to cancel subscription' }); }
};

// ─── POST /portal ──────────────────────────────────────────────────────────────
export const createPortalSession = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) { res.status(401).json({ success: false, message: 'Authentication required' }); return; }
    const user = await prisma.user.findUnique({ where: { id: req.user.id }, select: { paymentProvider: true, stripeCustomerId: true } });
    const returnUrl = req.body.returnUrl || process.env.FRONTEND_URL || 'https://localhost';

    if (user?.paymentProvider === PaymentProvider.STRIPE && user.stripeCustomerId) {
      const sk = process.env.STRIPE_SECRET_KEY || '';
      if (sk && !sk.includes('placeholder')) {
        try {
          const Stripe = require('stripe');
          const stripe = new Stripe(sk, { apiVersion: '2023-10-16' });
          const portal = await stripe.billingPortal.sessions.create({ customer: user.stripeCustomerId, return_url: returnUrl });
          res.json({ success: true, data: { url: portal.url, provider: 'STRIPE' } });
          return;
        } catch (err: any) { logger.error('[Payment] Stripe portal error:', err.message); }
      }
    }

    res.json({ success: true, data: { url: `${returnUrl}?tab=billing`, provider: user?.paymentProvider || 'N/A', message: 'View your payment history in the account dashboard' } });
  } catch (error: any) { res.status(500).json({ success: false, message: 'Failed to create portal session' }); }
};

// Alias for backward compat
export const createCheckoutSession = createCheckout;

function _planIdToEnum(planId: string): string {
  return ({ monthly: 'MONTHLY', yearly: 'YEARLY', 'two-year': 'TWO_YEAR' } as any)[planId] || 'MONTHLY';
}
