/**
 * VPN Controller
 * Handles VPN client management, connections, and configuration
 */

import { Response } from 'express';
import { PrismaClient } from '@prisma/client';
import { AuthenticatedRequest, VPNClientConfig, ConnectionStatus } from '../types';
import { vpnEngine } from '../server';
import { logger } from '../utils/logger';

const prisma = new PrismaClient();

/**
 * Get all VPN clients for user
 */
export const getClients = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const clients = await prisma.vPNClient.findMany({
      where: { userId: req.user.id },
      include: {
        server: {
          select: {
            id: true,
            name: true,
            country: true,
            city: true,
            hostname: true,
            latencyMs: true,
            loadPercentage: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    res.json({
      success: true,
      data: clients,
    });
  } catch (error) {
    logger.error('Get clients error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get VPN clients',
    });
  }
};

/**
 * Create new VPN client
 */
export const createClient = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const { clientName, serverId } = req.body;

    // Check client limit (max 10 per user)
    const existingClients = await prisma.vPNClient.count({
      where: { userId: req.user.id },
    });

    if (existingClients >= 10) {
      res.status(400).json({
        success: false,
        message: 'Maximum 10 devices allowed. Please remove an existing device.',
      });
      return;
    }

    // Select server (use provided or auto-select best)
    let server;
    if (serverId) {
      server = await prisma.vPNServer.findUnique({
        where: { id: serverId, isActive: true },
      });
    }

    // Auto-select if not provided or not found
    if (!server) {
      server = await prisma.vPNServer.findFirst({
        where: { isActive: true, isMaintenance: false },
        orderBy: [{ loadPercentage: 'asc' }, { latencyMs: 'asc' }],
      });
    }

    if (!server) {
      res.status(503).json({
        success: false,
        message: 'No available servers. Please try again later.',
      });
      return;
    }

    // Create client via VPN engine
    const clientConfig = await vpnEngine.createClient({
      userId: req.user.id,
      clientName,
      serverId: server.id,
    });

    logger.info(`VPN client created: ${clientName} for user ${req.user.email}`);

    res.status(201).json({
      success: true,
      message: 'VPN client created successfully',
      data: clientConfig,
    });
  } catch (error) {
    logger.error('Create client error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create VPN client',
    });
  }
};

/**
 * Get client configuration
 */
export const getClientConfig = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const { clientId } = req.params;

    const client = await prisma.vPNClient.findFirst({
      where: {
        id: clientId,
        userId: req.user.id,
      },
      include: {
        server: true,
      },
    });

    if (!client) {
      res.status(404).json({
        success: false,
        message: 'Client not found',
      });
      return;
    }

    const config: VPNClientConfig = {
      id: client.id,
      clientName: client.clientName,
      assignedIp: client.assignedIp,
      server: {
        hostname: client.server.hostname,
        port: client.server.port,
        publicKey: client.server.publicKey,
      },
      configFile: client.configFile || '',
      qrCode: client.qrCodeData || '',
    };

    res.json({
      success: true,
      data: config,
    });
  } catch (error) {
    logger.error('Get client config error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get client configuration',
    });
  }
};

/**
 * Delete VPN client
 */
export const deleteClient = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const { clientId } = req.params;

    const client = await prisma.vPNClient.findFirst({
      where: {
        id: clientId,
        userId: req.user.id,
      },
    });

    if (!client) {
      res.status(404).json({
        success: false,
        message: 'Client not found',
      });
      return;
    }

    // Remove from VPN engine
    await vpnEngine.removeClient(client.id);

    // Delete from database
    await prisma.vPNClient.delete({
      where: { id: clientId },
    });

    logger.info(`VPN client deleted: ${clientId}`);

    res.json({
      success: true,
      message: 'VPN client deleted successfully',
    });
  } catch (error) {
    logger.error('Delete client error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete VPN client',
    });
  }
};

/**
 * Get connection status
 */
