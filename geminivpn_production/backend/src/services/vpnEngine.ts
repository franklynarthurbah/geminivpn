/**
 * VPN Engine Service
 * Manages WireGuard VPN connections and client configurations
 * 
 * NOTE: This is a scaffold implementation. In production, integrate with:
 * - WireGuard tools (wg, wg-quick)
 * - Actual WireGuard kernel module
 * - Proper key management system
 */

import { PrismaClient } from '@prisma/client';
import { exec } from 'child_process';
import { promisify } from 'util';
import QRCode from 'qrcode';
import { logger } from '../utils/logger';

const execAsync = promisify(exec);
const prisma = new PrismaClient();

interface CreateClientParams {
  userId: string;
  clientName: string;
  serverId: string;
}

interface ClientConfig {
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

/**
 * VPN Engine class for managing WireGuard connections
 */
export class VPNEngine {
  private isInitialized: boolean = false;
  private configPath: string;
  private interfaceName: string;

  constructor() {
    this.configPath = process.env.WIREGUARD_CONFIG_PATH || '/etc/wireguard';
    this.interfaceName = process.env.WIREGUARD_INTERFACE || 'wg0';
  }

  /**
   * Initialize VPN engine
   */
  async initialize(): Promise<void> {
    try {
      logger.info('Initializing VPN Engine...');
      
      // In production, verify WireGuard is installed and configured
      // await this.verifyWireGuardInstallation();
      
      this.isInitialized = true;
      logger.info('VPN Engine initialized successfully');
    } catch (error) {
      logger.error('Failed to initialize VPN Engine:', error);
      throw error;
    }
  }

  /**
   * Shutdown VPN engine
   */
  async shutdown(): Promise<void> {
    try {
      logger.info('Shutting down VPN Engine...');
      
      // Disconnect all active clients
      const activeClients = await prisma.vPNClient.findMany({
        where: { isConnected: true },
      });

      for (const client of activeClients) {
        await this.disconnectClient(client.id);
      }

      this.isInitialized = false;
      logger.info('VPN Engine shut down successfully');
    } catch (error) {
      logger.error('Error during VPN Engine shutdown:', error);
    }
  }

  /**
   * Generate WireGuard key pair
   */
  private async generateKeyPair(): Promise<{ privateKey: string; publicKey: string }> {
    try {
      // In production, use actual WireGuard key generation:
      // const { stdout: privateKey } = await execAsync('wg genkey');
      // const { stdout: publicKey } = await execAsync(`echo "${privateKey.trim()}" | wg pubkey`);
      
      // For demo purposes, generate placeholder keys
      const privateKey = this.generatePlaceholderKey();
      const publicKey = this.generatePlaceholderKey();
      
      return { privateKey, publicKey };
    } catch (error) {
      logger.error('Key generation error:', error);
      throw new Error('Failed to generate WireGuard keys');
    }
  }

  /**
   * Generate placeholder key (for demo only)
   */
  private generatePlaceholderKey(): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let key = '';
    for (let i = 0; i < 44; i++) {
      key += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return key;
  }

  /**
   * Find available IP address in subnet
   */
  private async findAvailableIp(serverId: string, subnet: string): Promise<string> {
    // Parse subnet (e.g., "10.8.1.0/24")
    const [baseIp, prefix] = subnet.split('/');
    const baseParts = baseIp.split('.').map(Number);
    
    // Get used IPs for this server
    const usedClients = await prisma.vPNClient.findMany({
      where: { serverId },
      select: { assignedIp: true },
    });
    
    const usedIps = new Set(usedClients.map(c => c.assignedIp));
    
    // Find first available IP (skip .1 for server)
    for (let i = 2; i < 254; i++) {
      const candidateIp = `${baseParts[0]}.${baseParts[1]}.${baseParts[2]}.${i}`;
      if (!usedIps.has(candidateIp)) {
        return candidateIp;
      }
    }
    
    throw new Error('No available IP addresses in subnet');
  }

  /**
   * Generate WireGuard configuration file
   */
  private generateConfigFile(
    privateKey: string,
    assignedIp: string,
    server: any,
    clientPublicKey: string
  ): string {
    const dnsServers = server.dnsServers.join(', ');
    
    return `# GeminiVPN Configuration
# Device: Auto-generated
# Server: ${server.name}
# Created: ${new Date().toISOString()}

[Interface]
PrivateKey = ${privateKey}
Address = ${assignedIp}/32
DNS = ${dnsServers}
MTU = 1420

[Peer]
PublicKey = ${server.publicKey}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${server.hostname}:${server.port}
PersistentKeepalive = 25
`;
  }

