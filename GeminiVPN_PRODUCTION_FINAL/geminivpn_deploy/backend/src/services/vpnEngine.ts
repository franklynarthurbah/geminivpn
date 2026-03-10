/**
 * VPN Engine Service — aligned with schema (VPNClient.name not clientName)
 */
import { PrismaClient } from '@prisma/client';
import { exec } from 'child_process';
import { promisify } from 'util';
import QRCode from 'qrcode';
import { logger } from '../utils/logger';

const execAsync = promisify(exec);
const prisma = new PrismaClient();

interface CreateClientParams { userId: string; clientName: string; serverId: string; }
interface ClientConfig {
  id: string; clientName: string; assignedIp: string;
  server: { hostname: string; port: number; publicKey: string; };
  configFile: string; qrCode: string;
}

export class VPNEngine {
  private isInitialized = false;
  private configPath: string;
  private interfaceName: string;

  constructor() {
    this.configPath   = process.env.WIREGUARD_CONFIG_PATH || '/etc/wireguard';
    this.interfaceName = process.env.WIREGUARD_INTERFACE  || 'wg0';
  }

  async initialize(): Promise<void> {
    try {
      logger.info('Initializing VPN Engine...');
      this.isInitialized = true;
      logger.info('VPN Engine initialized successfully');
    } catch (error) {
      logger.error('Failed to initialize VPN Engine:', error);
      throw error;
    }
  }

  async shutdown(): Promise<void> {
    try {
      logger.info('Shutting down VPN Engine...');
      const activeClients = await prisma.vPNClient.findMany({ where: { isConnected: true } });
      for (const client of activeClients) await this.disconnectClient(client.id);
      this.isInitialized = false;
      logger.info('VPN Engine shut down successfully');
    } catch (error) {
      logger.error('Error during VPN Engine shutdown:', error);
    }
  }

  private async generateKeyPair(): Promise<{ privateKey: string; publicKey: string }> {
    try {
      if (process.env.WIREGUARD_ENABLED === 'true') {
        const { stdout: privKeyRaw } = await execAsync('wg genkey');
        const privateKey = privKeyRaw.trim();
        const { stdout: pubKeyRaw } = await execAsync(`echo "${privateKey}" | wg pubkey`);
        return { privateKey, publicKey: pubKeyRaw.trim() };
      }
    } catch { /* fall through to mock */ }
    // Mock keys for dev/test
    const mockPriv = Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64');
    const mockPub  = Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64');
    return { privateKey: mockPriv, publicKey: mockPub };
  }

  private async findNextAvailableIp(subnet: string): Promise<string> {
    const base = subnet.split('/')[0].split('.');
    const prefix = `${base[0]}.${base[1]}.${base[2]}`;
    const existing = await prisma.vPNClient.findMany({ select: { assignedIp: true } });
    const usedLast = new Set(existing.map((c) => parseInt(c.assignedIp.split('.')[3])));
    for (let i = 2; i < 255; i++) {
      if (!usedLast.has(i)) return `${prefix}.${i}`;
    }
    throw new Error('No available IP addresses in subnet');
  }

  async createClient(params: CreateClientParams): Promise<ClientConfig> {
    const { userId, clientName, serverId } = params;
    const server = await prisma.vPNServer.findUnique({ where: { id: serverId } });
    if (!server) throw new Error('Server not found');

    const { privateKey, publicKey } = await this.generateKeyPair();
    const assignedIp = await this.findNextAvailableIp(server.subnet);

    const configContent = this.generateConfigFile({
      privateKey, assignedIp,
      serverPublicKey: server.publicKey,
      serverEndpoint: `${server.hostname}:${server.port}`,
      dns: server.dnsServers,
    });

    let qrCodeData = '';
    try { qrCodeData = await QRCode.toDataURL(configContent); } catch { /* non-fatal */ }

    const client = await prisma.vPNClient.create({
      data: {
        userId, name: clientName,          // ← use 'name' not 'clientName'
        publicKey, privateKey, assignedIp,
        serverId, configFile: configContent, qrCodeData,
      },
    });

    logger.info(`Created VPN client: ${clientName} (${client.id})`);

    return {
      id: client.id,
      clientName: client.name,             // ← expose as clientName in API response
      assignedIp: client.assignedIp,
      server: { hostname: server.hostname, port: server.port, publicKey: server.publicKey },
      configFile: configContent,
      qrCode: qrCodeData,
    };
  }

  private generateConfigFile(opts: {
    privateKey: string; assignedIp: string;
    serverPublicKey: string; serverEndpoint: string; dns: string;
  }): string {
    return `[Interface]
PrivateKey = ${opts.privateKey}
Address = ${opts.assignedIp}/32
DNS = ${opts.dns}
MTU = 1420
# Table = off  # Uncomment for split-tunnel (route specific traffic only)

[Peer]
PublicKey = ${opts.serverPublicKey}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${opts.serverEndpoint}
# PersistentKeepalive = 15 keeps NAT mapping alive aggressively (vs default 25s)
# Prevents latency spikes from NAT re-establishment on idle connections
PersistentKeepalive = 15
`;
  }

  async connectClient(clientId: string): Promise<void> {
    logger.info(`VPN Engine: connecting client ${clientId}`);
    // Production: call wg-quick or add peer to interface
  }

  async disconnectClient(clientId: string): Promise<void> {
    logger.info(`VPN Engine: disconnecting client ${clientId}`);
    // Production: call wg-quick down or remove peer
  }

  async removeClient(clientId: string): Promise<void> {
    logger.info(`VPN Engine: removing client ${clientId}`);
  }

  async getServerMetrics(serverId: string) {
    const server = await prisma.vPNServer.findUnique({ where: { id: serverId } });
    if (!server) throw new Error('Server not found');
    const clientCount = await prisma.vPNClient.count({ where: { serverId, isConnected: true } });
    return {
      serverId,
      latency:        server.latencyMs,
      loadPercentage: server.loadPercentage,
      currentClients: clientCount,
      isHealthy:      server.isActive && !server.isMaintenance,
    };
  }
}
