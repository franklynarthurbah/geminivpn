#!/usr/bin/env bash
# =============================================================================
# GeminiVPN — Let's Encrypt SSL Setup + 24/7 Auto-Renewal
# Hostname: geminivpn.zapto.org  (No-IP DDNS — no www subdomain)
#
# Usage: sudo bash scripts/setup-ssl.sh [domain] [email]
#   sudo bash scripts/setup-ssl.sh geminivpn.zapto.org admin@geminivpn.zapto.org
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[→]${NC} $1"; }

[[ $EUID -ne 0 ]] && fail "Run as root: sudo bash $0"

DOMAIN="${1:-geminivpn.zapto.org}"
EMAIL="${2:-}"

if [[ -z "$EMAIL" ]]; then
  read -rp "  Email for SSL cert notifications: " EMAIL
fi

echo ""
echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   GeminiVPN — Let's Encrypt SSL + Auto-Renewal   ║${NC}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
info "Domain : $DOMAIN"
info "Email  : $EMAIL"
echo ""

# ── 1. Verify DNS resolves to this server ─────────────────────────────────────
info "Checking DNS resolution..."
SERVER_IP=$(curl -s --max-time 8 ifconfig.me 2>/dev/null || \
            curl -s --max-time 8 api.ipify.org 2>/dev/null || echo "")
RESOLVED=$(dig +short "$DOMAIN" 2>/dev/null | grep -E '^[0-9]+\.' | tail -1 || echo "")

if [[ -z "$RESOLVED" ]]; then
  warn "DNS for $DOMAIN does not resolve yet."
  warn "Make sure your No-IP hostname is set to: $SERVER_IP"
  warn "Waiting up to 60 seconds for DNS..."
  for i in $(seq 1 12); do
    sleep 5
    RESOLVED=$(dig +short "$DOMAIN" 2>/dev/null | grep -E '^[0-9]+\.' | tail -1 || echo "")
    [[ -n "$RESOLVED" ]] && break
    echo "  Still waiting... ($((i*5))s)"
  done
fi

if [[ -n "$RESOLVED" && "$RESOLVED" == "$SERVER_IP" ]]; then
  ok "DNS verified: $DOMAIN → $RESOLVED"
elif [[ -n "$RESOLVED" ]]; then
  warn "DNS resolves to $RESOLVED but this server is $SERVER_IP"
  warn "Proceeding anyway — Let's Encrypt will validate via HTTP challenge"
else
  fail "DNS for $DOMAIN is not resolving. Configure No-IP first then re-run."
fi

# ── 2. Install certbot ────────────────────────────────────────────────────────
info "Installing certbot..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>/dev/null
apt-get install -y -qq certbot dnsutils 2>/dev/null
ok "certbot installed: $(certbot --version 2>&1 | head -1)"

# ── 3. Check if cert already exists ──────────────────────────────────────────
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
if [[ -f "$CERT_PATH" ]]; then
  DAYS=$(( ( $(date -d "$(openssl x509 -noout -enddate -in "$CERT_PATH" | cut -d= -f2)" +%s) - $(date +%s) ) / 86400 ))
  if [[ $DAYS -gt 30 ]]; then
    ok "Certificate already exists and is valid for $DAYS more days — skipping issuance"
    info "To force renewal: certbot renew --force-renewal"
    CERT_ISSUED=true
  else
    warn "Certificate expires in $DAYS days — renewing..."
    CERT_ISSUED=false
  fi
else
  CERT_ISSUED=false
fi

# ── 4. Stop nginx (port 80 must be free for standalone challenge) ─────────────
if [[ "$CERT_ISSUED" != "true" ]]; then
  info "Stopping nginx to free port 80 for HTTP challenge..."
  docker stop geminivpn-nginx 2>/dev/null || true
  # Also kill anything else on port 80
  fuser -k 80/tcp 2>/dev/null || true
  sleep 2

  # ── 5. Obtain certificate ───────────────────────────────────────────────────
  # NOTE: No -d www.$DOMAIN — No-IP DDNS free accounts don't have a www record.
  # Requesting www will cause certbot to fail even if the main record works.
  info "Requesting Let's Encrypt certificate for $DOMAIN ..."
  certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --preferred-challenges http-01 \
    -d "$DOMAIN" \
    2>&1

  CERT_EXIT=$?
  if [[ $CERT_EXIT -eq 0 ]]; then
    ok "Certificate obtained successfully!"
    CERT_ISSUED=true
  else
    fail "certbot failed. Check: 1) DNS resolves to this server, 2) port 80 is open, 3) No-IP hostname is registered"
  fi

  # ── 6. Restart nginx ─────────────────────────────────────────────────────────
  info "Restarting nginx..."
  docker start geminivpn-nginx 2>/dev/null || true
  sleep 3
  docker exec geminivpn-nginx nginx -s reload 2>/dev/null || true
  ok "nginx restarted"
