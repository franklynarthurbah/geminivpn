/**
 * Payment Controller
 * Handles Stripe payment integration for subscriptions
 */

import { Response } from 'express';
import Stripe from 'stripe';
import { PrismaClient, SubscriptionStatus, PlanType, PaymentStatus } from '@prisma/client';
import { AuthenticatedRequest, SubscriptionPlan, CheckoutSession } from '../types';
import { logger } from '../utils/logger';

const prisma = new PrismaClient();

// Initialize Stripe
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY || '', {
  apiVersion: '2023-10-16',
});

// Plan configurations
const SUBSCRIPTION_PLANS: SubscriptionPlan[] = [
  {
    id: 'monthly',
    name: 'Monthly',
    description: 'Billed monthly. Cancel anytime.',
    price: 11.99,
    currency: 'USD',
    interval: 'month',
    intervalCount: 1,
    features: [
      '10 simultaneous devices',
      '10 Gbps server speeds',
      'No logs policy',
      'Kill switch',
      '24/7 support',
    ],
    stripePriceId: process.env.STRIPE_MONTHLY_PRICE_ID || '',
  },
  {
    id: 'yearly',
    name: '1-Year',
    description: 'Save 58%. Billed annually.',
    price: 4.99,
    currency: 'USD',
    interval: 'month',
    intervalCount: 12,
    features: [
      '10 simultaneous devices',
      '10 Gbps server speeds',
      'No logs policy',
      'Kill switch',
      '24/7 support',
      'Priority servers',
    ],
    stripePriceId: process.env.STRIPE_YEARLY_PRICE_ID || '',
  },
  {
    id: 'two-year',
    name: '2-Year',
    description: 'Save 71%. Best value.',
    price: 3.49,
    currency: 'USD',
    interval: 'month',
    intervalCount: 24,
    features: [
      '10 simultaneous devices',
      '10 Gbps server speeds',
      'No logs policy',
      'Kill switch',
      '24/7 support',
      'Priority servers',
      'Dedicated IP option',
    ],
    stripePriceId: process.env.STRIPE_TWO_YEAR_PRICE_ID || '',
  },
];

/**
 * Get available subscription plans
 */
export const getPlans = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    res.json({
      success: true,
      data: SUBSCRIPTION_PLANS,
    });
  } catch (error) {
    logger.error('Get plans error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get subscription plans',
    });
  }
};

/**
 * Create checkout session for subscription
 */
export const createCheckout = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const { planType, successUrl, cancelUrl } = req.body;

    // Find plan
    const plan = SUBSCRIPTION_PLANS.find(p => p.id === planType);
    if (!plan) {
      res.status(400).json({
        success: false,
        message: 'Invalid plan type',
      });
      return;
    }

    // Get or create Stripe customer
    let customerId: string;
    
    // Check for existing payments to get customer ID
    const existingPayment = await prisma.payment.findFirst({
      where: { userId: req.user.id },
      orderBy: { createdAt: 'desc' },
    });

    if (existingPayment?.stripeCustomerId) {
      customerId = existingPayment.stripeCustomerId;
    } else {
      // Create new Stripe customer
      const customer = await stripe.customers.create({
        email: req.user.email,
        name: req.user.name || undefined,
        metadata: {
          userId: req.user.id,
        },
      });
      customerId = customer.id;
    }

    // Create checkout session
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      payment_method_types: ['card', 'paypal'],
      line_items: [
        {
          price: plan.stripePriceId,
          quantity: 1,
        },
      ],
      mode: 'subscription',
      success_url: successUrl,
      cancel_url: cancelUrl,
      metadata: {
        userId: req.user.id,
        planType: planType,
      },
      subscription_data: {
        metadata: {
          userId: req.user.id,
          planType: planType,
        },
      },
    });

    // Create pending payment record
    await prisma.payment.create({
      data: {
        userId: req.user.id,
        stripeCustomerId: customerId,
        amount: plan.price * (plan.intervalCount === 1 ? 1 : plan.intervalCount),
        currency: plan.currency.toLowerCase(),
        status: PaymentStatus.PENDING,
        paymentMethod: 'CARD', // Will be updated by webhook
        planType: planType.toUpperCase() as PlanType,
        planName: plan.name,
      },
    });

    logger.info(`Checkout session created: ${session.id} for user ${req.user.email}`);

    const checkoutSession: CheckoutSession = {
      sessionId: session.id,
      url: session.url || '',
    };

    res.json({
      success: true,
      data: checkoutSession,
    });
  } catch (error) {
    logger.error('Create checkout error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create checkout session',
    });
  }
};

