/**
 * demoController.ts
 * GeminiVPN – Demo Account System
 *
 * ⚠️  IMPORTANT: This file in backend_additions/ is a DRAFT reference copy.
 *     The CANONICAL, FIXED version is: backend/src/controllers/demoController.ts
 *     The circular import bug below (`import { vpnEngine } from '../server'`)
 *     is FIXED in the canonical version using a lazy require() accessor.
 *     DO NOT use this file directly — use backend/src/controllers/demoController.ts
 *
 * BUG IN THIS DRAFT FILE:
 *   `import { vpnEngine } from '../server'` creates a circular dependency:
 *    server.ts → demoRoutes.ts → demoController.ts → server.ts (crash on boot)
 *   Fixed version uses: const getVpnEngine = () => require('../server').vpnEngine;
 */

import { Request, Response }    from 'express';
import { PrismaClient, SubscriptionStatus } from '@prisma/client';
import crypto                   from 'crypto';
import { logger }               from '../utils/logger';
// FIXED: was `import { vpnEngine } from '../server'` — circular dependency crash
// Using lazy require to break the import cycle:
function getVpnEngine() {
  try { return require('../server').vpnEngine ?? null; } catch { return null; }
}

const prisma = new PrismaClient();

const DEMO_DURATION_MINUTES = parseInt(process.env.DEMO_DURATION_MINUTES || '60');
const DEMO_RATE_LIMIT_HOURS = 24;   // 1 demo per IP per 24 hours
const DEMO_ALLOWED_SERVERS  = ['us-ny', 'eu-london'];  // server name slugs
const DEMO_BANDWIDTH_MBPS   = 10;   // throttle cap for demo users
const DEMO_MAX_CLIENTS      = 1;    // single device

// ─── Generate Demo Account ────────────────────────────────────────────────────

/**
 * POST /api/v1/demo/generate
 * Creates a new 60-minute demo account.
 * Rate-limited to 1 per IP per 24 hours.
 */
export const generateDemoAccount = async (req: Request, res: Response): Promise<void> => {
  try {
    const clientIp = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
                  || req.socket.remoteAddress
                  || 'unknown';

    // ── Rate limit check ────────────────────────────────────────────────────
    const since = new Date(Date.now() - DEMO_RATE_LIMIT_HOURS * 3600 * 1000);
    const recentDemo = await prisma.demoAccount.findFirst({
      where: {
        creatorIp: clientIp,
        createdAt: { gte: since },
      },
    });

    if (recentDemo) {
      const nextAllowed = new Date(recentDemo.createdAt.getTime() + DEMO_RATE_LIMIT_HOURS * 3600 * 1000);
      res.status(429).json({
        success: false,
        error:   'DEMO_RATE_LIMITED',
        message: `Demo accounts are limited to 1 per ${DEMO_RATE_LIMIT_HOURS} hours per IP.`,
        data: { nextAllowedAt: nextAllowed },
      });
      return;
    }

    // ── Generate credentials ────────────────────────────────────────────────
    const randomSuffix = crypto.randomBytes(4).toString('hex');
    const username     = `demo_${randomSuffix}`;
    const email        = `${username}@geminivpn.temp`;
    const password     = crypto.randomBytes(10).toString('base64url');  // 14-char URL-safe

    const expiresAt    = new Date(Date.now() + DEMO_DURATION_MINUTES * 60 * 1000);

    // ── Create User ─────────────────────────────────────────────────────────
    const bcrypt = await import('bcryptjs');
    const hashedPassword = await bcrypt.hash(password, 10);

    const user = await prisma.user.create({
      data: {
        email,
        password:           hashedPassword,
        name:               username,
        subscriptionStatus: SubscriptionStatus.TRIAL,
        trialEndsAt:        expiresAt,
        isTestUser:         true,
      },
    });

    // ── Record demo metadata ────────────────────────────────────────────────
    await prisma.demoAccount.create({
      data: {
        userId:       user.id,
        username,
        creatorIp:    clientIp,
        expiresAt,
        maxClients:   DEMO_MAX_CLIENTS,
        bandwidthMbps: DEMO_BANDWIDTH_MBPS,
        allowedServers: DEMO_ALLOWED_SERVERS.join(','),
      },
    });

    logger.info(`Demo account created: ${username} (IP: ${clientIp})`);

    res.status(201).json({
      success: true,
      message: 'Demo account created',
      data: {
        username,
        email,
        password,
        expiresAt,
        durationMinutes: DEMO_DURATION_MINUTES,
        maxDevices:      DEMO_MAX_CLIENTS,
        allowedServers:  DEMO_ALLOWED_SERVERS,
        bandwidthMbps:   DEMO_BANDWIDTH_MBPS,
      },
    });

  } catch (error) {
    logger.error('Generate demo account error:', error);
    res.status(500).json({ success: false, message: 'Failed to create demo account' });
  }
};

// ─── Cleanup expired demos ────────────────────────────────────────────────────

/**
 * POST /api/v1/demo/cleanup   (admin only)
 * Deletes all expired demo accounts and their VPN clients.
 * Should also be called by a cron job every 5 minutes.
 */
