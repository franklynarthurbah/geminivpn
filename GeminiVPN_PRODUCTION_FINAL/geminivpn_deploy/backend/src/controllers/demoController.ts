/**
 * demoController.ts — GeminiVPN Demo Account System
 *
 * BUGS FIXED:
 *   1. Circular import crash: removed `import { vpnEngine } from '../server'`
 *      (server → demoRoutes → demoController → server = Node.js crash on boot)
 *      vpnEngine is now obtained lazily via require() only during cleanup.
 *   2. Schema field mismatch: `convertedAt` → `conversionDate` (matches schema)
 *   3. Schema field mismatch: `deletedAt` doesn't exist — removed, use `isDeleted`
 *   4. Added graceful fallback when WireGuard is disabled
 */

import { Request, Response } from 'express';
import { PrismaClient, SubscriptionStatus } from '@prisma/client';
import crypto from 'crypto';
import { logger } from '../utils/logger';

const prisma = new PrismaClient();

const DEMO_DURATION_MINUTES = parseInt(process.env.DEMO_DURATION_MINUTES || '60');
const DEMO_RATE_LIMIT_HOURS = 24;
const DEMO_ALLOWED_SERVERS  = ['us-ny', 'eu-london'];
const DEMO_BANDWIDTH_MBPS   = 10;
const DEMO_MAX_CLIENTS      = 1;

