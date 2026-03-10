#!/usr/bin/env bash
# =============================================================================
# GeminiVPN -- Domain Setup Script
# Run ONCE after cloning on your server:  sudo bash scripts/setup-domain.sh
# =============================================================================
set -euo pipefail

# -- Always run relative to the project root, not the script's directory -------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()  { printf "${GREEN}[+]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
err()  { printf "${RED}[x]${NC} %s\n"   "$1"; exit 1; }

printf "${CYAN}%s${NC}\n" "=========================================="
printf "${CYAN}%s${NC}\n" "  GeminiVPN Domain Configuration Setup   "
printf "${CYAN}%s${NC}\n" "=========================================="
echo ""

# -- 1. Get domain name ---------------------------------------------------------
EXISTING=""
if [[ -f .env ]]; then
  EXISTING=$(grep '^FRONTEND_URL=' .env | cut -d= -f2 | sed 's|https\?://||' | sed 's|/.*||' || true)
fi

read -rp "Enter your domain (e.g. myvpn.ddns.net or geminivpn.zapto.org): " DOMAIN
DOMAIN="${DOMAIN:-${EXISTING:-localhost}}"
DOMAIN="${DOMAIN#http*://}"
echo ""

if [[ -z "$DOMAIN" || "$DOMAIN" == "localhost" ]]; then
  warn "No domain entered; defaulting to localhost."
fi

# -- 2. Get server public IP ----------------------------------------------------
DETECTED_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "0.0.0.0")
read -rp "Enter server public IP [$DETECTED_IP]: " SERVER_IP
SERVER_IP="${SERVER_IP:-$DETECTED_IP}"

# -- 3. Patch nginx.conf --------------------------------------------------------
NGINX_CONF="docker/nginx/nginx.conf"
if [[ -f "$NGINX_CONF" ]]; then
  # Replace DOMAIN_PLACEHOLDER (fresh clone) OR baked-in domain (updated package)
  sed -i "s|DOMAIN_PLACEHOLDER|$DOMAIN|g"          "$NGINX_CONF"
  sed -i "s|geminivpn\.zapto\.org|$DOMAIN|g"       "$NGINX_CONF"
  log "Patched $NGINX_CONF with domain: $DOMAIN"
else
  warn "$NGINX_CONF not found -- skipping nginx patch."
fi

# -- 4. Patch .env --------------------------------------------------------------
if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
    log "Created .env from .env.example"
  elif [[ -f backend/.env.example ]]; then
    cp backend/.env.example .env
    log "Created .env from backend/.env.example"
  else
    cat > .env <<EOF
FRONTEND_URL=https://$DOMAIN
SERVER_PUBLIC_IP=$SERVER_IP
JWT_ACCESS_SECRET=CHANGE_ME_generate_with_openssl_rand_base64_48
JWT_REFRESH_SECRET=CHANGE_ME_generate_with_openssl_rand_base64_48
EOF
    log "No .env.example found -- created minimal .env"
  fi
fi

# Generate JWT secrets if placeholders are still present
if grep -q 'CHANGE_ME_generate_with_openssl' .env 2>/dev/null; then
  ACCESS_SECRET=$(openssl rand -base64 48)
  REFRESH_SECRET=$(openssl rand -base64 48)
  sed -i "s|CHANGE_ME_generate_with_openssl_rand_base64_48|$ACCESS_SECRET|1" .env
  sed -i "s|CHANGE_ME_generate_with_openssl_rand_base64_48|$REFRESH_SECRET|1" .env
  log "Generated JWT secrets"
fi

# Set domain and IP in .env
if grep -q '^FRONTEND_URL=' .env; then
  sed -i "s|FRONTEND_URL=.*|FRONTEND_URL=https://$DOMAIN|" .env
else
  echo "FRONTEND_URL=https://$DOMAIN" >> .env
fi

if grep -q '^SERVER_PUBLIC_IP=' .env; then
  sed -i "s|SERVER_PUBLIC_IP=.*|SERVER_PUBLIC_IP=$SERVER_IP|" .env
else
  echo "SERVER_PUBLIC_IP=$SERVER_IP" >> .env
fi

log "Updated .env  ->  FRONTEND_URL=https://$DOMAIN  SERVER_PUBLIC_IP=$SERVER_IP"

# -- 5. Create required host directories ---------------------------------------
mkdir -p /var/www/geminivpn/downloads
mkdir -p /var/www/certbot
mkdir -p /var/log/geminivpn
log "Created required directories"

# -- 6. Copy frontend dist ------------------------------------------------------
if [[ -d frontend/dist ]]; then
  cp -r frontend/dist/. /var/www/geminivpn/
  log "Copied frontend dist to /var/www/geminivpn/"
else
  warn "frontend/dist not found -- run:  cd frontend && npm install && npm run build && cp -r dist/. /var/www/geminivpn/"
fi

# -- 7. Copy download files if present -----------------------------------------
if [[ -d downloads ]] && compgen -G "downloads/*" > /dev/null 2>&1; then
  cp -r downloads/. /var/www/geminivpn/downloads/
  log "Copied downloads to /var/www/geminivpn/downloads/"
fi

# -- 8. Summary -----------------------------------------------------------------
echo ""
printf "${CYAN}%s${NC}\n" "=========================================="
printf "${GREEN}%s${NC}\n" "  Setup complete!"
printf "${CYAN}%s${NC}\n" "=========================================="
echo ""
echo "  Domain:    $DOMAIN"
echo "  Server IP: $SERVER_IP"
echo ""
printf "${YELLOW}Next steps:${NC}\n"
echo "  1. Get SSL cert:    sudo bash scripts/setup-ssl.sh $DOMAIN"
echo "  2. Start stack:     docker compose -f docker/docker-compose.yml --env-file .env up -d"
echo "  3. Run migrations:  docker exec geminivpn-backend npx prisma@5.22.0 migrate deploy"
echo "  4. Seed database:   docker exec geminivpn-backend node dist/prisma/seed.js"
echo "  5. Visit:           https://$DOMAIN"
echo ""
