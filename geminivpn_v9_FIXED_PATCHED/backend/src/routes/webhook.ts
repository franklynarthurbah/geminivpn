import { Router } from 'express';
import {
  handleStripeWebhook,
  handleSquareWebhook,
  handlePaddleWebhook,
  handleCoinbaseWebhook,
} from '../controllers/webhookController';

const router = Router();

// Note: raw body parsing is set in server.ts BEFORE express.json()
// These routes therefore receive req.body as a Buffer
router.post('/stripe',   handleStripeWebhook);
router.post('/square',   handleSquareWebhook);
router.post('/paddle',   handlePaddleWebhook);
router.post('/coinbase', handleCoinbaseWebhook);

export default router;
