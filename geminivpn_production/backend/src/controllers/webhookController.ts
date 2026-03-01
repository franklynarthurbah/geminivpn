/**
 * Webhook Controller
 * Handles Stripe webhook events for payment processing
 */

import { Request, Response } from 'express';
import Stripe from 'stripe';
import { PrismaClient, SubscriptionStatus, PaymentStatus } from '@prisma/client';
import { logger } from '../utils/logger';

const prisma = new PrismaClient();

// Initialize Stripe
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY || '', {
  apiVersion: '2023-10-16',
});

const WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET || '';

/**
 * Handle Stripe webhook
 */
export const handleStripeWebhook = async (req: Request, res: Response): Promise<void> => {
  try {
    const signature = req.headers['stripe-signature'];

    if (!signature) {
      res.status(400).json({
        success: false,
        message: 'Missing Stripe signature',
      });
      return;
    }

    let event: Stripe.Event;

    try {
      event = stripe.webhooks.constructEvent(
        req.body,
        signature,
        WEBHOOK_SECRET
      );
    } catch (err: any) {
      logger.error('Webhook signature verification failed:', err.message);
      res.status(400).json({
        success: false,
        message: `Webhook Error: ${err.message}`,
      });
      return;
    }

    logger.info(`Processing Stripe webhook: ${event.type}`);

    // Handle different event types
    switch (event.type) {
      case 'checkout.session.completed':
        await handleCheckoutCompleted(event.data.object as Stripe.Checkout.Session);
        break;

      case 'invoice.payment_succeeded':
        await handleInvoicePaymentSucceeded(event.data.object as Stripe.Invoice);
        break;

      case 'invoice.payment_failed':
        await handleInvoicePaymentFailed(event.data.object as Stripe.Invoice);
        break;

      case 'customer.subscription.deleted':
        await handleSubscriptionDeleted(event.data.object as Stripe.Subscription);
        break;

      case 'customer.subscription.updated':
        await handleSubscriptionUpdated(event.data.object as Stripe.Subscription);
        break;

      default:
        logger.info(`Unhandled event type: ${event.type}`);
    }

    res.json({ received: true });
  } catch (error) {
    logger.error('Webhook error:', error);
    res.status(500).json({
      success: false,
      message: 'Webhook processing failed',
    });
  }
};

/**
 * Handle checkout.session.completed
 */
async function handleCheckoutCompleted(session: Stripe.Checkout.Session): Promise<void> {
  try {
    const userId = session.metadata?.userId;
    const planType = session.metadata?.planType;

    if (!userId || !planType) {
      logger.error('Missing metadata in checkout session');
      return;
    }

    // Update payment record
    await prisma.payment.updateMany({
      where: {
        userId,
        status: PaymentStatus.PENDING,
      },
      data: {
        stripePaymentId: session.payment_intent as string,
        stripeSubscriptionId: session.subscription as string,
        stripeCustomerId: session.customer as string,
        status: PaymentStatus.COMPLETED,
        paidAt: new Date(),
      },
    });

    // Calculate subscription end date
    const subscriptionEndsAt = new Date();
    switch (planType.toUpperCase()) {
      case 'MONTHLY':
        subscriptionEndsAt.setMonth(subscriptionEndsAt.getMonth() + 1);
        break;
      case 'YEARLY':
        subscriptionEndsAt.setFullYear(subscriptionEndsAt.getFullYear() + 1);
        break;
      case 'TWO_YEAR':
        subscriptionEndsAt.setFullYear(subscriptionEndsAt.getFullYear() + 2);
        break;
    }

    // Update user subscription status
    await prisma.user.update({
      where: { id: userId },
      data: {
        subscriptionStatus: SubscriptionStatus.ACTIVE,
        subscriptionEndsAt,
      },
    });

    logger.info(`Checkout completed for user ${userId}, plan: ${planType}`);
  } catch (error) {
    logger.error('Handle checkout completed error:', error);
  }
}

/**
 * Handle invoice.payment_succeeded
 */
