# GeminiVPN — Post-Deploy Quick Start Guide

> **Status:** Emergency fix applied (v3). All containers healthy. Site is live.  
> **URL:** https://geminivpn.zapto.org  
> **Server:** DigitalOcean Ubuntu 24.04 · 167.172.96.225

---

## ✅ Already Done (by fix-all.sh)

| Task | Status |
|------|--------|
| nginx crash fix (duplicate types{} block) | ✅ Done |
| nginx ssl_stapling fix (self-signed cert) | ✅ Done |
| Node.js crash fix (circular import) | ✅ Done |
| Docker cache busted (–no-cache rebuild) | ✅ Done |
| Frontend built & deployed | ✅ Done |
| Database migrated + seeded | ✅ Done |
| Admin account created | ✅ Done |
| Test account created | ✅ Done |
| WhatsApp Live Chat wired (+905368895622) | ✅ Done |

---

## 🔲 Remaining Tasks (in order)

### 1. Harden the Server  
```bash
sudo bash scripts/tune-host.sh
```
**What it does:** UFW firewall, fail2ban brute-force protection, 2GB swap, BBR kernel tuning, Docker log rotation, auto security updates, SSH key-only auth.  
**Run once, safe to re-run.**

---

### 2. Get a Real SSL Certificate  
```bash
sudo bash scripts/setup-ssl.sh geminivpn.zapto.org your@email.com
```
**What it does:**  
- Verifies DNS resolves to this server  
- Obtains Let's Encrypt cert via HTTP-01 challenge  
- Configures zero-downtime auto-renewal (systemd timer, twice daily)  
- Automatically re-enables `ssl_stapling` in nginx.conf  
- Tests dry-run renewal  

**Prerequisites:** Port 80 must be publicly reachable. The No-IP DDNS hostname must point to `167.172.96.225`.

---

### 3. Configure Stripe Payments  
```bash
sudo bash scripts/setup-stripe.sh
```
**What it does:**  
- Prompts for Stripe secret + publishable keys  
- Creates 3 products in your Stripe dashboard (Monthly $11.99, 1-Year $4.99/mo, 2-Year $3.49/mo)  
- Creates webhook endpoint for `geminivpn.zapto.org`  
- Updates `/opt/geminivpn/.env` with all price IDs  
- Restarts backend + verifies health  

**Get keys from:** https://dashboard.stripe.com/apikeys  
Use `sk_test_` keys for testing, `sk_live_` for production.

---

### 4. Configure Email (SMTP)  
```bash
sudo bash scripts/setup-smtp.sh
```
**What it does:**  
- Lets you choose: Gmail / Zoho / Outlook / SendGrid / Mailgun / Custom  
- Sends a test email to confirm delivery  
- Updates `.env` with SMTP credentials  
- Restarts backend  

**Recommended free options:**
- **Gmail:** Use an App Password — https://myaccount.google.com/apppasswords
- **Zoho:** Free plan, 200/day, supports custom sender domains
- **SendGrid:** 100/day free, best deliverability

---

### 5. Change Admin Password  
```bash
sudo bash scripts/change-admin-password.sh admin@geminivpn.local
```
Or from the web UI: Login → Profile → Change Password.

---

### 6. Build Real App Binaries  
```bash
sudo bash scripts/build-apps.sh all
```
**Builds:** Android APK, Windows EXE, Linux AppImage + DEB  
**Requires:** Node.js + Android SDK (Docker image) for full builds. Falls back to placeholder files if unavailable.

**iOS (requires macOS + Xcode):**  
See `downloads/iOS-Build-Instructions.txt` for step-by-step Xcode build guide.

---

## 👤 Account Management

```bash
# List all users
sudo bash scripts/account-manager.sh list

# Create a new user account
sudo bash scripts/account-manager.sh create

# Set a user to ACTIVE subscription
sudo bash scripts/account-manager.sh set-active user@email.com

# Reset a user's password
sudo bash scripts/account-manager.sh reset-pass user@email.com NewPassword123

# View stats
sudo bash scripts/account-manager.sh stats
```

---

## 🧪 Test Accounts

| Email | Password | Status |
|-------|----------|--------|
| `admin@geminivpn.local` | `GeminiAdmin2026!` | ACTIVE (expires 2099) |
| `alibasma@geminivpn.local` | `alibabaat2026` | ACTIVE (expires 2030) |

---

## 🔧 Common Operations

```bash
# Full re-deploy (after any source changes)
sudo bash scripts/fix-all.sh

# Run test suite (32 tests)
sudo bash scripts/test-geminivpn.sh

# View live container logs
docker logs geminivpn-backend -f --tail=50
docker logs geminivpn-nginx -f --tail=50

# Restart a specific container
cd /opt/geminivpn/docker
docker compose --env-file /opt/geminivpn/.env restart backend

# Check container health
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Run Prisma migrations after schema changes
docker exec geminivpn-backend npx prisma@5.22.0 migrate deploy

# Access the database directly
docker exec -it geminivpn-postgres psql -U geminivpn -d geminivpn
```

---

## 📁 File Locations

| Purpose | Path |
|---------|------|
| Environment config | `/opt/geminivpn/.env` |
| nginx config | `/opt/geminivpn/docker/nginx/nginx.conf` |
| Frontend files | `/var/www/geminivpn/` |
| App downloads | `/var/www/geminivpn/downloads/` |
| Server logs | `/var/log/geminivpn/` |
| SSL certificate | `/etc/letsencrypt/live/geminivpn.zapto.org/` |
| SSL auto-renewal log | `/var/log/letsencrypt-renewal.log` |
| Docker compose | `/opt/geminivpn/docker/docker-compose.yml` |

---

## 🚨 Emergency Recovery

If the site goes down:

```bash
# 1. Check what's broken
docker ps -a
docker logs geminivpn-backend --tail=40

# 2. Nuclear option — full re-deploy from source
cd ~/GeminiVPN_FIX_v3/geminivpn_deploy
sudo bash scripts/fix-all.sh

# 3. Just restart services (if config is fine)
cd /opt/geminivpn/docker
docker compose --env-file /opt/geminivpn/.env down
docker compose --env-file /opt/geminivpn/.env up -d
```

---

## 📞 Support Contacts

- **WhatsApp:** https://wa.me/905368895622
- **Email:** support@geminivpn.zapto.org
- **Site:** https://geminivpn.zapto.org
