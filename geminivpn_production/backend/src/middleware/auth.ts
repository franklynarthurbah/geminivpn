/**
 * Authentication Middleware
 * Handles JWT verification and user authorization
 */

import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { PrismaClient } from '@prisma/client';
import { AuthenticatedRequest, JWTPayload } from '../types';
import { logger } from '../utils/logger';

const prisma = new PrismaClient();

const JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'your-access-secret';

/**
 * Verify JWT access token and attach user to request
 */
export const authenticate = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    // Get token from header
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({
        success: false,
        message: 'Access token required',
      });
      return;
    }

    const token = authHeader.substring(7);

    // Verify token
    const decoded = jwt.verify(token, JWT_ACCESS_SECRET) as JWTPayload;

    // Check if user exists and is active
    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      include: {
        sessions: {
          where: {
            isValid: true,
            expiresAt: { gt: new Date() },
          },
        },
      },
    });

    if (!user) {
      res.status(401).json({
        success: false,
        message: 'User not found',
      });
      return;
    }

    if (!user.isActive) {
      res.status(403).json({
        success: false,
        message: 'Account is deactivated',
      });
      return;
    }

    // Check subscription status
    if (user.subscriptionStatus === 'EXPIRED' || user.subscriptionStatus === 'SUSPENDED') {
      res.status(403).json({
        success: false,
        message: 'Subscription expired. Please renew to continue.',
        data: {
          subscriptionStatus: user.subscriptionStatus,
        },
      });
      return;
    }

    // Attach user to request
    req.user = user;
    req.token = token;

    next();
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      res.status(401).json({
        success: false,
        message: 'Token expired',
        error: {
          code: 'TOKEN_EXPIRED',
        },
      });
      return;
    }

    if (error instanceof jwt.JsonWebTokenError) {
      res.status(401).json({
        success: false,
        message: 'Invalid token',
      });
      return;
    }

    logger.error('Authentication error:', error);
    res.status(500).json({
      success: false,
      message: 'Authentication failed',
    });
  }
};

/**
 * Optional authentication - attaches user if token valid, but doesn't require it
 */
export const optionalAuth = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      next();
      return;
    }

    const token = authHeader.substring(7);
    const decoded = jwt.verify(token, JWT_ACCESS_SECRET) as JWTPayload;

    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
    });

    if (user && user.isActive) {
      req.user = user;
      req.token = token;
    }

    next();
  } catch (error) {
    // Silently continue without user
    next();
  }
};

/**
 * Check if user has active subscription
 */
export const requireSubscription = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): void => {
  if (!req.user) {
    res.status(401).json({
      success: false,
      message: 'Authentication required',
    });
    return;
  }

  const allowedStatuses = ['ACTIVE', 'TRIAL'];
  
  if (!allowedStatuses.includes(req.user.subscriptionStatus)) {
    res.status(403).json({
      success: false,
      message: 'Active subscription required',
      data: {
        subscriptionStatus: req.user.subscriptionStatus,
      },
    });
    return;
  }

  // Check trial expiration
  if (req.user.subscriptionStatus === 'TRIAL' && req.user.trialEndsAt) {
    if (new Date() > req.user.trialEndsAt) {
      res.status(403).json({
        success: false,
        message: 'Trial period has expired. Please subscribe to continue.',
      });
      return;
    }
  }

  next();
};

/**
 * Admin-only middleware
 */
export const requireAdmin = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): void => {
  if (!req.user) {
    res.status(401).json({
      success: false,
      message: 'Authentication required',
    });
    return;
  }

  // For now, test users are considered admins
  if (!req.user.isTestUser) {
    res.status(403).json({
      success: false,
      message: 'Admin access required',
    });
    return;
  }

  next();
};
