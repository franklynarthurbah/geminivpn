/**
 * Payment Routes
 */

import { Router } from 'express';
import {
  getPlans,
  createCheckout,
  getPaymentHistory,
  cancelSubscription,
  getSubscriptionStatus,
  createPortalSession,
} from '../controllers/paymentController';
import { authenticate } from '../middleware/auth';
import { createCheckoutValidation } from '../middleware/validation';

const router = Router();

// Public route
router.get('/plans', getPlans);

// Protected routes
router.use(authenticate);

router.post('/checkout', createCheckoutValidation, createCheckout);
router.get('/history', getPaymentHistory);
router.get('/subscription', getSubscriptionStatus);
router.post('/cancel', cancelSubscription);
router.post('/portal', createPortalSession);

export default router;
