import { Router } from 'express';
import { authenticate, authenticateForPayment } from '../middleware/auth';
import {
  getPlans,
  createCheckout,
  createCheckoutSession,
  getSubscriptionStatus,
  getPaymentHistory,
  cancelSubscription,
  createPortalSession,
} from '../controllers/paymentController';

const router = Router();

// /plans — public (shows configured providers + pricing)
router.get('/plans',        getPlans);
// Checkout & portal use authenticateForPayment: verifies JWT but does NOT block
// EXPIRED/SUSPENDED users — they must be able to reach here to renew
router.post('/checkout',    authenticateForPayment, createCheckout);
router.post('/create-checkout-session', authenticateForPayment, createCheckoutSession);
router.post('/portal',      authenticateForPayment, createPortalSession);
// Read-only subscription info — same loose auth
router.get('/subscription', authenticateForPayment, getSubscriptionStatus);
// History and cancel need active auth (no reason an expired user needs these)
router.get('/history',      authenticate, getPaymentHistory);
router.post('/cancel',      authenticate, cancelSubscription);

export default router;
