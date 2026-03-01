/**
 * Connection Monitor Service
 * Handles auto-refresh connections and self-healing error recovery
 */

import { PrismaClient, ConnectionEvent } from '@prisma/client';
import cron from 'node-cron';
import { logger } from '../utils/logger';
import { vpnEngine } from '../server';

const prisma = new PrismaClient();

interface ConnectionHealth {
  clientId: string;
  userId: string;
  serverId: string;
  lastPing: Date;
  failedPings: number;
  latency: number;
  isHealthy: boolean;
}

interface HealingAction {
  type: 'RECONNECT' | 'SWITCH_SERVER' | 'NOTIFY_USER' | 'NONE';
  reason: string;
  targetServerId?: string;
}

/**
 * Connection Monitor class
 * Monitors VPN connections and performs self-healing actions
 */
export class ConnectionMonitor {
  private isRunning: boolean = false;
  private checkInterval: number;
  private maxReconnectAttempts: number;
  private reconnectAttempts: Map<string, number> = new Map();
  private monitorTask: cron.ScheduledTask | null = null;

  constructor() {
    this.checkInterval = parseInt(process.env.AUTO_REFRESH_INTERVAL_MS || '30000');
    this.maxReconnectAttempts = parseInt(process.env.MAX_RECONNECT_ATTEMPTS || '5');
  }

  /**
   * Start the connection monitor
   */
  start(): void {
    if (this.isRunning) {
      logger.warn('Connection monitor is already running');
      return;
    }

    logger.info('Starting connection monitor...');
    
    // Schedule health checks every 30 seconds
    this.monitorTask = cron.schedule('*/30 * * * * *', async () => {
      await this.performHealthCheck();
    });

    this.isRunning = true;
    logger.info(`Connection monitor started (interval: ${this.checkInterval}ms)`);
  }

  /**
   * Stop the connection monitor
   */
  stop(): void {
    if (!this.isRunning) {
      return;
    }

    logger.info('Stopping connection monitor...');
    
    if (this.monitorTask) {
      this.monitorTask.stop();
      this.monitorTask = null;
    }

    this.isRunning = false;
    logger.info('Connection monitor stopped');
  }

  /**
   * Perform health check on all active connections
   */
  private async performHealthCheck(): Promise<void> {
    try {
      // Get all connected clients
      const connectedClients = await prisma.vPNClient.findMany({
        where: { isConnected: true },
        include: { server: true },
      });

      if (connectedClients.length === 0) {
        return;
      }

      logger.debug(`Health checking ${connectedClients.length} connections`);

      for (const client of connectedClients) {
        await this.checkClientHealth(client);
      }
    } catch (error) {
      logger.error('Health check error:', error);
    }
  }

  /**
   * Check health of individual client connection
   */
  private async checkClientHealth(client: any): Promise<void> {
    try {
      // Simulate ping test (in production, actual ICMP or WireGuard handshake check)
      const health = await this.pingClient(client);

      if (!health.isHealthy) {
        logger.warn(`Unhealthy connection detected: ${client.id} (${client.clientName})`);
        
        // Increment failed ping counter
        const currentAttempts = this.reconnectAttempts.get(client.id) || 0;
        this.reconnectAttempts.set(client.id, currentAttempts + 1);

        // Determine healing action
        const action = await this.determineHealingAction(client, health);
        
        if (action.type !== 'NONE') {
          await this.executeHealingAction(client, action);
        }
      } else {
        // Reset reconnect attempts on successful health check
        this.reconnectAttempts.delete(client.id);
        
        // Update latency in database
        await prisma.vPNServer.update({
          where: { id: client.serverId },
          data: { latencyMs: health.latency },
        });
      }
    } catch (error) {
      logger.error(`Health check error for client ${client.id}:`, error);
    }
  }

  /**
   * Ping client to check connectivity
   */
  private async pingClient(client: any): Promise<ConnectionHealth> {
    // In production, implement actual ping:
    // - ICMP ping to assigned IP
    // - WireGuard handshake check
    // - Traffic flow verification

    // Simulate ping with random latency for demo
    const latency = Math.floor(Math.random() * 50) + 5; // 5-55ms
    const isHealthy = latency < 100; // Healthy if under 100ms

    return {
      clientId: client.id,
      userId: client.userId,
      serverId: client.serverId,
      lastPing: new Date(),
      failedPings: this.reconnectAttempts.get(client.id) || 0,
      latency,
      isHealthy,
    };
  }

