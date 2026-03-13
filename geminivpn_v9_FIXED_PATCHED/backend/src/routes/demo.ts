/**
 * Demo Account Routes
 * POST /api/v1/demo/generate  — public, rate-limited to 1/IP/24h
 * POST /api/v1/demo/cleanup   — admin only
 * GET  /api/v1/demo/metrics   — admin only
 */
import { Router } from 'express';
import { generateDemoAccount, cleanupExpiredDemoAccounts, getDemoMetrics } from '../controllers/demoController';
import { authenticate } from '../middleware/auth';

const router = Router();

// Public: generate a 60-minute demo account
router.post('/generate', generateDemoAccount);

// Admin: cleanup expired accounts + metrics
// (any authenticated user for now — add role check when admin role is added)
router.post('/cleanup', authenticate, cleanupExpiredDemoAccounts);
router.get('/metrics',  authenticate, getDemoMetrics);

export default router;
