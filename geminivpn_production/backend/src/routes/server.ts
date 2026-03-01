/**
 * VPN Server Routes
 */

import { Router } from 'express';
import { PrismaClient } from '@prisma/client';
import { authenticate } from '../middleware/auth';
import { logger } from '../utils/logger';

const router = Router();
const prisma = new PrismaClient();

// Get all available servers (public)
router.get('/', async (req, res) => {
  try {
    const servers = await prisma.vPNServer.findMany({
      where: {
        isActive: true,
        isMaintenance: false,
      },
      select: {
        id: true,
        name: true,
        country: true,
        city: true,
        region: true,
        hostname: true,
        port: true,
        loadPercentage: true,
        latencyMs: true,
        maxClients: true,
        currentClients: true,
      },
      orderBy: [{ loadPercentage: 'asc' }, { latencyMs: 'asc' }],
    });

    res.json({
      success: true,
      data: servers,
    });
  } catch (error) {
    logger.error('Get servers error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get servers',
    });
  }
});

// Get server by ID (public)
router.get('/:serverId', async (req, res) => {
  try {
    const { serverId } = req.params;

    const server = await prisma.vPNServer.findUnique({
      where: { id: serverId },
      select: {
        id: true,
        name: true,
        country: true,
        city: true,
        region: true,
        hostname: true,
        port: true,
        publicKey: true,
        loadPercentage: true,
        latencyMs: true,
        maxClients: true,
        currentClients: true,
        dnsServers: true,
      },
    });

    if (!server) {
      res.status(404).json({
        success: false,
        message: 'Server not found',
      });
      return;
    }

    res.json({
      success: true,
      data: server,
    });
  } catch (error) {
    logger.error('Get server error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get server',
    });
  }
});

// Get recommended server (public)
router.get('/recommended/best', async (req, res) => {
  try {
    const { country } = req.query;

    const where: any = {
      isActive: true,
      isMaintenance: false,
    };

    if (country) {
      where.country = country.toString().toUpperCase();
    }

    const server = await prisma.vPNServer.findFirst({
      where,
      orderBy: [{ loadPercentage: 'asc' }, { latencyMs: 'asc' }],
      select: {
        id: true,
        name: true,
        country: true,
        city: true,
        hostname: true,
        port: true,
        loadPercentage: true,
        latencyMs: true,
      },
    });

    if (!server) {
      res.status(404).json({
        success: false,
        message: 'No available servers',
      });
      return;
    }

    res.json({
      success: true,
      data: server,
    });
  } catch (error) {
    logger.error('Get recommended server error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get recommended server',
    });
  }
});

// Get server statistics (admin only)
router.get('/stats/overview', authenticate, async (req, res) => {
  try {
    // Verify admin access (test users are admins)
    if (!req.user?.isTestUser) {
      res.status(403).json({
        success: false,
        message: 'Admin access required',
      });
      return;
    }

    const stats = await prisma.vPNServer.aggregate({
      _count: { id: true },
      _sum: { currentClients: true, maxClients: true },
    });

    const activeServers = await prisma.vPNServer.count({
      where: { isActive: true },
    });

    const maintenanceServers = await prisma.vPNServer.count({
      where: { isMaintenance: true },
    });

    res.json({
      success: true,
      data: {
        totalServers: stats._count.id,
        activeServers,
        maintenanceServers,
        totalClients: stats._sum.currentClients || 0,
        totalCapacity: stats._sum.maxClients || 0,
        averageLoad: stats._sum.maxClients 
          ? Math.round(((stats._sum.currentClients || 0) / stats._sum.maxClients) * 100)
          : 0,
      },
    });
  } catch (error) {
    logger.error('Get server stats error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get server statistics',
    });
  }
});

export default router;