async function handleInvoicePaymentSucceeded(invoice: Stripe.Invoice): Promise<void> {
  try {
    const subscriptionId = invoice.subscription as string;
    const customerId = invoice.customer as string;

    // Find user by customer ID
    const payment = await prisma.payment.findFirst({
      where: { stripeCustomerId: customerId },
    });

    if (!payment) {
      logger.error(`No user found for customer ${customerId}`);
      return;
    }

    // Create payment record for recurring payment
    if (invoice.billing_reason === 'subscription_cycle') {
      await prisma.payment.create({
        data: {
          userId: payment.userId,
          stripeCustomerId: customerId,
          stripeSubscriptionId: subscriptionId,
          stripePaymentId: invoice.payment_intent as string,
          amount: invoice.amount_paid / 100, // Convert from cents
          currency: invoice.currency,
          status: PaymentStatus.COMPLETED,
          paymentMethod: 'CARD',
          planType: payment.planType,
          planName: payment.planName,
          paidAt: new Date(),
        },
      });

      // Extend subscription
      const subscriptionEndsAt = new Date();
      switch (payment.planType) {
        case 'MONTHLY':
          subscriptionEndsAt.setMonth(subscriptionEndsAt.getMonth() + 1);
          break;
        case 'YEARLY':
          subscriptionEndsAt.setFullYear(subscriptionEndsAt.getFullYear() + 1);
          break;
        case 'TWO_YEAR':
          subscriptionEndsAt.setFullYear(subscriptionEndsAt.getFullYear() + 2);
          break;
      }

      await prisma.user.update({
        where: { id: payment.userId },
        data: {
          subscriptionStatus: SubscriptionStatus.ACTIVE,
          subscriptionEndsAt,
        },
      });

      logger.info(`Recurring payment succeeded for user ${payment.userId}`);
    }
  } catch (error) {
    logger.error('Handle invoice payment succeeded error:', error);
  }
}

/**
 * Handle invoice.payment_failed
 */
async function handleInvoicePaymentFailed(invoice: Stripe.Invoice): Promise<void> {
  try {
    const customerId = invoice.customer as string;

    const payment = await prisma.payment.findFirst({
      where: { stripeCustomerId: customerId },
    });

    if (!payment) {
      logger.error(`No user found for customer ${customerId}`);
      return;
    }

    // Update payment status
    await prisma.payment.create({
      data: {
        userId: payment.userId,
        stripeCustomerId: customerId,
        stripePaymentId: invoice.payment_intent as string,
        amount: invoice.amount_due / 100,
        currency: invoice.currency,
        status: PaymentStatus.FAILED,
        paymentMethod: 'CARD',
        planType: payment.planType,
        planName: payment.planName,
      },
    });

    // Suspend user after multiple failures (handled by Stripe's retry logic)
    logger.warn(`Payment failed for user ${payment.userId}`);
  } catch (error) {
    logger.error('Handle invoice payment failed error:', error);
  }
}

/**
 * Handle customer.subscription.deleted
 */
async function handleSubscriptionDeleted(subscription: Stripe.Subscription): Promise<void> {
  try {
    const customerId = subscription.customer as string;

    const payment = await prisma.payment.findFirst({
      where: { stripeCustomerId: customerId },
    });

    if (!payment) {
      logger.error(`No user found for customer ${customerId}`);
      return;
    }

    // Update user status to cancelled
    await prisma.user.update({
      where: { id: payment.userId },
      data: {
        subscriptionStatus: SubscriptionStatus.CANCELLED,
      },
    });

    logger.info(`Subscription cancelled for user ${payment.userId}`);
  } catch (error) {
    logger.error('Handle subscription deleted error:', error);
  }
}

/**
 * Handle customer.subscription.updated
 */
async function handleSubscriptionUpdated(subscription: Stripe.Subscription): Promise<void> {
  try {
    const customerId = subscription.customer as string;

    const payment = await prisma.payment.findFirst({
      where: { stripeCustomerId: customerId },
    });

    if (!payment) {
      logger.error(`No user found for customer ${customerId}`);
      return;
    }

    // Handle status changes
    if (subscription.status === 'past_due') {
      await prisma.user.update({
        where: { id: payment.userId },
        data: {
          subscriptionStatus: SubscriptionStatus.SUSPENDED,
        },
      });

      logger.warn(`Subscription past due for user ${payment.userId}`);
    }
  } catch (error) {
    logger.error('Handle subscription updated error:', error);
  }
}
