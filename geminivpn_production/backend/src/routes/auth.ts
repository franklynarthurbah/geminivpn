/**
 * Authentication Routes
 */

import { Router } from 'express';
import {
  register,
  login,
  logout,
  refreshToken,
  getProfile,
  checkSubscription,
} from '../controllers/authController';
import { authenticate, optionalAuth } from '../middleware/auth';
import {
  registerValidation,
  loginValidation,
  refreshTokenValidation,
} from '../middleware/validation';

const router = Router();

// Public routes
router.post('/register', registerValidation, register);
router.post('/login', loginValidation, login);
router.post('/refresh', refreshTokenValidation, refreshToken);

// Protected routes
router.post('/logout', optionalAuth, logout);
router.get('/profile', authenticate, getProfile);
router.get('/subscription', authenticate, checkSubscription);

export default router;
