/**
 * Webhook Routes
 */

import { Router } from 'express';
import { handleStripeWebhook } from '../controllers/webhookController';

const router = Router();

// Stripe webhook endpoint (raw body needed for signature verification)
router.post(
  '/stripe',
  // Note: In server.ts, you need to add raw body parser for this route
  handleStripeWebhook
);

export default router;
