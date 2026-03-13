/**
 * Payment Service Registry
 * ─────────────────────────
 * Single import point for the payment subsystem.
 * The controller calls getPaymentService(provider) to get the right implementation.
 */

import { squareService }   from './squareService';
import { paddleService }   from './paddleService';
import { coinbaseService } from './coinbaseService';
import type { IPaymentService } from './types';

export type ProviderKey = 'square' | 'paddle' | 'coinbase';

const SERVICES: Record<ProviderKey, IPaymentService> = {
  square:   squareService,
  paddle:   paddleService,
  coinbase: coinbaseService,
};

/**
 * Returns the correct IPaymentService for the given provider key.
 * Throws a clear error if the provider string is unknown.
 */
export function getPaymentService(provider: string): IPaymentService {
  const svc = SERVICES[provider.toLowerCase() as ProviderKey];
  if (!svc) {
    throw new Error(
      `Unknown payment provider: "${provider}". ` +
      'Valid values: square, paddle, coinbase',
    );
  }
  return svc;
}

// Re-export everything so other modules only need to import from this index
export { squareService, paddleService, coinbaseService };
export * from './types';