export const cleanupExpiredDemoAccounts = async (req: Request, res: Response): Promise<void> => {
  try {
    const deleted = await runDemoCleanup();
    res.json({ success: true, data: { deletedCount: deleted } });
  } catch (error) {
    logger.error('Demo cleanup error:', error);
    res.status(500).json({ success: false, message: 'Cleanup failed' });
  }
};

/**
 * Core cleanup logic – callable from cron job and HTTP endpoint.
 */
export async function runDemoCleanup(): Promise<number> {
  const now = new Date();

  // Find expired demo accounts
  const expiredDemos = await prisma.demoAccount.findMany({
    where: {
      expiresAt: { lte: now },
      isDeleted: false,
    },
    include: { user: { include: { vpnClients: true } } },
  });

  let deletedCount = 0;

  for (const demo of expiredDemos) {
    try {
      const engine = getVpnEngine();
      // 1. Disconnect & remove VPN clients
      for (const client of demo.user.vpnClients) {
        if (client.isConnected && engine) {
          await engine.disconnectClient(client.id);
        }
        if (engine) await engine.removeClient(client.id);
      }

      // 2. Mark demo as deleted (soft delete — deletedAt field does not exist
      //    in schema; use isDeleted boolean flag instead)
      await prisma.demoAccount.update({
        where: { id: demo.id },
        data:  { isDeleted: true },
      });

      // 3. Delete user record
      await prisma.user.delete({ where: { id: demo.userId } });

      deletedCount++;
      logger.info(`Deleted expired demo account: ${demo.username}`);

    } catch (err) {
      logger.error(`Failed to delete demo ${demo.username}:`, err);
    }
  }

  if (deletedCount > 0) {
    logger.info(`Demo cleanup complete: removed ${deletedCount} expired accounts`);
  }

  return deletedCount;
}

// ─── Demo conversion tracking ─────────────────────────────────────────────────

/**
 * Called when a demo user completes a payment (from webhookController).
 */
export async function trackDemoConversion(userId: string): Promise<void> {
  try {
    const demo = await prisma.demoAccount.findFirst({
      where: { userId, isDeleted: false },
    });

    if (demo) {
      await prisma.demoAccount.update({
        where: { id: demo.id },
        data:  {
          convertedToPaid: true,
          convertedAt:     new Date(),
        },
      });
      logger.info(`Demo conversion tracked: user ${userId}`);
    }
  } catch (err) {
    logger.error('Demo conversion tracking error:', err);
  }
}

// ─── Demo metrics ─────────────────────────────────────────────────────────────

/**
 * GET /api/v1/demo/metrics   (admin only)
 */
export const getDemoMetrics = async (req: Request, res: Response): Promise<void> => {
  try {
    const [total, converted, active] = await Promise.all([
      prisma.demoAccount.count(),
      prisma.demoAccount.count({ where: { convertedToPaid: true } }),
      prisma.demoAccount.count({ where: { isDeleted: false, expiresAt: { gt: new Date() } } }),
    ]);

    const conversionRate = total > 0 ? Math.round((converted / total) * 100 * 10) / 10 : 0;

    res.json({
      success: true,
      data: {
        totalCreated:    total,
        convertedToPaid: converted,
        currentlyActive: active,
        conversionRate:  `${conversionRate}%`,
      },
    });
  } catch (error) {
    logger.error('Demo metrics error:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch metrics' });
  }
};

// ─── Validate demo access ─────────────────────────────────────────────────────

/**
 * Middleware to enforce demo-account restrictions.
 * Use on VPN client creation routes.
 */
export const enforceDemoLimits = async (req: any, res: Response, next: Function): Promise<void> => {
  if (!req.user?.isTestUser) { next(); return; }

  const demo = await prisma.demoAccount.findFirst({
    where: { userId: req.user.id, isDeleted: false },
  });

  if (!demo) { next(); return; }

  // Check expiration
  if (new Date() > demo.expiresAt) {
    res.status(403).json({
      success: false,
      error:   'DEMO_EXPIRED',
      message: 'Your demo account has expired. Please create a subscription to continue.',
    });
    return;
  }

  // Check device limit
  const clientCount = await prisma.vPNClient.count({ where: { userId: req.user.id } });
  if (clientCount >= demo.maxClients) {
    res.status(403).json({
      success: false,
      error:   'DEMO_DEVICE_LIMIT',
      message: `Demo accounts are limited to ${demo.maxClients} device(s).`,
    });
    return;
  }

  // Check server restriction (inject into request for downstream validation)
  const { serverId } = req.body;
  if (serverId) {
    const server = await prisma.vPNServer.findUnique({ where: { id: serverId } });
    const allowedSlugs = demo.allowedServers.split(',');
    const serverSlug   = server?.name.toLowerCase().replace(/\s+/g, '-') || '';
    const allowed = allowedSlugs.some(slug => serverSlug.includes(slug));

    if (!allowed) {
      res.status(403).json({
        success: false,
        error:   'DEMO_SERVER_RESTRICTED',
        message: `Demo accounts can only connect to: ${allowedSlugs.join(', ')}.`,
        data:    { allowedServers: allowedSlugs },
      });
      return;
    }
  }

  next();
};
