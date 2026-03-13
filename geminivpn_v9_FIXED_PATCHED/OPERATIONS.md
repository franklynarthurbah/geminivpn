# GeminiVPN — Operations Runbook

**Server**: geminivpn.zapto.org (167.172.96.225)  
**Stack**: Node.js/Express + PostgreSQL + Redis + nginx (Docker)

---

## Quick Reference

| Task | Command |
|------|---------|
| **Fix & redeploy everything** | `sudo bash scripts/fix-all.sh` |
| **Redeploy (keep data)** | `sudo bash scripts/redeploy.sh` |
| **Test all endpoints** | `sudo bash scripts/test-geminivpn.sh` |
| **Change any password** | `sudo bash scripts/change-admin-password.sh` |
| **Manage accounts** | `sudo bash scripts/account-manager.sh list` |
| **Build app binaries** | `sudo bash scripts/build-apps.sh all` |
| **Setup SSL (first time)** | `sudo bash scripts/setup-ssl.sh` |
| **View backend logs** | `docker logs geminivpn-backend -f` |
| **View nginx logs** | `docker logs geminivpn-nginx --tail=50` |

---

## Default Accounts

| Email | Password | Role |
|-------|----------|------|
| `admin@geminivpn.local` | `GeminiAdmin2026!` | Admin |
| `alibasma@geminivpn.local` | `alibabaat2026` | Test User (ACTIVE) |

⚠️ **Change the admin password immediately after first deploy:**
```bash
sudo bash scripts/change-admin-password.sh admin@geminivpn.local
```

---

## Pending Setup (requires your credentials)

### 1. Stripe Payments
```bash
nano /opt/geminivpn/.env
# Set:
STRIPE_SECRET_KEY=sk_live_...
STRIPE_PUBLISHABLE_KEY=pk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_MONTHLY_PRICE_ID=price_...
STRIPE_YEARLY_PRICE_ID=price_...
STRIPE_TWO_YEAR_PRICE_ID=price_...
# Then restart:
cd /opt/geminivpn/docker && docker compose restart backend
```

### 2. SMTP Email
```bash
nano /opt/geminivpn/.env
# Set:
SMTP_HOST=smtp.gmail.com        # or smtp.sendgrid.net etc.
SMTP_PORT=587
SMTP_USER=your@email.com
SMTP_PASS=your-app-password
# Then restart:
cd /opt/geminivpn/docker && docker compose restart backend
```

### 3. SSL Certificate (Let's Encrypt)
```bash
# Run ONCE after DNS is configured and pointing to this server:
sudo bash scripts/setup-ssl.sh geminivpn.zapto.org your@email.com
# This will:
# - Get a free 90-day cert from Let's Encrypt
# - Set up auto-renewal (twice daily via systemd)
# - Re-enable ssl_stapling in nginx.conf automatically
```

### 4. App Binaries (Android/Windows/Linux)
```bash
# Builds real installable apps (requires Docker + node):
sudo bash scripts/build-apps.sh all
# Individual platforms:
sudo bash scripts/build-apps.sh android
sudo bash scripts/build-apps.sh windows
sudo bash scripts/build-apps.sh linux
```

### 5. iOS App
See: `/var/www/geminivpn/downloads/iOS-Build-Instructions.txt`  
Requires macOS + Xcode — cannot be built on Linux.

---

## Monitoring

```bash
# Container health
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Backend logs (live)
docker logs geminivpn-backend -f

# nginx access log
docker logs geminivpn-nginx -f

# Database size
docker exec geminivpn-postgres psql -U geminivpn -c "\l+"

# Active users
docker exec geminivpn-postgres psql -U geminivpn -d geminivpn -c \
  "SELECT email, \"subscriptionStatus\", \"createdAt\" FROM \"User\" ORDER BY \"createdAt\" DESC LIMIT 20;"

# Connection logs
docker exec geminivpn-postgres psql -U geminivpn -d geminivpn -c \
  "SELECT * FROM \"ConnectionLog\" ORDER BY \"createdAt\" DESC LIMIT 20;"
```

---

## Troubleshooting

### Backend keeps restarting
```bash
docker logs geminivpn-backend --tail=50
# Then fix & rebuild with --no-cache:
sudo bash scripts/fix-all.sh
```

### nginx returns HTTP 000
```bash
docker logs geminivpn-nginx --tail=30
# Test config:
docker exec geminivpn-nginx nginx -t
```

### Login fails (valid credentials)
```bash
# Test directly:
curl -sk -X POST https://geminivpn.zapto.org/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@geminivpn.local","password":"GeminiAdmin2026!"}'
# If 401: reset password:
sudo bash scripts/change-admin-password.sh
```

### Database issues
```bash
# Re-run migrations + seed:
docker exec geminivpn-backend npx prisma@5.22.0 migrate deploy
docker exec geminivpn-backend npx prisma@5.22.0 db seed
```

---

## Architecture

```
Internet → nginx:443 (HTTPS, TLS 1.2/1.3)
              ├── /api/* → backend:5000 (Node.js/Express)
              │              ├── PostgreSQL (prisma ORM)
              │              └── Redis (sessions/cache)
              ├── /downloads/* → /var/www/geminivpn/downloads/
              └── /* → /var/www/geminivpn/ (React SPA)
```

All containers: `geminivpn-network` bridge  
Data volumes: `postgres_data`, `redis_data`, `wireguard_configs`
