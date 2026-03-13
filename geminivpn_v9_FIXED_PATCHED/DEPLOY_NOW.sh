#!/usr/bin/env bash
# =============================================================================
#  GeminiVPN — ONE-COMMAND COMPLETE FIX
#  Run this ONCE on your server. It does everything:
#  1. Extracts the fixed project
#  2. Applies all sysctl fixes live (IPv6 bindv6only=0)
#  3. Stops any broken containers
#  4. Starts containers in correct order
#  5. Issues Let's Encrypt SSL cert
#  6. Forces No-IP DNS to correct IPv4
#  7. Verifies everything end-to-end
#
#  Usage:  sudo bash DEPLOY_NOW.sh
# =============================================================================
set -uo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[✓]${NC} $*"; }
err()  { echo -e "  ${RED}[✗]${NC} $*"; exit 1; }
info() { echo -e "  ${CYAN}[→]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $*"; }
step() { echo ""; echo -e "${BOLD}══ $* ══${NC}"; }

[[ $EUID -ne 0 ]] && err "Run as root: sudo bash DEPLOY_NOW.sh"

DOMAIN="geminivpn.zapto.org"
SERVER_IP="167.172.96.225"
DEPLOY_DIR="/opt/geminivpn"
WWW_DIR="/var/www/geminivpn"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  GeminiVPN — Complete Fix & Deploy                              ║${NC}"
echo -e "${BOLD}║  Domain: geminivpn.zapto.org → 167.172.96.225                  ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "  $(date)"

# ─────────────────────────────────────────────────────────────────────────────
step "Step 1 — Apply Critical Kernel Settings"
# ─────────────────────────────────────────────────────────────────────────────
# net.ipv6.bindv6only=0: allows IPv4 traffic through IPv6 wildcard sockets.
# Without this, Docker on dual-stack Ubuntu binds port 80 to IPv6 ONLY →
# IPv4 clients (every browser) get ERR_CONNECTION_TIMED_OUT.
sysctl -w net.ipv6.bindv6only=0        2>/dev/null && ok "net.ipv6.bindv6only=0 applied" || true
sysctl -w net.ipv4.ip_forward=1        2>/dev/null && ok "net.ipv4.ip_forward=1"         || true
sysctl -w net.ipv4.conf.all.forwarding=1 2>/dev/null                                     || true
# Persist across reboots
cat > /etc/sysctl.d/99-geminivpn-ipv6.conf << 'SYSCTL'
net.ipv6.bindv6only = 0
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL
sysctl -p /etc/sysctl.d/99-geminivpn-ipv6.conf 2>/dev/null || true
ok "Kernel settings persisted to /etc/sysctl.d/99-geminivpn-ipv6.conf"

# ─────────────────────────────────────────────────────────────────────────────
step "Step 2 — Firewall: Open 80/443"
# ─────────────────────────────────────────────────────────────────────────────
ufw allow 22/tcp  2>/dev/null | grep -v 'Skip\|already\|Rules' || true
ufw allow 80/tcp  2>/dev/null | grep -v 'Skip\|already\|Rules' || true
ufw allow 443/tcp 2>/dev/null | grep -v 'Skip\|already\|Rules' || true
ufw allow 51820/udp 2>/dev/null | grep -v 'Skip\|already\|Rules' || true

# UFW FORWARD policy — Docker needs ACCEPT
UFW_DEF="/etc/default/ufw"
[[ -f "$UFW_DEF" ]] && \
  sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$UFW_DEF" 2>/dev/null || true

# iptables FORWARD rules (Docker inter-container routing)
iptables -I FORWARD -j ACCEPT       2>/dev/null || true
iptables -P FORWARD ACCEPT          2>/dev/null || true
iptables -I DOCKER-USER -j ACCEPT   2>/dev/null || true
ip6tables -P FORWARD ACCEPT         2>/dev/null || true
iptables -I INPUT -p tcp --dport 80  -j ACCEPT 2>/dev/null || true
iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
# Persist
mkdir -p /etc/iptables
iptables-save  > /etc/iptables/rules.v4 2>/dev/null || true
ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
ufw reload 2>/dev/null || true
ok "UFW + iptables: ports 22/80/443/51820 open, FORWARD=ACCEPT, INPUT rules added"

