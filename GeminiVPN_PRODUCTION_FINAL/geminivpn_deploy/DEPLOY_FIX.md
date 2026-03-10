# GeminiVPN — Seed / Migration Deployment Fix

## Root Causes

### 1. `dist/prisma/seed.js` was never compiled
`tsconfig.json` has `rootDir: "./src"`, which tells the TypeScript compiler
to only process files under `src/`. Because `prisma/seed.ts` lives *outside*
`src/`, it was silently skipped, so `dist/prisma/seed.js` never existed in
the container.

**Fix applied:** Added `backend/tsconfig.seed.json` with `rootDir: "./prisma"`
and `outDir: "./dist/prisma"`. The Dockerfile builder stage now runs this
config after the main `tsc` build, with a TypeScript-API fallback to ensure
it always succeeds.

### 2. No Prisma migrations existed
`prisma migrate deploy` reported "No migration found in prisma/migrations"
because the `migrations/` directory was completely absent. Without a migration,
Prisma never created the database schema.

**Fix applied:** Created `backend/prisma/migrations/20240101000000_init/migration.sql`
containing the full DDL for every table, enum, index, and foreign key defined
in `schema.prisma`.

---

## Files Changed

| File | Change |
|------|--------|
| `backend/tsconfig.seed.json` | **NEW** — separate tsconfig for seed compilation |
| `backend/prisma/migrations/20240101000000_init/migration.sql` | **NEW** — initial DB schema migration |
| `docker/Dockerfile.backend` | **UPDATED** — added seed compilation step in builder stage |

---

## Deployment Steps

### Step 1 — Rebuild the Docker image
```bash
cd /opt/geminivpn_final/docker
docker compose build --no-cache backend
```

### Step 2 — Restart the backend container
```bash
docker compose up -d backend
```

### Step 3 — Apply migrations (creates all tables)
```bash
docker exec geminivpn-backend npx prisma@5.22.0 migrate deploy
```
Expected output:
```
Prisma schema loaded from prisma/schema.prisma
Datasource "db": PostgreSQL database "geminivpn" ...
1 migration found in prisma/migrations.
Applying migration `20240101000000_init`
The following migration(s) have been applied:
migrations/
  └─ 20240101000000_init/
       └─ migration.sql
```

### Step 4 — Seed the database
```bash
docker exec geminivpn-backend node dist/prisma/seed.js
```
Expected output:
```
🌱 Starting database seed...
✅ Test user: alibasma@geminivpn.local (password: alibabaat2026)
✅ Server: New York, USA
✅ Server: Los Angeles, USA
... (10 servers total)
✅ Config: TRIAL_DURATION_DAYS = 3
... (6 configs total)
✨ Seed completed!
```

### Step 5 — Verify (optional)
```bash
# Confirm seed.js exists in the container
docker exec geminivpn-backend ls -la dist/prisma/seed.js

# Confirm DB tables exist
docker exec geminivpn-postgres psql -U geminivpn -d geminivpn \
  -c "\dt" 2>/dev/null
```

---

## Test Credentials (seeded)
| Field    | Value                      |
|----------|----------------------------|
| Email    | alibasma@geminivpn.local   |
| Password | alibabaat2026              |
| Status   | ACTIVE (expires 2030-12-31)|