/** Lazy vpnEngine accessor — avoids circular import that crashes Node on startup */
function getVpnEngine() {
  try {
    return require('../server').vpnEngine ?? null;
  } catch {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/demo/generate
// ─────────────────────────────────────────────────────────────────────────────
export const generateDemoAccount = async (req: Request, res: Response): Promise<void> => {
  try {
    const clientIp = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
                  || req.socket.remoteAddress || 'unknown';

    const since = new Date(Date.now() - DEMO_RATE_LIMIT_HOURS * 3600 * 1000);
    const recentDemo = await prisma.demoAccount.findFirst({
      where: { creatorIp: clientIp, createdAt: { gte: since }, isDeleted: false },
    });

    if (recentDemo) {
      const nextAllowed = new Date(recentDemo.createdAt.getTime() + DEMO_RATE_LIMIT_HOURS * 3600 * 1000);
      res.status(429).json({
        success: false, error: 'DEMO_RATE_LIMITED',
        message: `Demo accounts are limited to 1 per ${DEMO_RATE_LIMIT_HOURS} hours per IP.`,
        data: { nextAllowedAt: nextAllowed },
      });
      return;
    }

    const randomSuffix = crypto.randomBytes(4).toString('hex');
    const username     = `demo_${randomSuffix}`;
    const email        = `${username}@geminivpn.temp`;
    const password     = crypto.randomBytes(10).toString('base64url');
    const expiresAt    = new Date(Date.now() + DEMO_DURATION_MINUTES * 60 * 1000);

    const bcrypt = await import('bcryptjs');
    const hashedPassword = await bcrypt.hash(password, 10);

    const user = await prisma.user.create({
      data: {
        email, password: hashedPassword, name: username,
        subscriptionStatus: SubscriptionStatus.TRIAL,
        trialEndsAt: expiresAt, isTestUser: true, emailVerified: true,
      },
    });

    await prisma.demoAccount.create({
      data: {
        userId: user.id, username, creatorIp: clientIp, expiresAt,
        maxClients: DEMO_MAX_CLIENTS, bandwidthMbps: DEMO_BANDWIDTH_MBPS,
        allowedServers: DEMO_ALLOWED_SERVERS.join(','),
      },
    });

    logger.info(`Demo account created: ${username} (IP: ${clientIp})`);
    res.status(201).json({
      success: true, message: 'Demo account created',
      data: { username, email, password, expiresAt, durationMinutes: DEMO_DURATION_MINUTES,
              maxDevices: DEMO_MAX_CLIENTS, allowedServers: DEMO_ALLOWED_SERVERS, bandwidthMbps: DEMO_BANDWIDTH_MBPS },
    });
  } catch (error) {
    logger.error('Generate demo account error:', error);
    res.status(500).json({ success: false, message: 'Failed to create demo account' });
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/demo/cleanup
// ─────────────────────────────────────────────────────────────────────────────
export const cleanupExpiredDemoAccounts = async (_req: Request, res: Response): Promise<void> => {
  try {
    const deleted = await runDemoCleanup();
    res.json({ success: true, data: { deletedCount: deleted } });
  } catch (error) {
    logger.error('Demo cleanup error:', error);
    res.status(500).json({ success: false, message: 'Cleanup failed' });
  }
};

export async function runDemoCleanup(): Promise<number> {
  const vpnEngine = getVpnEngine();
  const expiredDemos = await prisma.demoAccount.findMany({
    where: { expiresAt: { lte: new Date() }, isDeleted: false },
    include: { user: { include: { vpnClients: true } } },
  });

  let deletedCount = 0;
  for (const demo of expiredDemos) {
    try {
      for (const client of demo.user.vpnClients) {
        try {
          if (client.isConnected && vpnEngine) await vpnEngine.disconnectClient(client.id);
          if (vpnEngine) await vpnEngine.removeClient(client.id);
          else await prisma.vPNClient.update({ where: { id: client.id }, data: { isConnected: false } });
        } catch (e) { logger.warn(`Client cleanup ${client.id}: ${e}`); }
      }
      // FIX: `deletedAt` field does not exist — use `isDeleted` flag only
      await prisma.demoAccount.update({ where: { id: demo.id }, data: { isDeleted: true } });
      await prisma.user.delete({ where: { id: demo.userId } });
      deletedCount++;
      logger.info(`Deleted expired demo: ${demo.username}`);
    } catch (err) { logger.error(`Failed to delete demo ${demo.username}:`, err); }
  }
  return deletedCount;
}

// ─────────────────────────────────────────────────────────────────────────────
// Conversion tracking (called from webhookController)
// ─────────────────────────────────────────────────────────────────────────────
export async function trackDemoConversion(userId: string): Promise<void> {
  try {
    const demo = await prisma.demoAccount.findFirst({ where: { userId, isDeleted: false } });
    if (demo) {
      await prisma.demoAccount.update({
        where: { id: demo.id },
        // FIX: schema field is `conversionDate`, not `convertedAt`
        data: { convertedToPaid: true, conversionDate: new Date() },
      });
    }
  } catch (err) { logger.error('Demo conversion tracking error:', err); }
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/demo/metrics
// ─────────────────────────────────────────────────────────────────────────────
export const getDemoMetrics = async (_req: Request, res: Response): Promise<void> => {
  try {
    const [total, converted, active] = await Promise.all([
      prisma.demoAccount.count(),
      prisma.demoAccount.count({ where: { convertedToPaid: true } }),
      prisma.demoAccount.count({ where: { isDeleted: false, expiresAt: { gt: new Date() } } }),
    ]);
    res.json({
      success: true,
      data: { totalCreated: total, convertedToPaid: converted, currentlyActive: active,
              conversionRate: `${total > 0 ? Math.round((converted / total) * 1000) / 10 : 0}%` },
    });
  } catch (error) {
    logger.error('Demo metrics error:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch metrics' });
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// Demo limits middleware
// ─────────────────────────────────────────────────────────────────────────────
export const enforceDemoLimits = async (req: any, res: Response, next: Function): Promise<void> => {
  if (!req.user?.isTestUser) { next(); return; }
  const demo = await prisma.demoAccount.findFirst({ where: { userId: req.user.id, isDeleted: false } });
  if (!demo) { next(); return; }

  if (new Date() > demo.expiresAt) {
    res.status(403).json({ success: false, error: 'DEMO_EXPIRED',
      message: 'Your demo account has expired. Create a subscription to continue.' });
    return;
  }
  const clientCount = await prisma.vPNClient.count({ where: { userId: req.user.id } });
  if (clientCount >= demo.maxClients) {
    res.status(403).json({ success: false, error: 'DEMO_DEVICE_LIMIT',
      message: `Demo accounts are limited to ${demo.maxClients} device(s).` });
    return;
  }
  const { serverId } = req.body;
  if (serverId) {
    const server = await prisma.vPNServer.findUnique({ where: { id: serverId } });
    const allowed = demo.allowedServers.split(',').some(s => (server?.name.toLowerCase().replace(/\s+/g, '-') || '').includes(s));
    if (!allowed) {
      res.status(403).json({ success: false, error: 'DEMO_SERVER_RESTRICTED',
        message: `Demo accounts can only connect to: ${demo.allowedServers}.`, data: { allowedServers: demo.allowedServers.split(',') } });
      return;
    }
  }
  next();
};
