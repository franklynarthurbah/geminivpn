/**
 * GeminiVPN Database Seeder
 * Creates initial data including test user and VPN servers
 */

import { PrismaClient, SubscriptionStatus, PlanType } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Starting database seed...\n');

  // Create test user: alibasma / alibabaat2026
  const testUserPassword = await bcrypt.hash('alibabaat2026', 12);
  
  const testUser = await prisma.user.upsert({
    where: { email: 'alibasma' },
    update: {},
    create: {
      email: 'alibasma',
      password: testUserPassword,
      name: 'Ali Basma (Test User)',
      subscriptionStatus: SubscriptionStatus.ACTIVE,
      isTestUser: true,
      // Set subscription to expire far in the future for testing
      subscriptionEndsAt: new Date('2030-12-31T23:59:59Z'),
      emailVerified: true,
      lastLoginAt: new Date(),
    },
  });
  
  console.log('✅ Test user created:', {
    id: testUser.id,
    email: testUser.email,
    name: testUser.name,
    subscriptionStatus: testUser.subscriptionStatus,
    isTestUser: testUser.isTestUser,
  });

  // Create global VPN servers
  const servers = [
    {
      name: 'New York, USA',
      country: 'US',
      city: 'New York',
      region: 'NY',
      hostname: 'us-ny.geminivpn.com',
      port: 51820,
      publicKey: 'PLACEHOLDER_NY_PUBLIC_KEY',
      subnet: '10.8.1.0/24',
      dnsServers: ['1.1.1.1', '1.0.0.1'],
      maxClients: 1000,
      latencyMs: 9,
    },
    {
      name: 'Los Angeles, USA',
      country: 'US',
      city: 'Los Angeles',
      region: 'CA',
      hostname: 'us-la.geminivpn.com',
      port: 51820,
      publicKey: 'PLACEHOLDER_LA_PUBLIC_KEY',
      subnet: '10.8.2.0/24',
      dnsServers: ['1.1.1.1', '1.0.0.1'],
      maxClients: 1000,
      latencyMs: 12,
    },
    {
      name: 'London, UK',
      country: 'GB',
      city: 'London',
      region: 'England',
      hostname: 'uk-ln.geminivpn.com',
      port: 51820,
      publicKey: 'PLACEHOLDER_LN_PUBLIC_KEY',
      subnet: '10.8.3.0/24',
      dnsServers: ['1.1.1.1', '1.0.0.1'],
      maxClients: 800,
      latencyMs: 15,
    },
    {
      name: 'Frankfurt, Germany',
      country: 'DE',
      city: 'Frankfurt',
      region: 'Hesse',
      hostname: 'de-fr.geminivpn.com',
      port: 51820,
      publicKey: 'PLACEHOLDER_FR_PUBLIC_KEY',
      subnet: '10.8.4.0/24',
      dnsServers: ['1.1.1.1', '1.0.0.1'],
      maxClients: 800,
      latencyMs: 18,
    },
    {
      name: 'Tokyo, Japan',
      country: 'JP',
      city: 'Tokyo',
      region: 'Tokyo',
      hostname: 'jp-tk.geminivpn.com',
      port: 51820,
      publicKey: 'PLACEHOLDER_TK_PUBLIC_KEY',
      subnet: '10.8.5.0/24',
      dnsServers: ['1.1.1.1', '1.0.0.1'],
      maxClients: 600,
      latencyMs: 22,
    },
    {
      name: 'Singapore',
      country: 'SG',
      city: 'Singapore',
      region: 'Singapore',
      hostname: 'sg-sg.geminivpn.com',
      port: 51820,
      publicKey: 'PLACEHOLDER_SG_PUBLIC_KEY',
      subnet: '10.8.6.0/24',
      dnsServers: ['1.1.1.1', '1.0.0.1'],
      maxClients: 600,
      latencyMs: 25,
    },
    {
      name: 'Sydney, Australia',
      country: 'AU',
      city: 'Sydney',
      region: 'NSW',
      hostname: 'au-sy.geminivpn.com',
      port: 51820,
      publicKey: 'PLACEHOLDER_SY_PUBLIC_KEY',
      subnet: '10.8.7.0/24',
      dnsServers: ['1.1.1.1', '1.0.0.1'],
      maxClients: 500,
      latencyMs: 28,
    },
    {
      name: 'São Paulo, Brazil',
      country: 'BR',
      city: 'São Paulo',
      region: 'SP',
      hostname: 'br-sp.geminivpn.com',
      port: 51820,
      publicKey: 'PLACEHOLDER_SP_PUBLIC_KEY',
      subnet: '10.8.8.0/24',
      dnsServers: ['1.1.1.1', '1.0.0.1'],
      maxClients: 500,
      latencyMs: 35,
    },
    {
      name: 'Amsterdam, Netherlands',
      country: 'NL',
      city: 'Amsterdam',
      region: 'North Holland',
      hostname: 'nl-am.geminivpn.com',
      port: 51820,
      publicKey: 'PLACEHOLDER_AM_PUBLIC_KEY',
      subnet: '10.8.9.0/24',
      dnsServers: ['1.1.1.1', '1.0.0.1'],
      maxClients: 700,
      latencyMs: 16,
    },
    {
      name: 'Toronto, Canada',
      country: 'CA',
      city: 'Toronto',
      region: 'Ontario',
      hostname: 'ca-to.geminivpn.com',
      port: 51820,
      publicKey: 'PLACEHOLDER_TO_PUBLIC_KEY',
      subnet: '10.8.10.0/24',
      dnsServers: ['1.1.1.1', '1.0.0.1'],
      maxClients: 600,
      latencyMs: 14,
    },
  ];

  for (const serverData of servers) {
    const server = await prisma.vPNServer.upsert({
      where: { publicKey: serverData.publicKey },
      update: {},
      create: serverData,
    });
    console.log(`✅ Server created: ${server.name} (${server.country})`);
  }

  // Create system configuration
  const configs = [
    {
      key: 'TRIAL_DURATION_DAYS',
      value: '3',
      description: 'Duration of free trial in days',
    },
    {
      key: 'STRIPE_MONTHLY_PRICE_ID',
      value: 'price_placeholder_monthly',
      description: 'Stripe Price ID for monthly plan',
    },
    {
      key: 'STRIPE_YEARLY_PRICE_ID',
      value: 'price_placeholder_yearly',
      description: 'Stripe Price ID for yearly plan',
    },
    {
      key: 'STRIPE_TWO_YEAR_PRICE_ID',
      value: 'price_placeholder_two_year',
      description: 'Stripe Price ID for 2-year plan',
    },
    {
      key: 'WHATSAPP_SUPPORT_NUMBER',
      value: '+1234567890',
      description: 'WhatsApp support phone number',
    },
    {
      key: 'AUTO_REFRESH_INTERVAL_MS',
      value: '30000',
      description: 'Auto-refresh connection check interval in milliseconds',
    },
    {
      key: 'SELF_HEALING_ENABLED',
      value: 'true',
      description: 'Enable self-healing connection recovery',
    },
    {
      key: 'MAX_RECONNECT_ATTEMPTS',
      value: '5',
      description: 'Maximum reconnection attempts before giving up',
    },
  ];

  for (const config of configs) {
    await prisma.systemConfig.upsert({
      where: { key: config.key },
      update: {},
      create: config,
    });
    console.log(`✅ Config created: ${config.key}`);
  }

  console.log('\n✨ Database seed completed successfully!');
  console.log('\n📋 Test User Credentials:');
  console.log('   Email: alibasma');
  console.log('   Password: alibabaat2026');
  console.log('   Status: ACTIVE (Full Access)');
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