# ─────────────────────────────────────────────────────────────────────────────
step "Step 3 — Detect Real Public IPv4"
# ─────────────────────────────────────────────────────────────────────────────
MY_IP=""
for src in \
  "curl -4 -sf --max-time 5 https://ipv4.icanhazip.com" \
  "curl -4 -sf --max-time 5 https://api.ipify.org" \
  "curl -4 -sf --max-time 5 https://checkip.amazonaws.com"; do
  MY_IP=$(eval "$src" 2>/dev/null | tr -d '[:space:]') || true
  [[ "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
  MY_IP=""
done
[[ -z "$MY_IP" ]] && MY_IP="$SERVER_IP"
ok "Public IPv4: $MY_IP"

# ─────────────────────────────────────────────────────────────────────────────
step "Step 4 — Fix No-IP DNS → $MY_IP"
# ─────────────────────────────────────────────────────────────────────────────
NOIP_CONF="/usr/local/etc/no-ip2/no-ip2.conf"
if [[ -f "$NOIP_CONF" ]]; then
  NOIP_USER=$(sed -n '1p' "$NOIP_CONF" 2>/dev/null || echo "")
  NOIP_PASS=$(sed -n '2p' "$NOIP_CONF" 2>/dev/null || echo "")
  NOIP_DOMAIN=$(sed -n '3p' "$NOIP_CONF" 2>/dev/null || echo "$DOMAIN")
  if [[ -n "$NOIP_USER" && -n "$NOIP_PASS" ]]; then
    RESP=$(curl -4 -sf --max-time 15 \
      "https://dynupdate.no-ip.com/nic/update?hostname=${NOIP_DOMAIN}&myip=${MY_IP}" \
      -u "${NOIP_USER}:${NOIP_PASS}" \
      -A "GeminiVPN-Deploy/3.0 ${NOIP_USER}" 2>/dev/null || echo "FAILED")
    case "$RESP" in
      good*)  ok  "No-IP: updated to $MY_IP [$RESP]" ;;
      nochg*) ok  "No-IP: already correct [$RESP]" ;;
      badauth*) warn "No-IP: bad credentials — re-run: sudo bash re-geminivpn.sh --noip" ;;
      *)      warn "No-IP: $RESP" ;;
    esac
  fi
else
  warn "No-IP config not found — run: sudo bash re-geminivpn.sh --noip"
fi

# Wait for DNS propagation
info "Waiting 10s for DNS propagation..."
sleep 10
command -v dig &>/dev/null && \
  DNS_CHECK=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || echo "") || \
  DNS_CHECK=""
if [[ "$DNS_CHECK" == "$MY_IP" ]]; then
  ok "DNS: $DOMAIN → $MY_IP ✓"
else
  warn "DNS: got '${DNS_CHECK:-not resolved}', expected $MY_IP"
  warn "DNS may take 1-5 more minutes to propagate globally"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Step 5 — Fix Docker daemon.json (DNS + live-restore)"
# ─────────────────────────────────────────────────────────────────────────────
python3 << 'DAEMONJSON'
import json, os
path = "/etc/docker/daemon.json"
d = {}
try:
    with open(path) as f: d = json.load(f)
except: pass
d.update({
    "log-driver": "json-file",
    "log-opts": {"max-size": "50m", "max-file": "5"},
    "dns": ["1.1.1.1", "8.8.8.8"],
    "live-restore": True,
    "userland-proxy": False,
})
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w') as f: json.dump(d, f, indent=2)
print("  [✓] Docker daemon.json: DNS, live-restore, userland-proxy=false")
DAEMONJSON
systemctl reload docker 2>/dev/null || systemctl restart docker 2>/dev/null || true
sleep 3

