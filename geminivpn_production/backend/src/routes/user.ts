/**
 * User Routes
 */

import { Router } from 'express';
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';
import { authenticate } from '../middleware/auth';
import { updateProfileValidation, changePasswordValidation } from '../middleware/validation';
import { logger } from '../utils/logger';

const router = Router();
const prisma = new PrismaClient();

const BCRYPT_ROUNDS = parseInt(process.env.BCRYPT_ROUNDS || '12');

// Get user profile
router.get('/profile', authenticate, async (req, res) => {
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
        id: true,
        email: true,
        name: true,
        subscriptionStatus: true,
        trialEndsAt: true,
        subscriptionEndsAt: true,
        isTestUser: true,
        createdAt: true,
        lastLoginAt: true,
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
      data: user,
    });
  } catch (error) {
    logger.error('Get profile error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get profile',
    });
  }
});

// Update user profile
router.put('/profile', authenticate, updateProfileValidation, async (req, res) => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const { name } = req.body;

    const updatedUser = await prisma.user.update({
      where: { id: req.user.id },
      data: { name },
      select: {
        id: true,
        email: true,
        name: true,
        subscriptionStatus: true,
        trialEndsAt: true,
        subscriptionEndsAt: true,
      },
    });

    res.json({
      success: true,
      message: 'Profile updated successfully',
      data: updatedUser,
    });
  } catch (error) {
    logger.error('Update profile error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update profile',
    });
  }
});

// Change password
router.put('/password', authenticate, changePasswordValidation, async (req, res) => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const { currentPassword, newPassword } = req.body;

    // Get user with password
    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
    });

    if (!user) {
      res.status(404).json({
        success: false,
        message: 'User not found',
      });
      return;
    }

    // Verify current password
    const isValid = await bcrypt.compare(currentPassword, user.password);
    if (!isValid) {
      res.status(400).json({
        success: false,
        message: 'Current password is incorrect',
      });
      return;
    }

    // Hash new password
    const hashedPassword = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);

    // Update password
    await prisma.user.update({
      where: { id: req.user.id },
      data: { password: hashedPassword },
    });

    res.json({
      success: true,
      message: 'Password changed successfully',
    });
  } catch (error) {
    logger.error('Change password error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to change password',
    });
  }
});

// Get user statistics
router.get('/stats', authenticate, async (req, res) => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    // Get connection stats
    const connectionLogs = await prisma.connectionLog.findMany({
      where: { userId: req.user.id },
    });

    const totalConnections = connectionLogs.filter(
      log => log.eventType === 'CONNECT'
    ).length;

    const totalDataTransferred = connectionLogs.reduce(
      (sum, log) => sum + (Number(log.dataTransferred) || 0),
      0
    );

    // Get favorite server
    const serverConnections = connectionLogs
      .filter(log => log.serverId)
      .reduce((acc, log) => {
        acc[log.serverId!] = (acc[log.serverId!] || 0) + 1;
        return acc;
      }, {} as Record<string, number>);

    const favoriteServerId = Object.entries(serverConnections)
      .sort((a, b) => b[1] - a[1])[0]?.[0];

    let favoriteServer = null;
    if (favoriteServerId) {
      favoriteServer = await prisma.vPNServer.findUnique({
        where: { id: favoriteServerId },
        select: { name: true, country: true, city: true },
      });
    }

    // Get VPN clients count
    const clientsCount = await prisma.vPNClient.count({
      where: { userId: req.user.id },
    });

    res.json({
      success: true,
      data: {
        totalConnections,
        totalDataTransferred,
        favoriteServer,
        clientsCount,
        accountAge: req.user.createdAt 
          ? Math.floor((Date.now() - new Date(req.user.createdAt).getTime()) / (1000 * 60 * 60 * 24))
          : 0,
      },
    });
  } catch (error) {
    logger.error('Get user stats error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get user statistics',
    });
  }
});

// Delete account
router.delete('/account', authenticate, async (req, res) => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    // In production, you might want to:
    // 1. Cancel any active subscriptions
    // 2. Disconnect all VPN clients
    // 3. Soft delete or anonymize data
    // 4. Send confirmation email

    // For now, we'll just mark as inactive
    await prisma.user.update({
      where: { id: req.user.id },
      data: { isActive: false },
    });

    logger.info(`User account deactivated: ${req.user.email}`);

    res.json({
      success: true,
      message: 'Account deactivated successfully',
    });
  } catch (error) {
    logger.error('Delete account error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to deactivate account',
    });
  }
});

export default router;
