/**
 * Download Routes — serve app installers + track download counts
 */
import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import { prisma } from '../server';
import { logger } from '../utils/logger';

const router = Router();
const DOWNLOADS_DIR = process.env.DOWNLOADS_DIR || path.join(process.cwd(), '..', 'downloads');

const PLATFORM_FILES: Record<string, { file: string; mime: string; display: string }> = {
  android:   { file: 'GeminiVPN.apk',        mime: 'application/vnd.android.package-archive', display: 'GeminiVPN.apk'       },
  windows:   { file: 'GeminiVPN-Setup.exe',   mime: 'application/octet-stream',                display: 'GeminiVPN-Setup.exe' },
  macos:     { file: 'GeminiVPN.dmg',         mime: 'application/x-apple-diskimage',           display: 'GeminiVPN.dmg'       },
  linux:     { file: 'GeminiVPN.AppImage',    mime: 'application/x-executable',               display: 'GeminiVPN.AppImage'  },
  'linux-deb':{ file: 'GeminiVPN.deb',        mime: 'application/x-deb',                      display: 'GeminiVPN.deb'       },
  ios:       { file: '', mime: '', display: 'App Store' },   // handled via redirect
  router:    { file: 'router-guide.pdf',      mime: 'application/pdf',                         display: 'Router-Setup-Guide.pdf' },
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
      message: `${meta.display} is not yet available. Check back soon.`,
      platform,
    });
    return;
  }

  res.setHeader('Content-Disposition', `attachment; filename="${meta.display}"`);
  res.setHeader('Content-Type', meta.mime);
  res.sendFile(path.resolve(filePath));
});

export default router;
