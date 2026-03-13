/**
 * Connection Monitor
 * Uses vpnEngineSingleton.ts to avoid circular dependencies with server.ts
 */
import prisma from '../lib/prisma';
import cron from 'node-cron';
import { logger } from '../utils/logger';


// vpnEngine singleton — no circular dep
// (server.ts re-exports vpnEngine from here via vpnEngineSingleton.ts)
import { vpnEngine } from './vpnEngineSingleton';

export class ConnectionMonitor {
  private isRunning = false;
  private checkInterval: number;
  private maxReconnectAttempts: number;
  private reconnectAttempts = new Map<string, number>();
  private monitorTask: cron.ScheduledTask | null = null;

  constructor() {
    this.checkInterval        = parseInt(process.env.AUTO_REFRESH_INTERVAL_MS || '30000');
    this.maxReconnectAttempts = parseInt(process.env.MAX_RECONNECT_ATTEMPTS   || '5');
  }

  start(): void {
    if (this.isRunning) return;
    this.isRunning = true;
    this.monitorTask = cron.schedule('*/30 * * * * *', () =>
      this.checkConnections().catch((e) => logger.error('Monitor check failed:', e))
    );
    logger.info('Connection monitor started');
  }

  stop(): void {
    if (!this.isRunning) return;
    this.monitorTask?.stop();
    this.isRunning = false;
    logger.info('Connection monitor stopped');
  }

  private async checkConnections(): Promise<void> {
    try {
      const connectedClients = await prisma.vPNClient.findMany({
        where: { isConnected: true },
        include: { server: true },
      });
      for (const client of connectedClients) {
        await this.checkClientHealth(client);
      }
    } catch (error) {
      logger.error('Error checking connections:', error);
    }
  }

  private async checkClientHealth(client: any): Promise<void> {
    try {
      const isHealthy = await this.pingClient(client);
      if (!isHealthy) {
        const attempts = this.reconnectAttempts.get(client.id) || 0;
        if (attempts < this.maxReconnectAttempts) {
          this.reconnectAttempts.set(client.id, attempts + 1);
          await this.reconnectClient(client);
        } else {
          await this.handleMaxRetriesExceeded(client);
        }
      } else {
        this.reconnectAttempts.delete(client.id);
      }
    } catch (error) {
      logger.error(`Health check failed for client ${client.id}:`, error);
    }
  }

  private async pingClient(_client: any): Promise<boolean> {
    if (process.env.WIREGUARD_ENABLED !== 'true') return true;
    return true;
  }

  private async reconnectClient(client: any): Promise<void> {
    try {
      logger.info(`Self-healing: reconnecting client ${client.id}`);
      await vpnEngine.disconnectClient(client.id);
      await new Promise((r) => setTimeout(r, 2000));
      await vpnEngine.connectClient(client.id);
      await prisma.connectionLog.create({
        data: { userId: client.userId, clientId: client.id, serverId: client.serverId, eventType: 'HEALING_TRIGGERED', clientIp: null },
      });
      logger.info(`Self-healing successful for client ${client.id}`);
    } catch (error) {
      logger.error(`Reconnect failed for client ${client.id}:`, error);
    }
  }

  private async handleMaxRetriesExceeded(client: any): Promise<void> {
    logger.warn(`Max reconnect attempts exceeded for client ${client.id}`);
    await prisma.vPNClient.update({ where: { id: client.id }, data: { isConnected: false } });
    await prisma.connectionLog.create({
      data: { userId: client.userId, clientId: client.id, serverId: client.serverId, eventType: 'ERROR' },
    });
    this.reconnectAttempts.delete(client.id);
  }

  async refreshConnection(clientId: string): Promise<boolean> {
    try {
      const client = await prisma.vPNClient.findUnique({ where: { id: clientId } });
      if (!client) throw new Error('Client not found');
      if (!client.isConnected) throw new Error('Client is not connected');
      await this.reconnectClient(client);
      return true;
    } catch (error) {
      logger.error(`Manual refresh failed for client ${clientId}:`, error);
      return false;
    }
  }

  getStatus() {
    return { isRunning: this.isRunning, checkInterval: this.checkInterval, maxReconnectAttempts: this.maxReconnectAttempts };
  }
}
