// ══════════════════════════════════════════════════════════════════════════════
// FILE: backend/src/routes/demo.ts
// ADD TO server.ts: import demoRoutes; app.use('/api/v1/demo', demoRoutes);
// ══════════════════════════════════════════════════════════════════════════════

import express from 'express';
import { generateDemoAccount, cleanupExpiredDemoAccounts, getDemoMetrics } from '../controllers/demoController';
import { authenticateToken, requireAdmin } from '../middleware/auth';

const router = express.Router();

// Public – generate demo account (rate-limited at controller level)
router.post('/generate', generateDemoAccount);

// Admin only
router.post('/cleanup', authenticateToken, requireAdmin, cleanupExpiredDemoAccounts);
router.get('/metrics',  authenticateToken, requireAdmin, getDemoMetrics);

export default router;


// ══════════════════════════════════════════════════════════════════════════════
// PRISMA SCHEMA ADDITIONS
// Add these models to backend/prisma/schema.prisma
// Then run: npx prisma migrate dev --name add_demo_accounts
// ══════════════════════════════════════════════════════════════════════════════
/*

model DemoAccount {
  id               String    @id @default(uuid())
  userId           String    @unique
  username         String    @unique
  creatorIp        String
  expiresAt        DateTime
  maxClients       Int       @default(1)
  bandwidthMbps    Int       @default(10)
  allowedServers   String    @default("us-ny,eu-london")
  convertedToPaid  Boolean   @default(false)
  convertedAt      DateTime?
  isDeleted        Boolean   @default(false)
  deletedAt        DateTime?
  createdAt        DateTime  @default(now())

  user             User      @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@index([creatorIp, createdAt])
  @@index([expiresAt, isDeleted])
  @@map("demo_accounts")
}

// Also add to User model:
// demoAccount DemoAccount?
// isActive    Boolean  @default(true)         ← add if missing
// lastLoginAt DateTime?                        ← add if missing
// subscriptionEndsAt DateTime?                 ← add if missing
// gracePeriodEndsAt  DateTime?                 ← add if missing
// stripeCustomerId   String?                   ← add if missing
// stripeSubscriptionId String?                 ← add if missing

// Also add to VPNClient model:
// clientName  String  @default("My Device")   ← rename from 'name' if needed
// qrCodeData  String? @db.Text
// configFile  String? @db.Text
// server      VPNServer? @relation(fields: [serverId], references: [id])

// Also add to VPNServer model:
// maxClients     Int      @default(200)
// dnsServers     String[] @default(["1.1.1.1","1.0.0.1"])
// clients        VPNClient[]

*/


// ══════════════════════════════════════════════════════════════════════════════
// CRON JOB: backend/src/jobs/demoCleanup.ts
// Schedule with node-cron every 5 minutes.
// ADD to server.ts after vpnEngine.initialize():
//   import { startDemoCleanupJob } from './jobs/demoCleanup';
//   startDemoCleanupJob();
// ══════════════════════════════════════════════════════════════════════════════
