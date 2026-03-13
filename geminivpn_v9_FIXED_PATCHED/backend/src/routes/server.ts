/**
 * VPN Server Routes — fixed: removed VPNServer.currentClients (not in schema)
 */
import { Router } from 'express';
import prisma from '../lib/prisma';
import { authenticate } from '../middleware/auth';
import { AuthenticatedRequest } from '../types';
import { logger } from '../utils/logger';

const router = Router();

// Get all active servers (public)
router.get('/', async (_req, res) => {
  try {
    const servers = await prisma.vPNServer.findMany({
      where:   { isActive: true, isMaintenance: false },
      select:  { id:true, name:true, country:true, city:true, region:true, hostname:true, port:true, loadPercentage:true, latencyMs:true, maxClients:true },
      orderBy: [{ loadPercentage:'asc' }, { latencyMs:'asc' }],
    });
    res.json({ success:true, data:servers });
  } catch (error) {
    logger.error('Get servers error:', error);
    res.status(500).json({ success:false, message:'Failed to get servers' });
  }
});

// Get recommended server (public)
router.get('/recommended/best', async (req, res) => {
  try {
    const { country } = req.query;
    const where: any = { isActive:true, isMaintenance:false };
    if (country) where.country = country.toString().toUpperCase();
    const server = await prisma.vPNServer.findFirst({
      where,
      orderBy: [{ loadPercentage:'asc' }, { latencyMs:'asc' }],
      select:  { id:true, name:true, country:true, city:true, hostname:true, port:true, loadPercentage:true, latencyMs:true },
    });
    if (!server) { res.status(404).json({ success:false, message:'No available servers' }); return; }
    res.json({ success:true, data:server });
  } catch (error) {
    logger.error('Get recommended server error:', error);
    res.status(500).json({ success:false, message:'Failed to get recommended server' });
  }
});

// Get server stats (admin only)
router.get('/stats/overview', authenticate, async (req: AuthenticatedRequest, res) => {
  try {
    if (!req.user?.isTestUser) { res.status(403).json({ success:false, message:'Admin access required' }); return; }
    const [total, active, maintenance, connectedClients] = await Promise.all([
      prisma.vPNServer.count(),
      prisma.vPNServer.count({ where:{ isActive:true } }),
      prisma.vPNServer.count({ where:{ isMaintenance:true } }),
      prisma.vPNClient.count({ where:{ isConnected:true } }),
    ]);
    const maxCapacity = await prisma.vPNServer.aggregate({ _sum:{ maxClients:true } });
    res.json({
      success:true,
      data: {
        totalServers: total, activeServers: active, maintenanceServers: maintenance,
        connectedClients, totalCapacity: maxCapacity._sum.maxClients || 0,
        averageLoad: maxCapacity._sum.maxClients ? Math.round((connectedClients / maxCapacity._sum.maxClients) * 100) : 0,
      },
    });
  } catch (error) {
    logger.error('Get server stats error:', error);
    res.status(500).json({ success:false, message:'Failed to get server statistics' });
  }
});

// Get server by ID (public)
router.get('/:serverId', async (req, res) => {
  try {
    const { serverId } = req.params;
    const server = await prisma.vPNServer.findUnique({
      where:  { id:serverId },
      select: { id:true, name:true, country:true, city:true, region:true, hostname:true, port:true, publicKey:true, loadPercentage:true, latencyMs:true, maxClients:true, dnsServers:true },
    });
    if (!server) { res.status(404).json({ success:false, message:'Server not found' }); return; }
    res.json({ success:true, data:server });
  } catch (error) {
    logger.error('Get server error:', error);
    res.status(500).json({ success:false, message:'Failed to get server' });
  }
});

export default router;
