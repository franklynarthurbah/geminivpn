/**
 * GeminiVPN Backend Server
 */
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import dotenv from 'dotenv';
import { PrismaClient } from '@prisma/client';

dotenv.config();

import authRoutes     from './routes/auth';
import userRoutes     from './routes/user';
import vpnRoutes      from './routes/vpn';
import paymentRoutes  from './routes/payment';
import serverRoutes   from './routes/server';
import webhookRoutes  from './routes/webhook';
import downloadRoutes from './routes/download';
import demoRoutes     from './routes/demo';

import { VPNEngine }          from './services/vpnEngine';
import { ConnectionMonitor }  from './services/connectionMonitor';
import { logger }             from './utils/logger';

const app  = express();
const PORT = process.env.PORT || 5000;
const HOST = process.env.HOST || '0.0.0.0';

export const prisma = new PrismaClient({
  log: process.env.NODE_ENV === 'development' ? ['query', 'info', 'warn', 'error'] : ['error'],
});

export const vpnEngine        = new VPNEngine();
export const connectionMonitor = new ConnectionMonitor();

// ── Security ───────────────────────────────────────────────────────────────
app.use(helmet({
  contentSecurityPolicy: false, // managed by nginx
  crossOriginEmbedderPolicy: false,
}));

// ── CORS ───────────────────────────────────────────────────────────────────
// When behind nginx reverse proxy, frontend and API share the same origin,
// so CORS is only needed for local development. We allow all origins when
// no FRONTEND_URL is set (dev mode).
const allowedOrigins = process.env.FRONTEND_URL
  ? [process.env.FRONTEND_URL, 'http://localhost:5173', 'http://localhost:3000']
  : true; // allow all in dev

app.use(cors({
  origin: allowedOrigins,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ── Rate limiting ──────────────────────────────────────────────────────────
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
  message: { success: false, message: 'Too many authentication attempts, please try again later.' },
});

// ── Body parsing ───────────────────────────────────────────────────────────
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Trust proxy (nginx sets X-Forwarded-For)
app.set('trust proxy', 1);

// ── Request logging ────────────────────────────────────────────────────────
app.use((req, _res, next) => {
  logger.info(`${req.method} ${req.path} - ${req.ip}`);
  next();
});

// ── Health check ───────────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString(), version: '1.0.0', environment: process.env.NODE_ENV });
});

// ── Routes ─────────────────────────────────────────────────────────────────
app.use('/api/v1/auth',      authLimiter, authRoutes);
app.use('/api/v1/users',     userRoutes);
app.use('/api/v1/vpn',       vpnRoutes);
app.use('/api/v1/payments',  paymentRoutes);
app.use('/api/v1/servers',   serverRoutes);
app.use('/api/v1/webhooks',  webhookRoutes);
app.use('/api/v1/downloads', downloadRoutes);
app.use('/api/v1/demo',      demoRoutes);

// WhatsApp support redirect
app.get('/support/whatsapp', (req, res) => {
  const phoneNumber = process.env.WHATSAPP_SUPPORT_NUMBER || '+905368895622';
  const message = encodeURIComponent('Hello GeminiVPN Support, I need assistance.');
  res.redirect(`https://wa.me/${phoneNumber}?text=${message}`);
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

// ── Graceful shutdown ──────────────────────────────────────────────────────
const gracefulShutdown = async (signal: string) => {
  logger.info(`Received ${signal}. Shutting down gracefully...`);
  await vpnEngine.shutdown();
  connectionMonitor.stop();
  await prisma.$disconnect();
  process.exit(0);
};
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT',  () => gracefulShutdown('SIGINT'));

// ── Start ──────────────────────────────────────────────────────────────────
const startServer = async () => {
  try {
    await prisma.$connect();
    logger.info('✅ Database connected');

    if (process.env.WIREGUARD_ENABLED === 'true') {
      await vpnEngine.initialize();
      logger.info('✅ VPN engine initialized');
    }
    if (process.env.ENABLE_SELF_HEALING === 'true') {
      connectionMonitor.start();
      logger.info('✅ Connection monitor started');
    }

    app.listen(PORT as number, HOST, () => {
      logger.info(`🚀 GeminiVPN API on http://${HOST}:${PORT}`);
    });
  } catch (error) {
    logger.error('❌ Failed to start server:', error);
    await prisma.$disconnect();
    process.exit(1);
  }
};

startServer();
export default app;
