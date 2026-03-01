/**
 * Type Definitions for GeminiVPN Backend
 */

import { Request } from 'express';
import { User, VPNClient, VPNServer, SubscriptionStatus } from '@prisma/client';

// ============================================================================
// Authentication Types
// ============================================================================

export interface AuthenticatedRequest extends Request {
  user?: User;
  token?: string;
}

export interface JWTPayload {
  userId: string;
  email: string;
  subscriptionStatus: SubscriptionStatus;
  iat: number;
  exp: number;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export interface LoginCredentials {
  email: string;
  password: string;
}

export interface RegisterData {
  email: string;
  password: string;
  name?: string;
}

// ============================================================================
// VPN Types
// ============================================================================

export interface WireGuardConfig {
  interface: {
    PrivateKey: string;
    Address: string;
    DNS: string;
    MTU?: number;
  };
  peer: {
    PublicKey: string;
    PresharedKey?: string;
    AllowedIPs: string;
    Endpoint: string;
    PersistentKeepalive?: number;
  };
}

export interface VPNClientConfig {
  id: string;
  clientName: string;
  assignedIp: string;
  server: {
    hostname: string;
    port: number;
    publicKey: string;
  };
  configFile: string;
  qrCode: string;
}

export interface ConnectionStatus {
  isConnected: boolean;
  serverId?: string;
  serverName?: string;
  assignedIp?: string;
  connectedAt?: Date;
  dataTransferred: number;
  latency?: number;
}

export interface ServerMetrics {
  serverId: string;
  latency: number;
  loadPercentage: number;
  currentClients: number;
  isHealthy: boolean;
}

// ============================================================================
// Payment Types
// ============================================================================

export interface PaymentIntent {
  clientSecret: string;
  paymentIntentId: string;
  amount: number;
  currency: string;
}

export interface SubscriptionPlan {
  id: string;
  name: string;
  description: string;
  price: number;
  currency: string;
  interval: 'month' | 'year';
  intervalCount: number;
  features: string[];
  stripePriceId: string;
}

export interface CheckoutSession {
  sessionId: string;
  url: string;
}

// ============================================================================
// API Response Types
// ============================================================================

export interface ApiResponse<T = any> {
  success: boolean;
  message?: string;
  data?: T;
  error?: {
    code: string;
    message: string;
    details?: any;
  };
  meta?: {
    page?: number;
    limit?: number;
    total?: number;
    totalPages?: number;
  };
}

export interface PaginatedResponse<T> extends ApiResponse<T[]> {
  meta: {
    page: number;
    limit: number;
    total: number;
    totalPages: number;
  };
}

// ============================================================================
// Webhook Types
// ============================================================================

export interface StripeWebhookEvent {
  id: string;
  type: string;
  data: {
    object: any;
  };
}

// ============================================================================
// Self-Healing Types
// ============================================================================

export interface ConnectionHealth {
  clientId: string;
  isHealthy: boolean;
  lastPing: Date;
  failedPings: number;
  latency: number;
}

export interface HealingAction {
  type: 'RECONNECT' | 'SWITCH_SERVER' | 'NOTIFY_USER';
  reason: string;
  targetServerId?: string;
}

// ============================================================================
// User Profile Types
// ============================================================================

export interface UserProfile {
  id: string;
  email: string;
  name: string | null;
  subscriptionStatus: SubscriptionStatus;
  trialEndsAt: Date | null;
  subscriptionEndsAt: Date | null;
  isTestUser: boolean;
  createdAt: Date;
  clients: VPNClient[];
}

export interface UserStats {
  totalConnections: number;
  totalDataTransferred: number;
  favoriteServer?: string;
  averageLatency: number;
}
