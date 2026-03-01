/**
 * Authentication Controller
 * Handles user registration, login, logout, and token refresh
 */

import { Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { PrismaClient, SubscriptionStatus } from '@prisma/client';
import { AuthenticatedRequest, LoginCredentials, RegisterData, TokenPair } from '../types';
import { logger } from '../utils/logger';

const prisma = new PrismaClient();

// JWT Configuration
const JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'your-access-secret';
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'your-refresh-secret';
const JWT_ACCESS_EXPIRY = process.env.JWT_ACCESS_EXPIRY || '15m';
const JWT_REFRESH_EXPIRY = process.env.JWT_REFRESH_EXPIRY || '7d';
const BCRYPT_ROUNDS = parseInt(process.env.BCRYPT_ROUNDS || '12');

// Trial duration in days
const TRIAL_DURATION_DAYS = parseInt(process.env.TRIAL_DURATION_DAYS || '3');

/**
 * Generate JWT access token
 */
const generateAccessToken = (userId: string, email: string, subscriptionStatus: SubscriptionStatus): string => {
  return jwt.sign(
    { userId, email, subscriptionStatus },
    JWT_ACCESS_SECRET,
    { expiresIn: JWT_ACCESS_EXPIRY }
  );
};

/**
 * Generate JWT refresh token
 */
const generateRefreshToken = (userId: string): string => {
  return jwt.sign(
    { userId },
    JWT_REFRESH_SECRET,
    { expiresIn: JWT_REFRESH_EXPIRY }
  );
};

/**
 * Generate token pair (access + refresh)
 */
const generateTokenPair = (userId: string, email: string, subscriptionStatus: SubscriptionStatus): TokenPair => {
  const accessToken = generateAccessToken(userId, email, subscriptionStatus);
  const refreshToken = generateRefreshToken(userId);
  
  // Parse expiry time
  const expiresInMatch = JWT_ACCESS_EXPIRY.match(/(\d+)([mhd])/);
  let expiresIn = 900; // Default 15 minutes
  
  if (expiresInMatch) {
    const value = parseInt(expiresInMatch[1]);
    const unit = expiresInMatch[2];
    switch (unit) {
      case 'm': expiresIn = value * 60; break;
      case 'h': expiresIn = value * 3600; break;
      case 'd': expiresIn = value * 86400; break;
    }
  }

  return { accessToken, refreshToken, expiresIn };
};

/**
 * Register new user
 */
export const register = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const { email, password, name } = req.body as RegisterData;

    // Check if user already exists
    const existingUser = await prisma.user.findUnique({
      where: { email },
    });

    if (existingUser) {
      res.status(409).json({
        success: false,
        message: 'Email already registered',
      });
      return;
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(password, BCRYPT_ROUNDS);

    // Calculate trial end date
    const trialEndsAt = new Date();
    trialEndsAt.setDate(trialEndsAt.getDate() + TRIAL_DURATION_DAYS);

    // Create user
    const user = await prisma.user.create({
      data: {
        email,
        password: hashedPassword,
        name,
        subscriptionStatus: SubscriptionStatus.TRIAL,
        trialEndsAt,
      },
    });

    // Generate tokens
    const tokens = generateTokenPair(user.id, user.email, user.subscriptionStatus);

    // Create session
    const refreshTokenExpiry = new Date();
    refreshTokenExpiry.setDate(refreshTokenExpiry.getDate() + 7);

    await prisma.session.create({
      data: {
        userId: user.id,
        refreshToken: tokens.refreshToken,
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'],
        expiresAt: refreshTokenExpiry,
      },
    });

    logger.info(`New user registered: ${email}`);

    res.status(201).json({
      success: true,
      message: 'Registration successful',
      data: {
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          subscriptionStatus: user.subscriptionStatus,
          trialEndsAt: user.trialEndsAt,
        },
        tokens,
      },
    });
  } catch (error) {
    logger.error('Registration error:', error);
    res.status(500).json({
      success: false,
      message: 'Registration failed',
    });
  }
};

/**
 * Login user
 */
export const login = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const { email, password } = req.body as LoginCredentials;

    // Find user
    const user = await prisma.user.findUnique({
      where: { email },
    });

    if (!user) {
      res.status(401).json({
        success: false,
        message: 'Invalid credentials',
      });
      return;
    }

    // Check if account is active
    if (!user.isActive) {
      res.status(403).json({
        success: false,
        message: 'Account is deactivated',
      });
      return;
    }

    // Verify password
    const isPasswordValid = await bcrypt.compare(password, user.password);

    if (!isPasswordValid) {
      res.status(401).json({
        success: false,
        message: 'Invalid credentials',
      });
      return;
    }

    // Check trial expiration
    if (user.subscriptionStatus === SubscriptionStatus.TRIAL && user.trialEndsAt) {
      if (new Date() > user.trialEndsAt) {
        // Update user status to expired
        await prisma.user.update({
          where: { id: user.id },
          data: { subscriptionStatus: SubscriptionStatus.EXPIRED },
        });
        
        res.status(403).json({
          success: false,
          message: 'Trial period has expired. Please subscribe to continue.',
          data: {
            subscriptionStatus: SubscriptionStatus.EXPIRED,
          },
        });
        return;
      }
    }

    // Generate tokens
    const tokens = generateTokenPair(user.id, user.email, user.subscriptionStatus);

    // Create session
    const refreshTokenExpiry = new Date();
    refreshTokenExpiry.setDate(refreshTokenExpiry.getDate() + 7);

    await prisma.session.create({
      data: {
        userId: user.id,
        refreshToken: tokens.refreshToken,
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'],
        expiresAt: refreshTokenExpiry,
      },
    });

    // Update last login
    await prisma.user.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date() },
    });

    logger.info(`User logged in: ${email}`);

    res.json({
      success: true,
      message: 'Login successful',
      data: {
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          subscriptionStatus: user.subscriptionStatus,
          trialEndsAt: user.trialEndsAt,
          subscriptionEndsAt: user.subscriptionEndsAt,
          isTestUser: user.isTestUser,
        },
        tokens,
      },
    });
  } catch (error) {
    logger.error('Login error:', error);
    res.status(500).json({
      success: false,
      message: 'Login failed',
    });
  }
};

