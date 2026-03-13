/**
 * GeminiVPN Database Seeder
 *
 * NOTE: SQLite (Prisma 5.x) does not support enum types.
 * All status/type fields are plain strings — values are defined
 * as constants in src/lib/enums.ts and used as literals here.
 */
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

// ── Enum string literals (SQLite: no Prisma enum support) ───────────────────
const STATUS_ACTIVE   = 'ACTIVE';
const STATUS_TRIAL    = 'TRIAL';

async function main() {
  console.log('🌱 Starting database seed...\n');

  // ── Admin user ─────────────────────────────────────────────────────────────
  const adminPassword = await bcrypt.hash('GeminiAdmin2026!', 12);
  const adminUser = await prisma.user.upsert({
    where:  { email: 'admin@geminivpn.local' },
    update: {},
    create: {
      email:              'admin@geminivpn.local',
      password:           adminPassword,
      name:               'GeminiVPN Admin',
      subscriptionStatus: STATUS_ACTIVE,
      isTestUser:         false,
      emailVerified:      true,
      subscriptionEndsAt: new Date('2099-12-31T23:59:59Z'),
      lastLoginAt:        new Date(),
    },
  });
  console.log('✅ Admin user:', adminUser.email, '(password: GeminiAdmin2026!)');

  // ── Test user ──────────────────────────────────────────────────────────────
  const testPassword = await bcrypt.hash('alibabaat2026', 12);
  const testUser = await prisma.user.upsert({
    where:  { email: 'alibasma@geminivpn.local' },
    update: {},
    create: {
      email:              'alibasma@geminivpn.local',
      password:           testPassword,
      name:               'Ali Basma (Test User)',
      subscriptionStatus: STATUS_ACTIVE,
      isTestUser:         true,
      emailVerified:      true,
      subscriptionEndsAt: new Date('2030-12-31T23:59:59Z'),
      lastLoginAt:        new Date(),
    },
  });
  console.log('✅ Test user:', testUser.email, '(password: alibabaat2026)');

  // ── VPN Servers ────────────────────────────────────────────────────────────
  const servers = [
    { name: 'New York, USA',          country: 'US', city: 'New York',    region: 'NY',            hostname: 'us-ny.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_NY_PUBLIC_KEY', subnet: '10.8.1.0/24',  dnsServers: '1.1.1.1,1.0.0.1', maxClients: 1000, latencyMs: 9  },
    { name: 'Los Angeles, USA',       country: 'US', city: 'Los Angeles', region: 'CA',            hostname: 'us-la.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_LA_PUBLIC_KEY', subnet: '10.8.2.0/24',  dnsServers: '1.1.1.1,1.0.0.1', maxClients: 1000, latencyMs: 12 },
    { name: 'London, UK',             country: 'GB', city: 'London',      region: 'England',       hostname: 'uk-ln.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_LN_PUBLIC_KEY', subnet: '10.8.3.0/24',  dnsServers: '1.1.1.1,1.0.0.1', maxClients: 800,  latencyMs: 15 },
    { name: 'Frankfurt, Germany',     country: 'DE', city: 'Frankfurt',   region: 'Hesse',         hostname: 'de-fr.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_FR_PUBLIC_KEY', subnet: '10.8.4.0/24',  dnsServers: '1.1.1.1,1.0.0.1', maxClients: 800,  latencyMs: 18 },
    { name: 'Tokyo, Japan',           country: 'JP', city: 'Tokyo',       region: 'Tokyo',         hostname: 'jp-tk.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_TK_PUBLIC_KEY', subnet: '10.8.5.0/24',  dnsServers: '1.1.1.1,1.0.0.1', maxClients: 600,  latencyMs: 22 },
    { name: 'Singapore',              country: 'SG', city: 'Singapore',   region: 'Singapore',     hostname: 'sg-sg.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_SG_PUBLIC_KEY', subnet: '10.8.6.0/24',  dnsServers: '1.1.1.1,1.0.0.1', maxClients: 600,  latencyMs: 25 },
    { name: 'Sydney, Australia',      country: 'AU', city: 'Sydney',      region: 'NSW',           hostname: 'au-sy.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_SY_PUBLIC_KEY', subnet: '10.8.7.0/24',  dnsServers: '1.1.1.1,1.0.0.1', maxClients: 500,  latencyMs: 28 },
    { name: 'São Paulo, Brazil',      country: 'BR', city: 'São Paulo',   region: 'SP',            hostname: 'br-sp.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_SP_PUBLIC_KEY', subnet: '10.8.8.0/24',  dnsServers: '1.1.1.1,1.0.0.1', maxClients: 500,  latencyMs: 35 },
    { name: 'Paris, France',          country: 'FR', city: 'Paris',       region: 'Île-de-France', hostname: 'fr-pa.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_PA_PUBLIC_KEY', subnet: '10.8.11.0/24', dnsServers: '1.1.1.1,1.0.0.1', maxClients: 700,  latencyMs: 16 },
    { name: 'Amsterdam, Netherlands', country: 'NL', city: 'Amsterdam',   region: 'N. Holland',    hostname: 'nl-am.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_AM_PUBLIC_KEY', subnet: '10.8.9.0/24',  dnsServers: '1.1.1.1,1.0.0.1', maxClients: 700,  latencyMs: 14 },
    { name: 'Toronto, Canada',        country: 'CA', city: 'Toronto',     region: 'Ontario',       hostname: 'ca-to.geminivpn.com', port: 51820, publicKey: 'PLACEHOLDER_TO_PUBLIC_KEY', subnet: '10.8.10.0/24', dnsServers: '1.1.1.1,1.0.0.1', maxClients: 600,  latencyMs: 11 },
  ];

  for (const s of servers) {
    await prisma.vPNServer.upsert({
      where:  { hostname: s.hostname },
      update: { latencyMs: s.latencyMs, maxClients: s.maxClients },
      create: s,
    });
    console.log(`✅ Server: ${s.name}`);
  }

  // ── System config ──────────────────────────────────────────────────────────
  const configs = [
    { key: 'TRIAL_DURATION_DAYS',      value: '3',             description: 'Duration of free trial in days'             },
    { key: 'MAX_DEVICES_PER_USER',     value: '10',            description: 'Maximum devices per user account'           },
    { key: 'WHATSAPP_SUPPORT_NUMBER',  value: '+905368895622', description: 'WhatsApp support phone number'              },
    { key: 'AUTO_REFRESH_INTERVAL_MS', value: '30000',         description: 'Connection check interval in milliseconds'  },
    { key: 'SELF_HEALING_ENABLED',     value: 'true',          description: 'Enable self-healing connection recovery'    },
    { key: 'MAX_RECONNECT_ATTEMPTS',   value: '5',             description: 'Max reconnection attempts before giving up' },
  ];
  for (const c of configs) {
    await prisma.systemConfig.upsert({ where: { key: c.key }, update: {}, create: c });
    console.log(`✅ Config: ${c.key} = ${c.value}`);
  }

  console.log('\n✨ Seed completed!');
  console.log('\n📋 Credentials:');
  console.log('   Admin:    admin@geminivpn.local  /  GeminiAdmin2026!');
  console.log('   Test:     alibasma@geminivpn.local  /  alibabaat2026');
}

main()
  .catch((e) => { console.error('❌ Seed failed:', e); process.exit(1); })
  .finally(() => prisma.$disconnect());
