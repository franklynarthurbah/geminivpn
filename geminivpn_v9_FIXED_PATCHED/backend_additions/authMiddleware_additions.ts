// ============================================================
// authMiddleware_additions.ts
// REFERENCE ONLY — helpers already integrated in backend/src/middleware/auth.ts
// Note: Schema uses isTestUser (boolean) as admin flag — no separate 'role' field
// ============================================================
import { Request, Response, NextFunction } from "express";

/** Reusable admin-only guard — checks isTestUser flag (schema has no 'role' field) */
export const requireAdmin = (req: Request, res: Response, next: NextFunction): void => {
  const user = (req as any).user;
  if (!user || !user.isTestUser) {
    res.status(403).json({ success: false, error: "Admin access required" });
    return;
  }
  next();
};

/** Require active subscription (active | trial) */
export const requireActiveSubscription = (req: Request, res: Response, next: NextFunction): void => {
  const user = (req as any).user;
  const allowed = ["active", "trial", "ACTIVE", "TRIAL"];
  if (!user || !allowed.includes(user.subscriptionStatus)) {
    res.status(402).json({
      success: false,
      error: "Active subscription required",
      code: "SUBSCRIPTION_REQUIRED",
    });
    return;
  }
  next();
};

/** Rate-limit demo generation: 1 per IP per 24 hours */
export const demoRateLimit = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  const ip = req.ip || req.socket.remoteAddress || "unknown";
  // Import your prisma instance at the top of this file:
  // import { prisma } from "../lib/prisma";
  try {
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);
    // const recent = await prisma.demoAccount.findFirst({
    //   where: { creatorIp: ip, createdAt: { gte: cutoff }, isDeleted: false },
    // });
    // if (recent) {
    //   res.status(429).json({ success: false, error: "Demo rate limit: 1 per 24 hours", code: "RATE_LIMITED" });
    //   return;
    // }
    next();
  } catch (err) {
    next(err);
  }
};