  /**
   * Create new VPN client
   */
  async createClient(params: CreateClientParams): Promise<ClientConfig> {
    const { userId, clientName, serverId } = params;

    try {
      // Get server details
      const server = await prisma.vPNServer.findUnique({
        where: { id: serverId },
      });

      if (!server) {
        throw new Error('Server not found');
      }

      // Generate key pair
      const { privateKey, publicKey } = await this.generateKeyPair();

      // Find available IP
      const assignedIp = await this.findAvailableIp(serverId, server.subnet);

      // Generate config file
      const configFile = this.generateConfigFile(privateKey, assignedIp, server, publicKey);

      // Generate QR code
      const qrCode = await QRCode.toDataURL(configFile, {
        width: 400,
        margin: 2,
        color: {
          dark: '#00F0FF',
          light: '#070A12',
        },
      });

      // Create client in database
      const client = await prisma.vPNClient.create({
        data: {
          userId,
          clientName,
          publicKey,
          privateKey, // In production, encrypt this!
          assignedIp,
          serverId,
          configFile,
          qrCodeData: qrCode,
        },
        include: {
          server: true,
        },
      });

      // Update server client count
      await prisma.vPNServer.update({
        where: { id: serverId },
        data: {
          currentClients: { increment: 1 },
        },
      });

      logger.info(`Created VPN client: ${clientName} (${client.id})`);

      return {
        id: client.id,
        clientName: client.clientName,
        assignedIp: client.assignedIp,
        server: {
          hostname: client.server.hostname,
          port: client.server.port,
          publicKey: client.server.publicKey,
        },
        configFile,
        qrCode,
      };
    } catch (error) {
      logger.error('Create client error:', error);
      throw error;
    }
  }

  /**
   * Remove VPN client
   */
  async removeClient(clientId: string): Promise<void> {
    try {
      const client = await prisma.vPNClient.findUnique({
        where: { id: clientId },
      });

      if (!client) {
        throw new Error('Client not found');
      }

      // Disconnect if connected
      if (client.isConnected) {
        await this.disconnectClient(clientId);
      }

      // Update server client count
      await prisma.vPNServer.update({
        where: { id: client.serverId },
        data: {
          currentClients: { decrement: 1 },
        },
      });

      // In production, remove from WireGuard:
      // await execAsync(`wg set ${this.interfaceName} peer ${client.publicKey} remove`);

      logger.info(`Removed VPN client: ${clientId}`);
    } catch (error) {
      logger.error('Remove client error:', error);
      throw error;
    }
  }

  /**
   * Connect client to VPN
   */
  async connectClient(clientId: string): Promise<void> {
    try {
      const client = await prisma.vPNClient.findUnique({
        where: { id: clientId },
        include: { server: true },
      });

      if (!client) {
        throw new Error('Client not found');
      }

      // In production, add peer to WireGuard:
      // const command = `wg set ${this.interfaceName} peer ${client.publicKey} allowed-ips ${client.assignedIp}/32`;
      // await execAsync(command);

      // Update server load
      await this.updateServerLoad(client.serverId);

      logger.info(`Connected client: ${clientId}`);
    } catch (error) {
      logger.error('Connect client error:', error);
      throw error;
    }
  }

  /**
   * Disconnect client from VPN
   */
  async disconnectClient(clientId: string): Promise<void> {
    try {
      const client = await prisma.vPNClient.findUnique({
        where: { id: clientId },
        include: { server: true },
      });

      if (!client) {
        throw new Error('Client not found');
      }

      // In production, remove peer from WireGuard:
      // await execAsync(`wg set ${this.interfaceName} peer ${client.publicKey} remove`);

      // Update server load
      await this.updateServerLoad(client.serverId);

      logger.info(`Disconnected client: ${clientId}`);
    } catch (error) {
      logger.error('Disconnect client error:', error);
      throw error;
    }
  }

  /**
   * Update server load metrics
   */
  private async updateServerLoad(serverId: string): Promise<void> {
    try {
      const connectedClients = await prisma.vPNClient.count({
        where: {
          serverId,
          isConnected: true,
        },
      });

      const server = await prisma.vPNServer.findUnique({
        where: { id: serverId },
      });

      if (server) {
        const loadPercentage = Math.round((connectedClients / server.maxClients) * 100);
        
        await prisma.vPNServer.update({
          where: { id: serverId },
          data: {
            currentClients: connectedClients,
            loadPercentage,
          },
        });
      }
    } catch (error) {
      logger.error('Update server load error:', error);
    }
  }

  /**
   * Verify WireGuard installation (production only)
   */
  private async verifyWireGuardInstallation(): Promise<void> {
    try {
      await execAsync('which wg');
      await execAsync('which wg-quick');
      logger.info('WireGuard tools verified');
    } catch (error) {
      throw new Error('WireGuard tools not found. Please install WireGuard.');
    }
  }

  /**
   * Get engine status
   */
  getStatus(): { isInitialized: boolean; configPath: string; interfaceName: string } {
    return {
      isInitialized: this.isInitialized,
      configPath: this.configPath,
      interfaceName: this.interfaceName,
    };
  }
}