export const getConnectionStatus = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const { clientId } = req.params;

    const client = await prisma.vPNClient.findFirst({
      where: {
        id: clientId,
        userId: req.user.id,
      },
      include: {
        server: true,
      },
    });

    if (!client) {
      res.status(404).json({
        success: false,
        message: 'Client not found',
      });
      return;
    }

    const status: ConnectionStatus = {
      isConnected: client.isConnected,
      serverId: client.serverId,
      serverName: client.server.name,
      assignedIp: client.assignedIp,
      connectedAt: client.lastConnectedAt || undefined,
      dataTransferred: Number(client.dataTransferred),
      latency: client.server.latencyMs || undefined,
    };

    res.json({
      success: true,
      data: status,
    });
  } catch (error) {
    logger.error('Get connection status error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get connection status',
    });
  }
};

/**
 * Connect to VPN
 */
export const connect = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const { clientId } = req.params;

    const client = await prisma.vPNClient.findFirst({
      where: {
        id: clientId,
        userId: req.user.id,
      },
      include: {
        server: true,
      },
    });

    if (!client) {
      res.status(404).json({
        success: false,
        message: 'Client not found',
      });
      return;
    }

    // Connect via VPN engine
    await vpnEngine.connectClient(client.id);

    // Update client status
    await prisma.vPNClient.update({
      where: { id: clientId },
      data: {
        isConnected: true,
        lastConnectedAt: new Date(),
      },
    });

    // Log connection
    await prisma.connectionLog.create({
      data: {
        userId: req.user.id,
        clientId: client.id,
        serverId: client.serverId,
        eventType: 'CONNECT',
        assignedIp: client.assignedIp,
        clientIp: req.ip,
      },
    });

    logger.info(`Client connected: ${clientId}`);

    res.json({
      success: true,
      message: 'Connected successfully',
      data: {
        isConnected: true,
        serverName: client.server.name,
        assignedIp: client.assignedIp,
      },
    });
  } catch (error) {
    logger.error('Connect error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to connect',
    });
  }
};

/**
 * Disconnect from VPN
 */
export const disconnect = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const { clientId } = req.params;

    const client = await prisma.vPNClient.findFirst({
      where: {
        id: clientId,
        userId: req.user.id,
      },
    });

    if (!client) {
      res.status(404).json({
        success: false,
        message: 'Client not found',
      });
      return;
    }

    // Disconnect via VPN engine
    await vpnEngine.disconnectClient(client.id);

    // Update client status
    await prisma.vPNClient.update({
      where: { id: clientId },
      data: { isConnected: false },
    });

    // Log disconnection
    await prisma.connectionLog.create({
      data: {
        userId: req.user.id,
        clientId: client.id,
        serverId: client.serverId,
        eventType: 'DISCONNECT',
      },
    });

    logger.info(`Client disconnected: ${clientId}`);

    res.json({
      success: true,
      message: 'Disconnected successfully',
    });
  } catch (error) {
    logger.error('Disconnect error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to disconnect',
    });
  }
};

/**
 * Get user's overall connection status
 */
export const getOverallStatus = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Authentication required',
      });
      return;
    }

    const clients = await prisma.vPNClient.findMany({
      where: { userId: req.user.id },
      include: {
        server: {
          select: {
            name: true,
            country: true,
            city: true,
            latencyMs: true,
          },
        },
      },
    });

    const connectedClients = clients.filter(c => c.isConnected);

    res.json({
      success: true,
      data: {
        totalClients: clients.length,
        connectedClients: connectedClients.length,
        isAnyConnected: connectedClients.length > 0,
        activeConnections: connectedClients.map(c => ({
          clientId: c.id,
          clientName: c.clientName,
          serverName: c.server.name,
          assignedIp: c.assignedIp,
          connectedAt: c.lastConnectedAt,
          latency: c.server.latencyMs,
        })),
      },
    });
  } catch (error) {
    logger.error('Get overall status error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get connection status',
    });
  }
};
