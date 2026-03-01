#!/usr/bin/env bash
# =============================================================================
# GeminiVPN — Full Production Deployment Script
# Domain:  geminivpn.access.ly
# Server:  Ubuntu 22.04 LTS (any public IP)
# Author:  GeminiVPN DevOps
# =============================================================================
# USAGE:
#   sudo bash deploy-production.sh
#
# Run this once on a fresh Ubuntu 22.04 server.
# It installs all dependencies, gets Let's Encrypt SSL, builds the frontend,
# runs all containers, and sets up 24/7 systemd supervision.
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
err()  { echo -e "${RED}✗ $*${NC}"; exit 1; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
info() { echo -e "${BLUE}ℹ $*${NC}"; }
step() { echo -e "\n${CYAN}══ $* ══${NC}"; }

# ── Config ───────────────────────────────────────────────────────────────────
DOMAIN="geminivpn.access.ly"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@geminivpn.access.ly}"
PROJECT_DIR="/opt/geminivpn"
FRONTEND_DIST="$PROJECT_DIR/frontend_built"
NODE_VERSION="20"

# ── Guard ────────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Run as root: sudo bash $0"

# ── Banner ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}"
cat << 'BANNER'
  ╔══════════════════════════════════════════════════════╗
  ║        GeminiVPN — Production Deployment             ║
  ║        geminivpn.access.ly  · 24/7 Nginx            ║
  ╚══════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# =============================================================================
# STEP 1 — System update & base packages
# =============================================================================
step "1/10 — System Update"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip jq \
    apt-transport-https ca-certificates gnupg lsb-release \
    ufw fail2ban \
    software-properties-common \
    build-essential
ok "System packages installed"

# =============================================================================
# STEP 2 — Install Node.js 20
# =============================================================================
step "2/10 — Node.js $NODE_VERSION"
if ! command -v node &>/dev/null || [[ "$(node --version | cut -d. -f1 | tr -d 'v')" -lt "$NODE_VERSION" ]]; then
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
    apt-get install -y nodejs
fi
ok "Node $(node --version) / npm $(npm --version)"

# =============================================================================
# STEP 3 — Install Docker & Docker Compose
# =============================================================================
step "3/10 — Docker"
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | bash
fi
if ! command -v docker-compose &>/dev/null; then
    COMPOSE_VER=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi
systemctl enable docker --now
ok "Docker $(docker --version) / Compose $(docker-compose --version)"

# =============================================================================
# STEP 4 — Install WireGuard
# =============================================================================
step "4/10 — WireGuard"
apt-get install -y -qq wireguard wireguard-tools
# Enable IP forwarding permanently
grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
grep -qxF 'net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p -q
ok "WireGuard installed, IP forwarding enabled"

# =============================================================================
# STEP 5 — Firewall (UFW)
# =============================================================================
step "5/10 — Firewall (UFW)"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    comment 'SSH'
ufw allow 80/tcp    comment 'HTTP (Let'\''s Encrypt + redirect)'
ufw allow 443/tcp   comment 'HTTPS'
ufw allow 51820/udp comment 'WireGuard VPN'
# Enable fail2ban for SSH bruteforce protection
systemctl enable fail2ban --now
ufw --force enable
ok "Firewall configured: SSH 22, HTTP 80, HTTPS 443, WireGuard 51820/udp"

# =============================================================================
# STEP 6 — Deploy project files
# =============================================================================
step "6/10 — Project Setup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"

# Copy project to /opt/geminivpn
rsync -a --delete "$SOURCE_DIR/" "$PROJECT_DIR/" --exclude='.git' --exclude='node_modules'
chown -R root:root "$PROJECT_DIR"
ok "Project files deployed to $PROJECT_DIR"