fi

# ── 7. Install 24/7 automatic renewal cron (Let's Encrypt certs expire 90d) ──
info "Setting up 24/7 automatic SSL renewal..."

# Create renewal hook that gracefully reloads nginx after renewal
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh << 'HOOKEOF'
#!/bin/bash
# Called by certbot after each successful renewal
# Reloads nginx inside Docker without downtime
echo "[$(date)] SSL cert renewed — reloading nginx" >> /var/log/letsencrypt-renewal.log
docker exec geminivpn-nginx nginx -s reload 2>/dev/null || \
  docker restart geminivpn-nginx 2>/dev/null || true
echo "[$(date)] nginx reloaded OK" >> /var/log/letsencrypt-renewal.log
HOOKEOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

# Create pre-hook: free port 80 before standalone renewal (if needed)
# NOTE: We use webroot method for renewal so nginx stays up
# First check if certbot can use webroot (preferred — zero downtime)
mkdir -p /var/www/certbot

# Update the renewal config to use webroot (no downtime) instead of standalone
RENEWAL_CONF="/etc/letsencrypt/renewal/${DOMAIN}.conf"
if [[ -f "$RENEWAL_CONF" ]]; then
  # Switch to webroot authenticator for renewals (keeps nginx running)
  sed -i 's/^authenticator = standalone/authenticator = webroot/' "$RENEWAL_CONF" 2>/dev/null || true
  if ! grep -q "webroot_path" "$RENEWAL_CONF"; then
    echo "webroot_path = /var/www/certbot" >> "$RENEWAL_CONF"
  fi
  ok "Renewal configured to use webroot (zero-downtime renewals)"
fi

# Create systemd timer for twice-daily renewal attempts (recommended by LE)
cat > /etc/systemd/system/certbot-renew.service << 'SVCEOF'
[Unit]
Description=Certbot Renewal — GeminiVPN SSL
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --no-self-upgrade
ExecStartPost=/bin/bash -c 'docker exec geminivpn-nginx nginx -s reload 2>/dev/null || true'
StandardOutput=journal
StandardError=journal
SVCEOF

cat > /etc/systemd/system/certbot-renew.timer << 'TIMEREOF'
[Unit]
Description=Certbot SSL auto-renewal — twice daily
After=network-online.target

[Timer]
# Run at 3:00 AM and 3:00 PM daily (staggered to avoid LE rate limit peaks)
OnCalendar=*-*-* 03:00:00
OnCalendar=*-*-* 15:00:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now certbot-renew.timer
ok "Auto-renewal timer enabled (runs twice daily, certs renew when <30 days left)"

# Test renewal in dry-run mode
info "Testing renewal configuration (dry run)..."
certbot renew --dry-run --quiet 2>&1 && ok "Dry-run renewal: PASSED" || \
  warn "Dry-run had a warning — check: certbot renew --dry-run"

# ── 8. Summary ────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✓  SSL Certificate Setup Complete!${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
echo "  Domain   : $DOMAIN"
echo "  Cert     : $CERT_PATH"
EXPIRY=$(openssl x509 -noout -enddate -in "$CERT_PATH" 2>/dev/null | cut -d= -f2 || echo "unknown")
echo "  Expires  : $EXPIRY"
echo "  Renewal  : Automatic (systemd timer, twice daily)"
echo "  Log      : /var/log/letsencrypt-renewal.log"
echo ""
echo "  Commands:"
echo "    certbot renew --dry-run           # test renewal"
echo "    systemctl status certbot-renew.timer  # check timer"
echo "    openssl x509 -noout -enddate -in $CERT_PATH"
echo ""
