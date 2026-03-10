/**
 * Payment Controller — complete with all exports required by payment.ts route
 */
import { Response } from 'express';
import Stripe from 'stripe';
import { PrismaClient, SubscriptionStatus, PlanType, PaymentStatus } from '@prisma/client';
import { AuthenticatedRequest, SubscriptionPlan, CheckoutSession } from '../types';
import { logger } from '../utils/logger';

const prisma = new PrismaClient();

const getStripe = (): Stripe | null => {
  const key = process.env.STRIPE_SECRET_KEY || '';
  if (!key || key === 'sk_placeholder') return null;
  return new Stripe(key, { apiVersion: '2023-10-16' });
};

const PLANS: SubscriptionPlan[] = [
  { id:'monthly',  name:'Monthly', description:'Billed monthly. Cancel anytime.', price:11.99, currency:'USD', interval:'month', intervalCount:1,  stripePriceId: process.env.STRIPE_MONTHLY_PRICE_ID  || '', features:['10 devices','10 Gbps','No logs','Kill switch','24/7 support'] },
  { id:'yearly',   name:'1-Year',  description:'Save 58%. Billed annually.',      price:4.99,  currency:'USD', interval:'month', intervalCount:12, stripePriceId: process.env.STRIPE_YEARLY_PRICE_ID   || '', features:['10 devices','10 Gbps','No logs','Kill switch','24/7 support','Priority servers'] },
  { id:'two-year', name:'2-Year',  description:'Save 71%. Best value.',           price:3.49,  currency:'USD', interval:'month', intervalCount:24, stripePriceId: process.env.STRIPE_TWO_YEAR_PRICE_ID || '', features:['10 devices','10 Gbps','No logs','Kill switch','24/7 support','Priority servers','Dedicated IP'] },
];

const planTypeMap: Record<string, PlanType> = {
  MONTHLY: PlanType.MONTHLY, YEARLY: PlanType.YEARLY, TWO_YEAR: PlanType.TWO_YEAR,
  monthly: PlanType.MONTHLY, yearly: PlanType.YEARLY, 'two-year': PlanType.TWO_YEAR,
};

export const getPlans = async (_req: AuthenticatedRequest, res: Response): Promise<void> => {
  res.json({ success: true, data: PLANS });
};

export const createCheckout = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) { res.status(401).json({ success: false, message: 'Authentication required' }); return; }
    const stripe = getStripe();
    if (!stripe) { res.status(503).json({ success: false, message: 'Payment not configured. Contact support.' }); return; }
    const { planType, successUrl, cancelUrl } = req.body;
    const plan = PLANS.find((p) => p.id === planType?.toLowerCase() || p.id === planType);
    if (!plan) { res.status(400).json({ success: false, message: 'Invalid plan type' }); return; }
    let customerId = req.user.stripeCustomerId;
    if (!customerId) {
      const customer = await stripe.customers.create({ email: req.user.email, name: req.user.name || undefined });
      customerId = customer.id;
      await prisma.user.update({ where: { id: req.user.id }, data: { stripeCustomerId: customerId } });
    }
    const session = await stripe.checkout.sessions.create({
      customer: customerId, mode: 'subscription', payment_method_types: ['card'],
      line_items: [{ price: plan.stripePriceId, quantity: 1 }],
      success_url: successUrl, cancel_url: cancelUrl,
      metadata: { userId: req.user.id, planType: planType.toUpperCase() },
    });
    const dbPlanType = planTypeMap[planType] || PlanType.MONTHLY;
    await prisma.payment.create({ data: { userId: req.user.id, stripePaymentId: session.id, amount: Math.round(plan.price * 100), currency: 'usd', status: PaymentStatus.PENDING, planType: dbPlanType } });
    const checkoutSession: CheckoutSession = { sessionId: session.id, url: session.url! };
    res.json({ success: true, data: checkoutSession });
  } catch (error: any) {
    logger.error('Create checkout error:', error);
    res.status(500).json({ success: false, message: 'Failed to create checkout session' });
  }
};

// Alias for any code still using the old name
export const createCheckoutSession = createCheckout;

export const getSubscriptionStatus = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) { res.status(401).json({ success: false, message: 'Authentication required' }); return; }
    const user = await prisma.user.findUnique({ where: { id: req.user.id }, select: { subscriptionStatus: true, trialEndsAt: true, subscriptionEndsAt: true, stripeSubscriptionId: true } });
    if (!user) { res.status(404).json({ success: false, message: 'User not found' }); return; }
    let status = user.subscriptionStatus;
    if (status === SubscriptionStatus.TRIAL && user.trialEndsAt && new Date() > user.trialEndsAt) {
      status = SubscriptionStatus.EXPIRED;
      await prisma.user.update({ where: { id: req.user.id }, data: { subscriptionStatus: SubscriptionStatus.EXPIRED } });
    }
    res.json({ success: true, data: { subscriptionStatus: status, trialEndsAt: user.trialEndsAt, subscriptionEndsAt: user.subscriptionEndsAt, isActive: status === SubscriptionStatus.ACTIVE || status === SubscriptionStatus.TRIAL } });
  } catch (error) {
    logger.error('Get subscription status error:', error);
    res.status(500).json({ success: false, message: 'Failed to get subscription status' });
  }
};

export const getPaymentHistory = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) { res.status(401).json({ success: false, message: 'Authentication required' }); return; }
    const payments = await prisma.payment.findMany({ where: { userId: req.user.id }, orderBy: { createdAt: 'desc' }, take: 20 });
    res.json({ success: true, data: payments });
  } catch (error) {
    logger.error('Get payment history error:', error);
    res.status(500).json({ success: false, message: 'Failed to get payment history' });
  }
};

export const cancelSubscription = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) { res.status(401).json({ success: false, message: 'Authentication required' }); return; }
    const stripe = getStripe();
    if (!stripe) {
      await prisma.user.update({ where: { id: req.user.id }, data: { subscriptionStatus: SubscriptionStatus.CANCELLED } });
      res.json({ success: true, message: 'Subscription cancelled' }); return;
    }
    const user = await prisma.user.findUnique({ where: { id: req.user.id } });
    if (!user?.stripeSubscriptionId) { res.status(400).json({ success: false, message: 'No active subscription found' }); return; }
    await stripe.subscriptions.update(user.stripeSubscriptionId, { cancel_at_period_end: true });
    await prisma.user.update({ where: { id: req.user.id }, data: { subscriptionStatus: SubscriptionStatus.CANCELLED } });
    res.json({ success: true, message: 'Subscription will be cancelled at end of billing period' });
  } catch (error: any) {
    logger.error('Cancel subscription error:', error);
    res.status(500).json({ success: false, message: 'Failed to cancel subscription' });
  }
};

export const createPortalSession = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) { res.status(401).json({ success: false, message: 'Authentication required' }); return; }
    const stripe = getStripe();
    if (!stripe) { res.status(503).json({ success: false, message: 'Payment not configured. Contact support.' }); return; }
    const user = await prisma.user.findUnique({ where: { id: req.user.id } });
    if (!user?.stripeCustomerId) { res.status(400).json({ success: false, message: 'No billing account found' }); return; }
    const { returnUrl } = req.body;
    const session = await stripe.billingPortal.sessions.create({ customer: user.stripeCustomerId, return_url: returnUrl || process.env.FRONTEND_URL || 'https://localhost' });
    res.json({ success: true, data: { url: session.url } });
  } catch (error: any) {
    logger.error('Create portal session error:', error);
    res.status(500).json({ success: false, message: 'Failed to create billing portal session' });
  }
};