# Create / load .env
ENV_FILE="$PROJECT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -f "$PROJECT_DIR/.env.example" ]]; then
        cp "$PROJECT_DIR/.env.example" "$ENV_FILE"

        # Auto-generate secrets
        JWT_ACCESS=$(openssl rand -base64 48 | tr -d '\n')
        JWT_REFRESH=$(openssl rand -base64 48 | tr -d '\n')
        DB_PASS=$(openssl rand -hex 24)
        REDIS_PASS=$(openssl rand -hex 16)

        sed -i "s|your_secure_database_password_here|$DB_PASS|g"   "$ENV_FILE"
        sed -i "s|your_secure_redis_password_here|$REDIS_PASS|g"   "$ENV_FILE"
        sed -i "s|your_jwt_access_secret_here_min_32_chars|$JWT_ACCESS|g" "$ENV_FILE"
        sed -i "s|your_jwt_refresh_secret_here_min_32_chars|$JWT_REFRESH|g" "$ENV_FILE"
        sed -i "s|geminivpn.com|$DOMAIN|g"                         "$ENV_FILE"

        warn ".env created with auto-generated secrets at $ENV_FILE"
        warn "Edit $ENV_FILE to add Stripe keys, SMTP, WireGuard key, WhatsApp number"
    else
        err ".env.example not found"
    fi
fi

# Source env for later use
set -a; source "$ENV_FILE"; set +a
ok ".env loaded"

# =============================================================================
# STEP 7 — Install certbot & get Let's Encrypt SSL
# =============================================================================
step "7/10 — Let's Encrypt SSL for $DOMAIN"
apt-get install -y -qq certbot

# Stop anything on port 80 temporarily so certbot standalone can bind
docker-compose -f "$PROJECT_DIR/docker/docker-compose.yml" down 2>/dev/null || true

if [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
    info "Obtaining certificate from Let's Encrypt (standalone mode)..."
    certbot certonly \
        --standalone \
        --agree-tos \
        --non-interactive \
        --email "$ADMIN_EMAIL" \
        -d "$DOMAIN" \
        -d "www.$DOMAIN" || {
        warn "www.$DOMAIN may not resolve — retrying with just $DOMAIN"
        certbot certonly \
            --standalone \
            --agree-tos \
            --non-interactive \
            --email "$ADMIN_EMAIL" \
            -d "$DOMAIN"
    }
fi

# Auto-renewal via systemd timer (preferred over cron on Ubuntu 22.04)
systemctl enable certbot.timer --now 2>/dev/null || true

# Post-renewal hook to reload nginx
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/geminivpn-reload.sh << 'HOOK'
#!/bin/bash
docker exec geminivpn-nginx nginx -s reload 2>/dev/null || true
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/geminivpn-reload.sh
ok "SSL certificate obtained and auto-renewal configured"

# =============================================================================
# STEP 8 — Build frontend
# =============================================================================
step "8/10 — Frontend Build"
cd "$PROJECT_DIR/frontend"
npm ci --prefer-offline 2>/dev/null || npm install
npm run build
mkdir -p "$FRONTEND_DIST"
cp -r dist/. "$FRONTEND_DIST/"
ok "Frontend built → $FRONTEND_DIST"

# Copy built files into named Docker volume
docker volume create geminivpn_frontend_dist 2>/dev/null || true
docker run --rm \
    -v geminivpn_frontend_dist:/dest \
    -v "$FRONTEND_DIST":/src:ro \
    alpine sh -c "cp -r /src/. /dest/"
ok "Frontend copied to Docker volume geminivpn_frontend_dist"

# =============================================================================
# STEP 9 — Generate WireGuard server keys (if not already set)
# =============================================================================
step "9/10 — WireGuard Keys"
WG_PRIVATE=$(grep -E '^WIREGUARD_SERVER_PRIVATE_KEY=' "$ENV_FILE" | cut -d= -f2 | tr -d '"')
if [[ -z "$WG_PRIVATE" || "$WG_PRIVATE" == "your_wireguard_server_private_key_here" ]]; then
    info "Generating WireGuard server key pair..."
    WG_PRIVATE=$(wg genkey)
    WG_PUBLIC=$(echo "$WG_PRIVATE" | wg pubkey)
    sed -i "s|^WIREGUARD_SERVER_PRIVATE_KEY=.*|WIREGUARD_SERVER_PRIVATE_KEY=$WG_PRIVATE|" "$ENV_FILE"
    ok "WireGuard private key set in .env"
    info "Server public key (needed for client configs): $WG_PUBLIC"
else
    ok "WireGuard key already configured"
fi

# =============================================================================
# STEP 10 — Start all containers
# =============================================================================
step "10/10 — Start Containers"
cd "$PROJECT_DIR/docker"

# Build backend image
docker-compose build --no-cache backend
ok "Backend image built"

# Start database first
docker-compose up -d postgres redis
info "Waiting for database (15s)..."
sleep 15

# Run Prisma migrations
docker-compose run --rm backend sh -c \
    "npx prisma migrate deploy && npx ts-node prisma/seed.ts" || \
    warn "Migration/seed may have already run — continuing"

# Start all services
docker-compose up -d
info "Waiting for services to be healthy (30s)..."
sleep 30

# Health check
if curl -sf "https://$DOMAIN/health" &>/dev/null; then
    ok "HTTPS health check passed ✓"
else
    warn "Health check at https://$DOMAIN/health not yet passing"
    info "Check logs: docker-compose -f $PROJECT_DIR/docker/docker-compose.yml logs"
fi

# =============================================================================
# SYSTEMD — Keep Docker Compose up on reboot
# =============================================================================
step "Systemd Service — 24/7 supervision"
cat > /etc/systemd/system/geminivpn.service << SVCEOF
[Unit]
Description=GeminiVPN Platform (Docker Compose)
After=network-online.target docker.service
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR/docker
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=/usr/local/bin/docker-compose up -d --remove-orphans
ExecStop=/usr/local/bin/docker-compose down
ExecReload=/usr/local/bin/docker-compose restart
TimeoutStartSec=180
TimeoutStopSec=60
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable geminivpn.service
ok "systemd service 'geminivpn' enabled (starts on boot)"

# =============================================================================
# LOGROTATE for Docker logs
# =============================================================================
cat > /etc/logrotate.d/geminivpn << 'LOGEOF'
/var/log/nginx/geminivpn-*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        docker exec geminivpn-nginx nginx -s reopen 2>/dev/null || true
    endscript
}
LOGEOF
ok "Log rotation configured (14 days)"

