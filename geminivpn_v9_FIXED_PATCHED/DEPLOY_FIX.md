# GeminiVPN v5 — SQLite Edition (No Redis · No PostgreSQL)

## What Changed from v4

| Before (v4)                         | After (v5 SQLite)                      |
|-------------------------------------|----------------------------------------|
| PostgreSQL container required        | ❌ Removed — no DB server needed        |
| Redis container required            | ❌ Removed — no cache server needed     |
| DB auth errors (P1000)              | ✅ Fixed — SQLite never has auth errors |
| geminivpn.sh installer              | ❌ Removed — use re-geminivpn.sh only   |
| `database/` directory               | ✅ Added — holds geminivpn.db           |
| 4 Docker containers                 | ✅ 2 containers (backend + nginx)       |
| DB connection retries (30s each)    | ✅ SQLite opens instantly               |

## Database Storage

All data is stored in `./database/geminivpn.db` (SQLite file).

- **Host path:** `/opt/geminivpn/database/geminivpn.db`
- **Container path:** `/app/database/geminivpn.db`
- **Backup:** `sudo bash re-geminivpn.sh --backup`
- **Restore:** `sudo bash re-geminivpn.sh --restore`
- **Daily auto-backup:** Installed to `/etc/cron.daily/geminivpn-db-backup`

## Quick Start

```bash
sudo bash re-geminivpn.sh
```

## Modes

```
--ssl        Set up / renew Let's Encrypt SSL
--stripe     Configure Stripe payments
--payment    Configure Square · Paddle · Coinbase
--smtp       Configure email
--test       Run full test suite
--harden     Apply server hardening
--status     Show container + SSL + payment status
--whatsapp   Update WhatsApp support number
--noip       Setup No-IP Dynamic DNS
--app        Build all apps (APK, EXE, DMG, iOS, Router)
--backup     Backup SQLite database
--restore    Restore SQLite database from backup
```

## Why SQLite?

- **Zero credentials** — no username/password to misconfigure
- **Zero containers** — fewer moving parts, easier to debug
- **Instant startup** — no 30-second DB connection retries
- **Easy backup** — just copy a single file
- **Sufficient for production** — handles thousands of VPN users

## Troubleshooting

```bash
# View logs
docker logs geminivpn-backend -f --tail=50

# Check database
sqlite3 /opt/geminivpn/database/geminivpn.db ".tables"

# Manual schema push
docker exec geminivpn-backend \
  sh -c "DATABASE_URL=file:/app/database/geminivpn.db npx prisma@5.22.0 db push --schema=/app/prisma/schema.prisma"

# Only 2 containers should be running:
docker ps | grep geminivpn
# geminivpn-backend
# geminivpn-nginx
```