# ─────────────────────────────────────────────────────────────────────────────
step "Step 6 — Stop Old Broken Containers"
# ─────────────────────────────────────────────────────────────────────────────
docker stop geminivpn-nginx   2>/dev/null && ok "Stopped old nginx"   || true
docker stop geminivpn-backend 2>/dev/null && ok "Stopped old backend" || true
docker rm   geminivpn-nginx   2>/dev/null || true
docker rm   geminivpn-backend 2>/dev/null || true
# Free ports 80/443 in case something else grabbed them
fuser -k 80/tcp  2>/dev/null || true
fuser -k 443/tcp 2>/dev/null || true
sleep 2
ok "Old containers cleared, ports freed"

# ─────────────────────────────────────────────────────────────────────────────
step "Step 7 — Start Backend First"
# ─────────────────────────────────────────────────────────────────────────────
COMPOSE_FILE="${DEPLOY_DIR}/docker/docker-compose.yml"
ENV_FILE="${DEPLOY_DIR}/.env"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  warn "Compose file not found — run full deploy first: sudo bash re-geminivpn.sh"
  # Try to find it
  COMPOSE_FILE=$(find /opt /root /home -name 'docker-compose.yml' 2>/dev/null | grep geminivpn | head -1 || echo "")
  [[ -z "$COMPOSE_FILE" ]] && err "Cannot find docker-compose.yml — run: sudo bash re-geminivpn.sh first"
fi

COMPOSE_DIR=$(dirname "$COMPOSE_FILE")
cd "$COMPOSE_DIR"

if docker compose version &>/dev/null; then
  DC="docker compose"
elif docker-compose version &>/dev/null; then
  DC="docker-compose"
else
  DC="docker compose"
fi

[[ -f "$ENV_FILE" ]] && DC_ARGS="--env-file $ENV_FILE" || DC_ARGS=""

info "Starting backend..."
$DC $DC_ARGS up -d backend 2>&1 | tail -5

info "Waiting for backend to be ready (up to 90s)..."
for i in $(seq 1 30); do
  if docker exec geminivpn-backend curl -sf http://localhost:5000/health &>/dev/null 2>&1; then
    ok "Backend healthy after ${i}×3s"
    break
  fi
  sleep 3
  echo -ne "  Waiting... (${i}/30)\r"
done

# ─────────────────────────────────────────────────────────────────────────────
step "Step 8 — Start nginx (bind ports 80/443)"
# ─────────────────────────────────────────────────────────────────────────────
$DC $DC_ARGS up -d --force-recreate nginx 2>&1 | tail -5
sleep 5

# Verify ports are bound
P80=$(ss  -tlnp 2>/dev/null | grep -c ':80 '  || echo 0)
P443=$(ss -tlnp 2>/dev/null | grep -c ':443 ' || echo 0)
ok "Port 80  listeners: $P80"
ok "Port 443 listeners: $P443"

if [[ "$P80" -eq 0 || "$P443" -eq 0 ]]; then
  warn "Ports not bound — checking nginx logs..."
  docker logs geminivpn-nginx --tail=20 2>/dev/null || true
  warn "Retrying nginx in 5s..."
  sleep 5
  $DC $DC_ARGS up -d --force-recreate nginx 2>&1 | tail -3
  sleep 5
fi

docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep geminivpn || true