  /**
   * Determine healing action based on health status
   */
  private async determineHealingAction(
    client: any,
    health: ConnectionHealth
  ): Promise<HealingAction> {
    const attempts = this.reconnectAttempts.get(client.id) || 0;

    // If max attempts reached, notify user
    if (attempts >= this.maxReconnectAttempts) {
      return {
        type: 'NOTIFY_USER',
        reason: `Connection failed after ${attempts} reconnection attempts`,
      };
    }

    // Check server health
    const server = await prisma.vPNServer.findUnique({
      where: { id: client.serverId },
    });

    if (!server || server.isMaintenance || server.loadPercentage > 90) {
      // Find alternative server
      const alternativeServer = await prisma.vPNServer.findFirst({
        where: {
          id: { not: client.serverId },
          isActive: true,
          isMaintenance: false,
          loadPercentage: { lt: 70 },
        },
        orderBy: [{ loadPercentage: 'asc' }, { latencyMs: 'asc' }],
      });

      if (alternativeServer) {
        return {
          type: 'SWITCH_SERVER',
          reason: 'Current server overloaded or in maintenance',
          targetServerId: alternativeServer.id,
        };
      }
    }

    // Default: try to reconnect
    return {
      type: 'RECONNECT',
      reason: `Connection unstable (latency: ${health.latency}ms)`,
    };
  }

  /**
   * Execute healing action
   */
  private async executeHealingAction(client: any, action: HealingAction): Promise<void> {
    logger.info(`Executing healing action: ${action.type} for client ${client.id}`);

    // Log healing event
    await prisma.connectionLog.create({
      data: {
        userId: client.userId,
        clientId: client.id,
        serverId: client.serverId,
        eventType: ConnectionEvent.HEALING_TRIGGERED,
        errorMessage: action.reason,
      },
    });

    switch (action.type) {
      case 'RECONNECT':
        await this.reconnectClient(client);
        break;

      case 'SWITCH_SERVER':
        if (action.targetServerId) {
          await this.switchServer(client, action.targetServerId);
        }
        break;

      case 'NOTIFY_USER':
        await this.notifyUserOfIssue(client, action.reason);
        break;

      default:
        logger.warn(`Unknown healing action: ${action.type}`);
    }
  }

  /**
   * Reconnect client to same server
   */
  private async reconnectClient(client: any): Promise<void> {
    try {
      logger.info(`Attempting reconnection for client ${client.id}`);

      // Disconnect
      await vpnEngine.disconnectClient(client.id);
      
      // Wait briefly
      await this.sleep(1000);
      
      // Reconnect
      await vpnEngine.connectClient(client.id);

      // Log reconnection
      await prisma.connectionLog.create({
        data: {
          userId: client.userId,
          clientId: client.id,
          serverId: client.serverId,
          eventType: ConnectionEvent.RECONNECT,
        },
      });

      logger.info(`Reconnection successful for client ${client.id}`);
    } catch (error) {
      logger.error(`Reconnection failed for client ${client.id}:`, error);
    }
  }

  /**
   * Switch client to different server
   */
  private async switchServer(client: any, newServerId: string): Promise<void> {
    try {
      logger.info(`Switching client ${client.id} to server ${newServerId}`);

      // Get new server details
      const newServer = await prisma.vPNServer.findUnique({
        where: { id: newServerId },
      });

      if (!newServer) {
        throw new Error('Target server not found');
      }

      // Disconnect from current server
      await vpnEngine.disconnectClient(client.id);

      // Create new client config for new server
      const newConfig = await vpnEngine.createClient({
        userId: client.userId,
        clientName: client.clientName,
        serverId: newServerId,
      });

      // Delete old client
      await prisma.vPNClient.delete({
        where: { id: client.id },
      });

      // Connect to new server
      await vpnEngine.connectClient(newConfig.id);

      logger.info(`Server switch successful: ${client.id} -> ${newConfig.id}`);
    } catch (error) {
      logger.error(`Server switch failed for client ${client.id}:`, error);
    }
  }

  /**
   * Notify user of connection issue
   */
  private async notifyUserOfIssue(client: any, reason: string): Promise<void> {
    logger.warn(`Notifying user ${client.userId} of connection issue: ${reason}`);
    
    // In production, send notification via:
    // - Email
    // - Push notification
    // - In-app notification
    // - WebSocket message

    // For now, just log it
    await prisma.connectionLog.create({
      data: {
        userId: client.userId,
        clientId: client.id,
        serverId: client.serverId,
        eventType: ConnectionEvent.ERROR,
        errorMessage: reason,
      },
    });
  }

  /**
   * Manual refresh connection (called by user)
   */
  async refreshConnection(clientId: string): Promise<boolean> {
    try {
      const client = await prisma.vPNClient.findUnique({
        where: { id: clientId },
      });

      if (!client) {
        throw new Error('Client not found');
      }

      if (!client.isConnected) {
        throw new Error('Client is not connected');
      }

      await this.reconnectClient(client);
      return true;
    } catch (error) {
      logger.error(`Manual refresh failed for client ${clientId}:`, error);
      return false;
    }
  }

  /**
   * Get monitor status
   */
  getStatus(): { isRunning: boolean; checkInterval: number; maxReconnectAttempts: number } {
    return {
      isRunning: this.isRunning,
      checkInterval: this.checkInterval,
      maxReconnectAttempts: this.maxReconnectAttempts,
    };
  }

  /**
   * Utility: Sleep for specified milliseconds
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
