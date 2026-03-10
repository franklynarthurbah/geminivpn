/**
 * VPN Routes
 */

import { Router } from 'express';
import {
  getClients,
  createClient,
  getClientConfig,
  deleteClient,
  getConnectionStatus,
  connect,
  disconnect,
  getOverallStatus,
} from '../controllers/vpnController';
import { authenticate, requireSubscription } from '../middleware/auth';
import { createClientValidation } from '../middleware/validation';

const router = Router();

// All VPN routes require authentication and active subscription
router.use(authenticate);
router.use(requireSubscription);

// Client management
router.get('/clients', getClients);
router.post('/clients', createClientValidation, createClient);
router.get('/clients/:clientId', getClientConfig);
router.delete('/clients/:clientId', deleteClient);

// Connection management
router.get('/status', getOverallStatus);
router.get('/clients/:clientId/status', getConnectionStatus);
router.post('/clients/:clientId/connect', connect);
router.post('/clients/:clientId/disconnect', disconnect);

export default router;