/**
 * Logout user
 */
export const logout = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const { refreshToken } = req.body;

    // Invalidate session
    if (refreshToken) {
      await prisma.session.updateMany({
        where: { refreshToken },
        data: {
          isValid: false,
          revokedAt: new Date(),
        },
      });
    }

    // Also invalidate current session if authenticated
    if (req.user) {
      await prisma.session.updateMany({
        where: {
          userId: req.user.id,
          isValid: true,
        },
        data: {
          isValid: false,
          revokedAt: new Date(),
        },
      });
    }

    logger.info(`User logged out: ${req.user?.email || 'unknown'}`);

    res.json({
      success: true,
      message: 'Logout successful',
    });
  } catch (error) {
    logger.error('Logout error:', error);
    res.status(500).json({
      success: false,
      message: 'Logout failed',
    });
  }
};

/**
 * Refresh access token
 */
export const refreshToken = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      res.status(400).json({
        success: false,
        message: 'Refresh token required',
      });
      return;
    }

    // Verify refresh token
    let decoded;
    try {
      decoded = jwt.verify(refreshToken, JWT_REFRESH_SECRET) as { userId: string };
    } catch (error) {
      res.status(401).json({
        success: false,
        message: 'Invalid refresh token',
      });
      return;
    }

    // Check if session exists and is valid
    const session = await prisma.session.findFirst({
      where: {
        refreshToken,
        isValid: true,
        expiresAt: { gt: new Date() },
      },
      include: { user: true },
    });

    if (!session) {
      res.status(401).json({
        success: false,
        message: 'Session expired or invalid',
      });
      return;
    }

    // Generate new token pair
    const tokens = generateTokenPair(
      session.user.id,
      session.user.email,
      session.user.subscriptionStatus
    );

    // Update session with new refresh token
    const newExpiry = new Date();
    newExpiry.setDate(newExpiry.getDate() + 7);

    await prisma.session.update({
      where: { id: session.id },
      data: {
        refreshToken: tokens.refreshToken,
        expiresAt: newExpiry,
        lastUsedAt: new Date(),
      },
    });

    res.json({
      success: true,
      message: 'Token refreshed',
      data: { tokens },
    });
  } catch (error) {
    logger.error('Token refresh error:', error);
    res.status(500).json({
      success: false,
      message: 'Token refresh failed',
    });
  }
};

/**
 * Get current user profile
 */
export const getProfile = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    // Get fresh user data with relations
    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
      include: {
        vpnClients: {
          include: {
            server: true,
          },
        },
        payments: {
          orderBy: { createdAt: 'desc' },
          take: 5,
        },
      },
    });

    if (!user) {
      res.status(404).json({
        success: false,
        message: 'User not found',
      });
      return;
    }

    res.json({
      success: true,
      data: {
        id: user.id,
        email: user.email,
        name: user.name,
        subscriptionStatus: user.subscriptionStatus,
        trialEndsAt: user.trialEndsAt,
        subscriptionEndsAt: user.subscriptionEndsAt,
        isTestUser: user.isTestUser,
        createdAt: user.createdAt,
        clients: user.vpnClients,
        recentPayments: user.payments,
      },
    });
  } catch (error) {
    logger.error('Get profile error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get profile',
    });
  }
};

/**
 * Check subscription status
 */
export const checkSubscription = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
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

    // Check if trial expired
    let status = user.subscriptionStatus;
    if (status === SubscriptionStatus.TRIAL && user.trialEndsAt && new Date() > user.trialEndsAt) {
      status = SubscriptionStatus.EXPIRED;
      await prisma.user.update({
        where: { id: req.user.id },
        data: { subscriptionStatus: SubscriptionStatus.EXPIRED },
      });
    }

    res.json({
      success: true,
      data: {
        subscriptionStatus: status,
        trialEndsAt: user.trialEndsAt,
        subscriptionEndsAt: user.subscriptionEndsAt,
        isActive: status === SubscriptionStatus.ACTIVE || status === SubscriptionStatus.TRIAL,
      },
    });
  } catch (error) {
    logger.error('Check subscription error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to check subscription',
    });
  }
};