/**
 * Get user's payment history
 */
export const getPaymentHistory = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const payments = await prisma.payment.findMany({
      where: { userId: req.user.id },
      orderBy: { createdAt: 'desc' },
    });

    res.json({
      success: true,
      data: payments,
    });
  } catch (error) {
    logger.error('Get payment history error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get payment history',
    });
  }
};

/**
 * Cancel subscription
 */
export const cancelSubscription = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    // Find active subscription
    const activePayment = await prisma.payment.findFirst({
      where: {
        userId: req.user.id,
        status: PaymentStatus.COMPLETED,
        stripeSubscriptionId: { not: null },
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!activePayment?.stripeSubscriptionId) {
      res.status(404).json({
        success: false,
        message: 'No active subscription found',
      });
      return;
    }

    // Cancel in Stripe
    await stripe.subscriptions.cancel(activePayment.stripeSubscriptionId);

    // Update user status
    await prisma.user.update({
      where: { id: req.user.id },
      data: { subscriptionStatus: SubscriptionStatus.CANCELLED },
    });

    logger.info(`Subscription cancelled for user ${req.user.email}`);

    res.json({
      success: true,
      message: 'Subscription cancelled successfully',
    });
  } catch (error) {
    logger.error('Cancel subscription error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to cancel subscription',
    });
  }
};

/**
 * Get subscription status
 */
export const getSubscriptionStatus = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
      select: {
        subscriptionStatus: true,
        trialEndsAt: true,
        subscriptionEndsAt: true,
      },
    });

    if (!user) {
      res.status(404).json({
        success: false,
        message: 'User not found',
      });
      return;
    }

    // Get active subscription details if any
    const activePayment = await prisma.payment.findFirst({
      where: {
        userId: req.user.id,
        status: PaymentStatus.COMPLETED,
      },
      orderBy: { createdAt: 'desc' },
    });

    res.json({
      success: true,
      data: {
        subscriptionStatus: user.subscriptionStatus,
        trialEndsAt: user.trialEndsAt,
        subscriptionEndsAt: user.subscriptionEndsAt,
        currentPlan: activePayment?.planName || null,
        nextBillingDate: activePayment ? calculateNextBillingDate(activePayment) : null,
      },
    });
  } catch (error) {
    logger.error('Get subscription status error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get subscription status',
    });
  }
};

/**
 * Create customer portal session
 */
export const createPortalSession = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const { returnUrl } = req.body;

    // Get customer ID
    const payment = await prisma.payment.findFirst({
      where: { userId: req.user.id },
      orderBy: { createdAt: 'desc' },
    });

    if (!payment?.stripeCustomerId) {
      res.status(404).json({
        success: false,
        message: 'No Stripe customer found',
      });
      return;
    }

    // Create portal session
    const session = await stripe.billingPortal.sessions.create({
      customer: payment.stripeCustomerId,
      return_url: returnUrl,
    });

    res.json({
      success: true,
      data: {
        url: session.url,
      },
    });
  } catch (error) {
    logger.error('Create portal session error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create portal session',
    });
  }
};

/**
 * Calculate next billing date based on plan
 */
function calculateNextBillingDate(payment: any): Date | null {
  if (!payment.paidAt) return null;

  const date = new Date(payment.paidAt);
  
  switch (payment.planType) {
    case 'MONTHLY':
      date.setMonth(date.getMonth() + 1);
      break;
    case 'YEARLY':
      date.setFullYear(date.getFullYear() + 1);
      break;
    case 'TWO_YEAR':
      date.setFullYear(date.getFullYear() + 2);
      break;
    default:
      return null;
  }

  return date;
}

export { SUBSCRIPTION_PLANS };
