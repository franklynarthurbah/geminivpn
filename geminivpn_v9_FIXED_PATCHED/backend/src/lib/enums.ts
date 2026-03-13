/**
 * GeminiVPN — Application-level Enum Constants
 *
 * WHY THIS FILE EXISTS:
 *   SQLite does not support Prisma enum types (Prisma P1012 error).
 *   The schema uses plain String fields. This file provides the same
 *   named constants and TypeScript types that the rest of the code
 *   previously imported from '@prisma/client'.
 *
 *   Usage:
 *     import { SubscriptionStatus, PaymentProvider, PaymentStatus, PlanType }
 *       from '../lib/enums';
 *
 *     user.subscriptionStatus === SubscriptionStatus.ACTIVE  // true
 *     user.subscriptionStatus satisfies SubscriptionStatusType // type-safe
 */

// ─── Subscription Status ─────────────────────────────────────────────────────

export const SubscriptionStatus = {
  TRIAL:     'TRIAL',
  ACTIVE:    'ACTIVE',
  EXPIRED:   'EXPIRED',
  CANCELLED: 'CANCELLED',
  SUSPENDED: 'SUSPENDED',
} as const;

export type SubscriptionStatusType =
  (typeof SubscriptionStatus)[keyof typeof SubscriptionStatus];

// ─── Plan Type ────────────────────────────────────────────────────────────────

export const PlanType = {
  MONTHLY:  'MONTHLY',
  YEARLY:   'YEARLY',
  TWO_YEAR: 'TWO_YEAR',
} as const;

export type PlanTypeType = (typeof PlanType)[keyof typeof PlanType];

// ─── Payment Status ───────────────────────────────────────────────────────────

export const PaymentStatus = {
  PENDING:   'PENDING',
  COMPLETED: 'COMPLETED',
  FAILED:    'FAILED',
  REFUNDED:  'REFUNDED',
} as const;

export type PaymentStatusType =
  (typeof PaymentStatus)[keyof typeof PaymentStatus];

// ─── Payment Provider ─────────────────────────────────────────────────────────

export const PaymentProvider = {
  STRIPE:   'STRIPE',
  SQUARE:   'SQUARE',
  PADDLE:   'PADDLE',
  COINBASE: 'COINBASE',
} as const;

export type PaymentProviderType =
  (typeof PaymentProvider)[keyof typeof PaymentProvider];
