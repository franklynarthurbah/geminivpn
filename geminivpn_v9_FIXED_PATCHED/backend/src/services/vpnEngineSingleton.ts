/**
 * VPN Engine Singleton
 * 
 * WHY THIS FILE EXISTS:
 *   server.ts creates VPNEngine and exports it.
 *   vpnController.ts imports from server.ts — causing a circular dependency:
 *     server.ts → vpnController.ts → server.ts → (crash / undefined exports)
 *
 *   Solution: move the singleton here. server.ts imports from HERE,
 *   and so does vpnController.ts — no circle.
 */
import { VPNEngine } from './vpnEngine';

export const vpnEngine = new VPNEngine();
