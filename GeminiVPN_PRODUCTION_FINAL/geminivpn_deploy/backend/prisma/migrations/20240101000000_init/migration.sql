-- =============================================================================
-- GeminiVPN — Initial Migration
-- Generated from prisma/schema.prisma
-- =============================================================================

-- CreateEnum
CREATE TYPE "SubscriptionStatus" AS ENUM ('TRIAL', 'ACTIVE', 'EXPIRED', 'CANCELLED', 'SUSPENDED');

-- CreateEnum
CREATE TYPE "PlanType" AS ENUM ('MONTHLY', 'YEARLY', 'TWO_YEAR');

-- CreateEnum
CREATE TYPE "PaymentStatus" AS ENUM ('PENDING', 'COMPLETED', 'FAILED', 'REFUNDED');

-- CreateTable
CREATE TABLE "User" (
    "id"                   TEXT NOT NULL,
    "email"                TEXT NOT NULL,
    "password"             TEXT NOT NULL,
    "name"                 TEXT,
    "subscriptionStatus"   "SubscriptionStatus" NOT NULL DEFAULT 'TRIAL',
    "trialEndsAt"          TIMESTAMP(3),
    "subscriptionEndsAt"   TIMESTAMP(3),
    "gracePeriodEndsAt"    TIMESTAMP(3),
    "stripeCustomerId"     TEXT,
    "stripeSubscriptionId" TEXT,
    "isActive"             BOOLEAN NOT NULL DEFAULT true,
    "isTestUser"           BOOLEAN NOT NULL DEFAULT false,
    "emailVerified"        BOOLEAN NOT NULL DEFAULT false,
    "lastLoginAt"          TIMESTAMP(3),
    "createdAt"            TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt"            TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "VPNClient" (
    "id"              TEXT NOT NULL,
    "userId"          TEXT NOT NULL,
    "name"            TEXT NOT NULL DEFAULT 'My Device',
    "publicKey"       TEXT NOT NULL,
    "privateKey"      TEXT NOT NULL,
    "assignedIp"      TEXT NOT NULL,
    "serverId"        TEXT,
    "isConnected"     BOOLEAN NOT NULL DEFAULT false,
    "lastConnectedAt" TIMESTAMP(3),
    "dataTransferred" BIGINT NOT NULL DEFAULT 0,
    "configFile"      TEXT,
    "qrCodeData"      TEXT,
    "createdAt"       TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt"       TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VPNClient_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "VPNServer" (
    "id"             TEXT NOT NULL,
    "name"           TEXT NOT NULL,
    "country"        TEXT NOT NULL,
    "city"           TEXT NOT NULL,
    "region"         TEXT,
    "hostname"       TEXT NOT NULL,
    "port"           INTEGER NOT NULL DEFAULT 51820,
    "publicKey"      TEXT NOT NULL,
    "loadPercentage" INTEGER NOT NULL DEFAULT 0,
    "latencyMs"      INTEGER NOT NULL DEFAULT 0,
    "maxClients"     INTEGER NOT NULL DEFAULT 200,
    "dnsServers"     TEXT NOT NULL DEFAULT '1.1.1.1,1.0.0.1',
    "isActive"       BOOLEAN NOT NULL DEFAULT true,
    "isMaintenance"  BOOLEAN NOT NULL DEFAULT false,
    "subnet"         TEXT NOT NULL DEFAULT '10.8.0.0/24',
    "tags"           TEXT[] DEFAULT ARRAY[]::TEXT[],
    "createdAt"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt"      TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VPNServer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Payment" (
    "id"              TEXT NOT NULL,
    "userId"          TEXT NOT NULL,
    "stripePaymentId" TEXT,
    "amount"          INTEGER NOT NULL,
    "currency"        TEXT NOT NULL DEFAULT 'usd',
    "status"          "PaymentStatus" NOT NULL DEFAULT 'PENDING',
    "planType"        "PlanType" NOT NULL,
    "createdAt"       TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Payment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Session" (
    "id"           TEXT NOT NULL,
    "userId"       TEXT NOT NULL,
    "refreshToken" TEXT NOT NULL,
    "ipAddress"    TEXT,
    "userAgent"    TEXT,
    "isValid"      BOOLEAN NOT NULL DEFAULT true,
    "revokedAt"    TIMESTAMP(3),
    "lastUsedAt"   TIMESTAMP(3),
    "expiresAt"    TIMESTAMP(3) NOT NULL,
    "createdAt"    TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Session_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConnectionLog" (
    "id"              TEXT NOT NULL,
    "userId"          TEXT NOT NULL,
    "clientId"        TEXT,
    "eventType"       TEXT NOT NULL,
    "serverId"        TEXT,
    "assignedIp"      TEXT,
    "clientIp"        TEXT,
    "duration"        INTEGER,
    "dataTransferred" BIGINT,
    "createdAt"       TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConnectionLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DemoAccount" (
    "id"              TEXT NOT NULL,
    "userId"          TEXT NOT NULL,
    "username"        TEXT NOT NULL,
    "creatorIp"       TEXT NOT NULL,
    "expiresAt"       TIMESTAMP(3) NOT NULL,
    "maxClients"      INTEGER NOT NULL DEFAULT 1,
    "bandwidthMbps"   INTEGER NOT NULL DEFAULT 10,
    "allowedServers"  TEXT NOT NULL DEFAULT 'us-ny,eu-london',
    "convertedToPaid" BOOLEAN NOT NULL DEFAULT false,
    "conversionDate"  TIMESTAMP(3),
    "warningSent"     BOOLEAN NOT NULL DEFAULT false,
    "isDeleted"       BOOLEAN NOT NULL DEFAULT false,
    "createdAt"       TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt"       TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DemoAccount_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DownloadLog" (
    "id"        TEXT NOT NULL,
    "platform"  TEXT NOT NULL,
    "version"   TEXT NOT NULL DEFAULT 'latest',
    "ipAddress" TEXT,
    "userAgent" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DownloadLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SystemConfig" (
    "id"          TEXT NOT NULL,
    "key"         TEXT NOT NULL,
    "value"       TEXT NOT NULL,
    "description" TEXT,
    "createdAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt"   TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SystemConfig_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key"                ON "User"("email");
CREATE UNIQUE INDEX "User_stripeCustomerId_key"     ON "User"("stripeCustomerId");
CREATE UNIQUE INDEX "User_stripeSubscriptionId_key" ON "User"("stripeSubscriptionId");

CREATE UNIQUE INDEX "VPNClient_publicKey_key"  ON "VPNClient"("publicKey");
CREATE UNIQUE INDEX "VPNClient_assignedIp_key" ON "VPNClient"("assignedIp");

CREATE UNIQUE INDEX "VPNServer_hostname_key"  ON "VPNServer"("hostname");
CREATE UNIQUE INDEX "VPNServer_publicKey_key" ON "VPNServer"("publicKey");

CREATE UNIQUE INDEX "Payment_stripePaymentId_key" ON "Payment"("stripePaymentId");

CREATE UNIQUE INDEX "Session_refreshToken_key" ON "Session"("refreshToken");

CREATE UNIQUE INDEX "DemoAccount_userId_key"   ON "DemoAccount"("userId");
CREATE UNIQUE INDEX "DemoAccount_username_key" ON "DemoAccount"("username");
CREATE INDEX "DemoAccount_creatorIp_idx"       ON "DemoAccount"("creatorIp");
CREATE INDEX "DemoAccount_expiresAt_idx"       ON "DemoAccount"("expiresAt");
CREATE INDEX "DemoAccount_isDeleted_idx"       ON "DemoAccount"("isDeleted");

CREATE INDEX "DownloadLog_platform_idx"  ON "DownloadLog"("platform");
CREATE INDEX "DownloadLog_createdAt_idx" ON "DownloadLog"("createdAt");

CREATE UNIQUE INDEX "SystemConfig_key_key" ON "SystemConfig"("key");

-- AddForeignKey
ALTER TABLE "VPNClient"     ADD CONSTRAINT "VPNClient_userId_fkey"     FOREIGN KEY ("userId") REFERENCES "User"("id")      ON DELETE CASCADE  ON UPDATE CASCADE;
ALTER TABLE "VPNClient"     ADD CONSTRAINT "VPNClient_serverId_fkey"   FOREIGN KEY ("serverId") REFERENCES "VPNServer"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Payment"       ADD CONSTRAINT "Payment_userId_fkey"       FOREIGN KEY ("userId") REFERENCES "User"("id")      ON DELETE CASCADE  ON UPDATE CASCADE;
ALTER TABLE "Session"       ADD CONSTRAINT "Session_userId_fkey"       FOREIGN KEY ("userId") REFERENCES "User"("id")      ON DELETE CASCADE  ON UPDATE CASCADE;
ALTER TABLE "ConnectionLog" ADD CONSTRAINT "ConnectionLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id")      ON DELETE CASCADE  ON UPDATE CASCADE;
ALTER TABLE "DemoAccount"   ADD CONSTRAINT "DemoAccount_userId_fkey"   FOREIGN KEY ("userId") REFERENCES "User"("id")      ON DELETE RESTRICT ON UPDATE CASCADE;