# =============================================================================
# SUMMARY
# =============================================================================
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "<your-server-ip>")
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}       GeminiVPN — Deployment Complete!${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}🌐 Domain:${NC}          https://$DOMAIN"
echo -e "${BLUE}🖥  Server IP:${NC}       $PUBLIC_IP"
echo -e "${BLUE}🔒 SSL:${NC}             Let's Encrypt (auto-renews)"
echo -e "${BLUE}🔑 WireGuard:${NC}       udp/$PUBLIC_IP:51820"
echo ""
echo -e "${BLUE}📋 DNS Records Required:${NC}"
echo "   A  $DOMAIN        → $PUBLIC_IP"
echo "   A  www.$DOMAIN    → $PUBLIC_IP"
echo ""
echo -e "${BLUE}🧪 Test Credentials:${NC}"
echo "   Email:    alibasma"
echo "   Password: alibabaat2026"
echo ""
echo -e "${BLUE}🛠  Useful Commands:${NC}"
echo "   View logs:       docker-compose -f $PROJECT_DIR/docker/docker-compose.yml logs -f"
echo "   Restart all:     systemctl restart geminivpn"
echo "   DB shell:        docker exec -it geminivpn-postgres psql -U geminivpn"
echo "   Redis CLI:       docker exec -it geminivpn-redis redis-cli -a \$REDIS_PASSWORD"
echo "   Nginx reload:    docker exec geminivpn-nginx nginx -s reload"
echo "   Update code:     cd $PROJECT_DIR && git pull && bash scripts/deploy-production.sh --update"
echo ""
echo -e "${YELLOW}⚠  Next Steps:${NC}"
echo "   1. Point DNS A records above to $PUBLIC_IP"
echo "   2. Edit $ENV_FILE — add Stripe keys, SMTP credentials"
echo "   3. Restart: systemctl restart geminivpn"
echo ""