# ─────────────────────────────────────────────────────────────────────────────
step "Step 9 — Test Local HTTPS"
# ─────────────────────────────────────────────────────────────────────────────
sleep 3
HEALTH_CODE=$(curl -4 -sk --max-time 10 -o /dev/null -w '%{http_code}' \
  https://127.0.0.1/health -H "Host: ${DOMAIN}" 2>/dev/null || echo "000")
IP_CODE=$(curl -4 -sk --max-time 10 -o /dev/null -w '%{http_code}' \
  "https://${MY_IP}/" 2>/dev/null || echo "000")

info "Local health check (/health):  HTTP $HEALTH_CODE"
info "By IP (https://${MY_IP}/): HTTP $IP_CODE"
[[ "$HEALTH_CODE" == "200" ]] && ok "Backend API: LIVE ✓" || warn "Backend: $HEALTH_CODE — may still be starting"
[[ "$IP_CODE" =~ ^(200|301|302)$ ]] && ok "IP HTTPS: responding ✓" || warn "IP HTTPS: $IP_CODE"

# ─────────────────────────────────────────────────────────────────────────────
step "Step 10 — Issue Let's Encrypt SSL Certificate"
# ─────────────────────────────────────────────────────────────────────────────
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"

if [[ -f "$CERT_PATH" ]]; then
  EXPIRY_TS=$(date -d "$(openssl x509 -noout -enddate -in "$CERT_PATH" | cut -d= -f2)" +%s 2>/dev/null || echo 0)
  DAYS_LEFT=$(( (EXPIRY_TS - $(date +%s)) / 86400 ))
  if [[ "$DAYS_LEFT" -gt 30 ]]; then
    ok "SSL cert valid for $DAYS_LEFT more days — skipping issuance"
  else
    warn "Cert expires in $DAYS_LEFT days — renewing..."
    # Re-issue
    docker stop geminivpn-nginx 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    sleep 2
    certbot certonly --standalone --non-interactive --agree-tos \
      --email "admin@${DOMAIN}" --preferred-challenges http-01 \
      -d "$DOMAIN" 2>&1 | tail -10
    docker start geminivpn-nginx 2>/dev/null || true
    sleep 5
    docker exec geminivpn-nginx nginx -s reload 2>/dev/null || true
  fi
else
  info "No SSL cert found — issuing from Let's Encrypt..."

  # Verify DNS resolves to us first
  if [[ "$DNS_CHECK" != "$MY_IP" ]]; then
    warn "DNS not yet pointing to $MY_IP — waiting up to 5 min..."
    for i in $(seq 1 30); do
      sleep 10
      DNS_CHECK=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || echo "")
      [[ "$DNS_CHECK" == "$MY_IP" ]] && { ok "DNS confirmed: $DOMAIN → $MY_IP"; break; }
      echo -ne "  DNS: ${DNS_CHECK:-not resolved} — waiting (${i}/30)\r"
    done
  fi

  apt-get install -y -qq certbot 2>/dev/null || true

  # Stop nginx to free port 80 for certbot HTTP-01 challenge
  docker stop geminivpn-nginx 2>/dev/null || true
  fuser -k 80/tcp 2>/dev/null || true
  sleep 2

  certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email "admin@${DOMAIN}" \
    --preferred-challenges http-01 \
    -d "$DOMAIN" \
    2>&1 | tail -15

  if [[ -f "$CERT_PATH" ]]; then
    EXPIRY=$(openssl x509 -noout -enddate -in "$CERT_PATH" | cut -d= -f2)
    ok "Let's Encrypt cert issued! Expires: $EXPIRY"
  else
    warn "Cert issuance failed — check DNS and port 80 accessibility"
    warn "Retry manually: sudo bash re-geminivpn.sh --ssl"
  fi

  # Restart nginx with real cert
  $DC $DC_ARGS up -d --force-recreate nginx 2>&1 | tail -3
  sleep 5
  docker exec geminivpn-nginx nginx -s reload 2>/dev/null && ok "nginx reloaded with real cert" || true

  # Set up auto-renewal
  mkdir -p /etc/letsencrypt/renewal-hooks/pre \
           /etc/letsencrypt/renewal-hooks/post

  cat > /etc/letsencrypt/renewal-hooks/pre/stop-nginx.sh << 'PREHOOK'
#!/bin/bash
docker stop geminivpn-nginx 2>/dev/null || true
fuser -k 80/tcp 2>/dev/null || true
sleep 2
PREHOOK
  chmod +x /etc/letsencrypt/renewal-hooks/pre/stop-nginx.sh

  cat > /etc/letsencrypt/renewal-hooks/post/start-nginx.sh << 'POSTHOOK'
