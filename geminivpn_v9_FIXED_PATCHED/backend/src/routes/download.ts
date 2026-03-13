/**
 * Download Routes — serve app installers + track download counts
 * FIX: removed `import { prisma } from '../server'` (circular dependency)
 *      server.ts imports this file → this file imported server.ts = crash.
 *      Now uses its own PrismaClient instance.
 */
import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import prisma from '../lib/prisma';
import { logger } from '../utils/logger';

const router = Router();
const DOWNLOADS_DIR = process.env.DOWNLOADS_DIR || path.join(process.cwd(), '..', 'downloads');

const PLATFORM_FILES: Record<string, { file: string; mime: string; display: string }> = {
  // Native installers — available now
  linux:      { file: 'GeminiVPN-linux-install.sh', mime: 'application/x-sh',        display: 'GeminiVPN-linux-install.sh' },
  windows:    { file: 'GeminiVPN-Setup.ps1',        mime: 'application/octet-stream', display: 'GeminiVPN-Setup.ps1'       },
  router:     { file: 'router-guide.pdf',            mime: 'application/pdf',          display: 'GeminiVPN-Router-Guide.pdf'},
  // Coming soon — APK/DMG builds in progress
  android:    { file: 'GeminiVPN.apk',              mime: 'application/vnd.android.package-archive', display: 'GeminiVPN.apk'  },
  macos:      { file: 'GeminiVPN.dmg',              mime: 'application/x-apple-diskimage',           display: 'GeminiVPN.dmg'  },
  'linux-deb':{ file: 'GeminiVPN.deb',              mime: 'application/x-deb',                       display: 'GeminiVPN.deb'  },
  ios:        { file: '', mime: '', display: 'App Store' },   // handled via redirect
};

const APP_STORE_URL = process.env.IOS_APP_STORE_URL || 'https://apps.apple.com/app/geminivpn';

/** GET /api/v1/downloads/stats — public counters */
router.get('/stats', async (_req: Request, res: Response) => {
  try {
    const rows = await prisma.downloadLog.groupBy({ by: ['platform'], _count: { id: true } });
    const stats: Record<string, number> = {};
    rows.forEach((r) => { stats[r.platform] = r._count.id; });
    res.json({ success: true, data: stats });
  } catch {
    res.json({ success: true, data: {} });
  }
});

/** GET /api/v1/downloads/:platform */
router.get('/:platform', async (req: Request, res: Response) => {
  const platform = req.params.platform.toLowerCase();

  // Log download attempt (non-fatal)
  try {
    await prisma.downloadLog.create({
      data: { platform, ipAddress: req.ip, userAgent: req.headers['user-agent'] || null },
    });
  } catch { /* non-fatal */ }

  // iOS → App Store redirect (must be before meta check)
  if (platform === 'ios') {
    res.redirect(302, APP_STORE_URL);
    return;
  }

  const meta = PLATFORM_FILES[platform];
  if (!meta) {
    res.status(404).json({ success: false, message: 'Unknown platform', availablePlatforms: Object.keys(PLATFORM_FILES) });
    return;
  }

  const filePath = path.join(DOWNLOADS_DIR, meta.file);
  if (!fs.existsSync(filePath)) {
    logger.warn(`Download file missing: ${filePath}`);
    res.status(503).json({
      success: false,
      message: `${meta.display} is coming soon. For Android, download WireGuard from the Play Store and import your config from your GeminiVPN dashboard. Visit https://geminivpn.zapto.org for setup guides.`,
      platform,
      alternativeUrl: platform === 'android' ? 'https://play.google.com/store/apps/details?id=com.wireguard.android' : null,
    });
    return;
  }

  res.setHeader('Content-Disposition', `attachment; filename="${meta.display}"`);
  res.setHeader('Content-Type', meta.mime);
  res.sendFile(path.resolve(filePath));
});

export default router;
