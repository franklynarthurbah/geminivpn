/**
 * demoCleanup.ts
 * GeminiVPN – Demo Account Cleanup Job
 *
 * Runs every 5 minutes to:
 *   1. Delete expired demo accounts and their WireGuard peers
 *   2. Send "expiring soon" notifications (1-minute warning)
 *
 * FILE: backend/src/jobs/demoCleanup.ts
 */

import cron   from 'node-cron';
import { PrismaClient } from '@prisma/client';
import { runDemoCleanup } from '../controllers/demoController';
import { logger } from '../utils/logger';

const prisma = new PrismaClient();

export function startDemoCleanupJob(): void {
  // Run every 5 minutes
  cron.schedule('*/5 * * * *', async () => {
    try {
      await sendExpiryWarnings();
      const count = await runDemoCleanup();
      if (count > 0) logger.info(`[DemoCleanup] Removed ${count} expired demo accounts`);
    } catch (err) {
      logger.error('[DemoCleanup] Job error:', err);
    }
  });

  logger.info('[DemoCleanup] Cleanup cron job started (every 5 minutes)');
}

/**
 * Send in-app notification to demo users with < 1 minute remaining.
 */
async function sendExpiryWarnings(): Promise<void> {
  const oneMinuteFromNow = new Date(Date.now() + 60 * 1000);
  const now              = new Date();

  const aboutToExpire = await prisma.demoAccount.findMany({
    where: {
      isDeleted:    false,
      expiresAt:    { lte: oneMinuteFromNow, gt: now },
      warningSent:  false,
    },
    include: { user: { include: { vpnClients: true } } },
  });

  for (const demo of aboutToExpire) {
    logger.info(`[DemoCleanup] Warning: demo ${demo.username} expires in < 1 minute`);

    // Mark warning sent
    await prisma.demoAccount.update({
      where: { id: demo.id },
      data:  { warningSent: true },
    });

    // In production: send push notification / WebSocket event here
    // e.g.: wsServer.sendToUser(demo.userId, 'demo-expiring', { secondsLeft: ... })
  }
}