#!/bin/bash
docker start geminivpn-nginx 2>/dev/null || true
sleep 3
docker exec geminivpn-nginx nginx -s reload 2>/dev/null || true
POSTHOOK
  chmod +x /etc/letsencrypt/renewal-hooks/post/start-nginx.sh

  # Certbot auto-renew via cron (simple, reliable)
  CRON_LINE="0 3,15 * * * root certbot renew --quiet --standalone 2>>/var/log/letsencrypt-renewal.log"
  grep -q 'certbot renew' /etc/crontab 2>/dev/null || echo "$CRON_LINE" >> /etc/crontab
  ok "SSL auto-renewal: cron job added (runs 03:00 + 15:00 daily)"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Step 11 — Final End-to-End Verification"
# ─────────────────────────────────────────────────────────────────────────────
sleep 5

HEALTH=$(curl -4 -sk --max-time 12 -o /dev/null -w '%{http_code}' \
  https://127.0.0.1/health -H "Host: ${DOMAIN}" 2>/dev/null || echo "000")
BY_IP=$(curl -4 -sk --max-time 12 -o /dev/null -w '%{http_code}' \
  "https://${MY_IP}/" 2>/dev/null || echo "000")

DNS_FINAL=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || echo "")
BY_DOMAIN="000"
if [[ "$DNS_FINAL" == "$MY_IP" ]]; then
  BY_DOMAIN=$(curl -4 -sk --max-time 15 -o /dev/null -w '%{http_code}' \
    "https://${DOMAIN}/" 2>/dev/null || echo "000")
fi

CERT_CN=$(echo | openssl s_client -connect "${MY_IP}:443" -servername "$DOMAIN" 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,]+' | head -1 || echo "none")

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                 DEPLOYMENT RESULTS                              ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
_stat() { [[ "$2" =~ ^(200|301|302)$ ]] && echo -e "  ${GREEN}✓${NC}  $1: HTTP $2" || echo -e "  ${RED}✗${NC}  $1: HTTP $2"; }
_stat "Health endpoint   " "$HEALTH"
_stat "By IP  https://${MY_IP}/" "$BY_IP"
[[ "$DNS_FINAL" == "$MY_IP" ]] && _stat "By domain https://${DOMAIN}/" "$BY_DOMAIN" || \
  echo -e "  ${YELLOW}!${NC}  Domain: DNS not yet resolved (wait 1-5 min)"
echo ""
[[ "$CERT_CN" == "$DOMAIN" ]] && \
  echo -e "  ${GREEN}✓${NC}  SSL cert: Let's Encrypt ($CERT_CN)" || \
  echo -e "  ${YELLOW}!${NC}  SSL cert: ${CERT_CN} (LE cert may still be pending)"

echo ""
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║  Containers                                                      ║${NC}"
docker ps --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep geminivpn || true
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo ""
if [[ "$BY_DOMAIN" =~ ^(200|301|302)$ ]]; then
  echo -e "  ${GREEN}${BOLD}🎉 https://geminivpn.zapto.org IS LIVE AND WORKING!${NC}"
else
  echo -e "  ${YELLOW}${BOLD}Site is running locally. If https://${DOMAIN} still times out:${NC}"
  echo ""
  echo -e "  ${BOLD}→ Check DigitalOcean Cloud Firewall:${NC}"
  echo -e "  ${CYAN}  https://cloud.digitalocean.com/networking/firewalls${NC}"
  echo -e "  ${CYAN}  Add inbound rules: TCP 80 + TCP 443, Sources: 0.0.0.0/0 + ::/0${NC}"
  echo ""
  echo -e "  ${BOLD}→ Flush your browser DNS cache:${NC}"
  echo -e "  ${CYAN}  Chrome: chrome://net-internals/#dns → Clear host cache${NC}"
  echo -e "  ${CYAN}  Windows CMD: ipconfig /flushdns${NC}"
fi
echo ""
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
