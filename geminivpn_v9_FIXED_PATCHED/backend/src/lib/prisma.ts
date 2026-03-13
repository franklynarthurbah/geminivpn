/**
 * Prisma Singleton — GeminiVPN
 *
 * WHY THIS FILE EXISTS:
 *   SQLite opens the database file as a single-writer, multi-reader store.
 *   Creating multiple PrismaClient instances causes "SQLITE_BUSY: database is locked".
 *   Every module MUST import `prisma` from this file — never `new PrismaClient()`.
 *
 * PRAGMAS: SQLite PRAGMAs return result rows even when setting values.
 *   $executeRawUnsafe() expects NO rows returned → crashes with P2010.
 *   $queryRawUnsafe()  accepts rows returned     → correct for PRAGMAs.
 */

import { PrismaClient } from '@prisma/client';
import { logger } from '../utils/logger';

declare global {
  // eslint-disable-next-line no-var
  var __prisma: PrismaClient | undefined;
}

function makePrismaClient(): PrismaClient {
  const client = new PrismaClient({
    log:
      process.env.NODE_ENV === 'development'
        ? ['query', 'info', 'warn', 'error']
        : ['error'],
  });

  // Enable WAL mode — use $queryRawUnsafe (not $executeRawUnsafe) because
  // SQLite PRAGMAs always return a result row, which $executeRaw forbids.
  client.$connect().then(async () => {
    try {
      await client.$queryRawUnsafe(`PRAGMA journal_mode = WAL;`);
      await client.$queryRawUnsafe(`PRAGMA synchronous  = NORMAL;`);
      await client.$queryRawUnsafe(`PRAGMA foreign_keys = ON;`);
      await client.$queryRawUnsafe(`PRAGMA busy_timeout = 5000;`);
      logger.info('✅ SQLite pragmas applied (WAL mode, 5s busy-timeout)');
    } catch (err) {
      logger.warn('⚠️  Could not apply SQLite pragmas (non-fatal):', err);
    }
  }).catch(() => {});

  return client;
}

const prisma: PrismaClient =
  global.__prisma ?? (global.__prisma = makePrismaClient());

export default prisma;
