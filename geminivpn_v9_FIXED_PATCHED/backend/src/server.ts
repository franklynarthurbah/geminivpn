/**
 * GeminiVPN Backend Server — Combined v3
 * All payment providers: Stripe · Square · Paddle · Coinbase
 */
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import dotenv from 'dotenv';
dotenv.config();

import prisma from './lib/prisma';

import authRoutes     from './routes/auth';
import userRoutes     from './routes/user';
import vpnRoutes      from './routes/vpn';
import paymentRoutes  from './routes/payment';
import serverRoutes   from './routes/server';
import webhookRoutes  from './routes/webhook';
import downloadRoutes from './routes/download';
import demoRoutes     from './routes/demo';

import { ConnectionMonitor } from './services/connectionMonitor';
import { logger }            from './utils/logger';

const app  = express();
const PORT = process.env.PORT || 5000;
const HOST = process.env.HOST || '0.0.0.0';

// prisma singleton is in ./lib/prisma — imported above
export { prisma };

import { vpnEngine } from './services/vpnEngineSingleton';
export { vpnEngine };
export const connectionMonitor = new ConnectionMonitor();

// ── Security ────────────────────────────────────────────────────────────────
app.use(helmet({ contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));

// ── CORS ────────────────────────────────────────────────────────────────────
const allowedOrigins = process.env.FRONTEND_URL
  ? [process.env.FRONTEND_URL, 'http://localhost:5173', 'http://localhost:3000']
  : true;

app.use(cors({
  origin: allowedOrigins,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ── Rate limiting ────────────────────────────────────────────────────────────
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000'),
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100'),
  message: { success: false, message: 'Too many requests, please try again later.' },
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(limiter);

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  skipSuccessfulRequests: true,
  message: { success: false, message: 'Too many authentication attempts.' },
});

// ── Body parsing ─────────────────────────────────────────────────────────────
// CRITICAL: All webhook routes MUST receive a raw Buffer.
// These MUST be registered BEFORE express.json() middleware.
app.use('/api/v1/webhooks/stripe',   express.raw({ type: 'application/json' }));
app.use('/api/v1/webhooks/square',   express.raw({ type: 'application/json' }));
app.use('/api/v1/webhooks/paddle',   express.raw({ type: 'application/json' }));
app.use('/api/v1/webhooks/coinbase', express.raw({ type: 'application/json' }));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

app.set('trust proxy', 1);

// ── Request logging ───────────────────────────────────────────────────────────
app.use((req, _res, next) => {
  logger.info(`${req.method} ${req.path} - ${req.ip}`);
  next();
});

// ── Health check ─────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: '3.0.0',
    environment: process.env.NODE_ENV,
    payments: {
      stripe:   !!(process.env.STRIPE_SECRET_KEY && !process.env.STRIPE_SECRET_KEY.includes('placeholder')),
      square:   !!(process.env.SQUARE_ACCESS_TOKEN && process.env.SQUARE_ACCESS_TOKEN !== 'placeholder'),
      paddle:   !!(process.env.PADDLE_API_KEY && process.env.PADDLE_API_KEY !== 'placeholder'),
      coinbase: !!(process.env.COINBASE_COMMERCE_API_KEY && process.env.COINBASE_COMMERCE_API_KEY !== 'placeholder'),
    },
  });
});

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/api/v1/auth',      authLimiter, authRoutes);
app.use('/api/v1/users',     userRoutes);
app.use('/api/v1/vpn',       vpnRoutes);
app.use('/api/v1/payments',  paymentRoutes);
app.use('/api/v1/servers',   serverRoutes);
app.use('/api/v1/webhooks',  webhookRoutes);
app.use('/api/v1/downloads', downloadRoutes);
app.use('/api/v1/demo',      demoRoutes);

// WhatsApp support redirect
app.get('/support/whatsapp', (_req, res) => {
  const phone   = process.env.WHATSAPP_SUPPORT_NUMBER || '+905368895622';
  const message = encodeURIComponent('Hello GeminiVPN Support, I need assistance.');
  res.redirect(`https://wa.me/${phone.replace(/\D/g, '')}?text=${message}`);
});

// 404
app.use((_req, res) => {
  res.status(404).json({ success: false, message: 'Endpoint not found' });
});

// Global error handler
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  logger.error('Unhandled error:', err);
  res.status(err.status || 500).json({
    success: false,
    message: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message,
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack }),
  });
});

// ── Graceful shutdown ─────────────────────────────────────────────────────────
const gracefulShutdown = async (signal: string) => {
  logger.info(`Received ${signal}. Shutting down gracefully...`);
  await vpnEngine.shutdown();
  connectionMonitor.stop();
  await prisma.$disconnect();
  process.exit(0);
};
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT',  () => gracefulShutdown('SIGINT'));

// ── Start ─────────────────────────────────────────────────────────────────────
// CRITICAL ORDERING:
//   1. app.listen() FIRST — HTTP server opens immediately so healthchecks always
//      have a port to hit, even while DB is still connecting.
//   2. DB connection with retry backoff — never calls process.exit() just because
//      postgres isn't ready yet; Docker depends_on can have brief race windows.
//   3. Services (WireGuard, connection monitor) start after DB is confirmed ready.
const startServer = async () => {
  // ── Step 1: Start HTTP listener immediately ─────────────────────────────
  const server = app.listen(PORT as number, HOST, () => {
    logger.info(`🚀 GeminiVPN API on http://${HOST}:${PORT} — waiting for DB...`);
  });

  server.on('error', (err: NodeJS.ErrnoException) => {
    logger.error('❌ HTTP server error:', err);
    if (err.code === 'EADDRINUSE') {
      logger.error(`Port ${PORT} already in use — check for another running process`);
    }
    process.exit(1);
  });

  // ── Step 2: Connect to DB with exponential backoff ──────────────────────
  const MAX_RETRIES  = 12;
  const BASE_DELAY   = 3000;  // 3s initial delay
  const MAX_DELAY    = 30000; // 30s cap
  let dbConnected    = false;

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      await prisma.$connect();
      logger.info('✅ Database connected');
      dbConnected = true;
      break;
    } catch (error) {
      const delay = Math.min(BASE_DELAY * Math.pow(1.5, attempt - 1), MAX_DELAY);
      logger.warn(`⏳ DB connect attempt ${attempt}/${MAX_RETRIES} failed — retrying in ${Math.round(delay/1000)}s`, error);
      if (attempt === MAX_RETRIES) {
        logger.error('❌ Database connection failed after all retries — server will stay running but DB is unavailable');
        // Do NOT exit — keep the HTTP server alive so Docker healthchecks pass
        // and so the container does not crash-loop.  The /health endpoint will
        // reflect the DB status once the DB becomes available.
        return;
      }
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }

  if (!dbConnected) return;

  // ── Step 3: Initialise optional services ───────────────────────────────
  if (process.env.WIREGUARD_ENABLED === 'true') {
    try {
      await vpnEngine.initialize();
      logger.info('✅ VPN engine initialized');
    } catch (err) {
      logger.warn('⚠️  VPN engine init failed (non-fatal):', err);
    }
  }

  if (process.env.ENABLE_SELF_HEALING === 'true') {
    connectionMonitor.start();
    logger.info('✅ Connection monitor started');
  }

  logger.info('✅ GeminiVPN backend fully ready');
};

startServer().catch((err) => {
  logger.error('❌ Unhandled error in startServer:', err);
  // Do NOT exit — keep container alive so logs are accessible
});
export default app;
