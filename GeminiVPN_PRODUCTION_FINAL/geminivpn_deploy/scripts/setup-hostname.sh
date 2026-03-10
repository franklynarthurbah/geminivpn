#!/usr/bin/env bash
# =============================================================================
# GeminiVPN — No-IP DDNS Hostname Setup
# Hostname: geminivpn.zapto.org  (No-IP free account)
# Supports: *.ddns.net *.hopto.org *.zapto.org *.no-ip.org and all No-IP TLDs
#
# Sets up 24/7 dynamic DNS so your IP always stays pointed at the server.
# Uses a systemd timer to update every 5 minutes, survives reboots.
#
# Usage: sudo bash scripts/setup-hostname.sh [noip-email] [noip-password]
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[→]${NC} $1"; }

[[ $EUID -ne 0 ]] && fail "Run as root: sudo bash $0"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       GeminiVPN — No-IP DDNS Hostname Setup                 ║"
echo "║       geminivpn.zapto.org  ·  24/7 Auto-Update              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── 1. Auto-detect public IP ──────────────────────────────────────────────────
info "Detecting server public IP..."
SERVER_IP=""
for SVC in "ifconfig.me" "api.ipify.org" "ipecho.net/plain" "icanhazip.com"; do
  SERVER_IP=$(curl -s --max-time 8 "https://$SVC" 2>/dev/null | tr -d '[:space:]') || true
  [[ "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
  SERVER_IP=""
done
[[ -z "$SERVER_IP" ]] && fail "Cannot detect public IP. Check internet connection."
ok "Public IP: $SERVER_IP"

# ── 2. Get No-IP credentials ──────────────────────────────────────────────────
NOIP_HOST="geminivpn.zapto.org"
NOIP_USER="${1:-}"
NOIP_PASS="${2:-}"

echo ""
echo "  No-IP hostname: ${BOLD}$NOIP_HOST${NC}"
echo "  Log in at https://www.noip.com/login to find your credentials."
echo ""
[[ -z "$NOIP_USER" ]] && read -rp "  No-IP Email/Username: " NOIP_USER
if [[ -z "$NOIP_PASS" ]]; then
  read -rsp "  No-IP Password: " NOIP_PASS
  echo ""
fi

[[ -z "$NOIP_USER" ]] && fail "Username required"
[[ -z "$NOIP_PASS" ]] && fail "Password required"

# ── 3. Install dependencies ───────────────────────────────────────────────────
info "Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>/dev/null
apt-get install -y -qq curl dnsutils 2>/dev/null
ok "Dependencies installed"

# ── 4. Save credentials ───────────────────────────────────────────────────────
mkdir -p /etc/noip
cat > /etc/noip/noip.conf << CONFEOF
NOIP_HOST="${NOIP_HOST}"
NOIP_USER="${NOIP_USER}"
NOIP_PASS="${NOIP_PASS}"
LAST_IP=""
LAST_UPDATE=""
CONFEOF
chmod 600 /etc/noip/noip.conf
ok "Credentials saved: /etc/noip/noip.conf (root-only)"

# ── 5. Create the DDNS updater script ────────────────────────────────────────
info "Creating /usr/local/bin/noip-update..."
cat > /usr/local/bin/noip-update << 'UPDEOF'
#!/usr/bin/env bash
LOG="/var/log/noip-update.log"
CONF="/etc/noip/noip.conf"
[[ ! -f "$CONF" ]] && echo "[$(date)] ERROR: Config missing: $CONF" >> "$LOG" && exit 1
source "$CONF"

CURRENT_IP=""
for SVC in "ifconfig.me" "api.ipify.org" "ipecho.net/plain" "icanhazip.com"; do
  CURRENT_IP=$(curl -s --max-time 8 "https://$SVC" 2>/dev/null | tr -d '[:space:]') || true
  [[ "$CURRENT_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
  CURRENT_IP=""
done

if [[ -z "$CURRENT_IP" ]]; then
  echo "[$(date)] WARN: Cannot detect public IP — retrying next cycle" >> "$LOG"
  exit 1
fi

# Skip silently if IP unchanged
[[ "$CURRENT_IP" == "$LAST_IP" ]] && exit 0

echo "[$(date)] INFO: IP change: ${LAST_IP:-none} → $CURRENT_IP" | tee -a "$LOG"

RESPONSE=$(curl -s --max-time 30 \
  --user "${NOIP_USER}:${NOIP_PASS}" \
  "https://dynupdate.no-ip.com/nic/update?hostname=${NOIP_HOST}&myip=${CURRENT_IP}" \
  -A "GeminiVPN-DUC/3.0 ${NOIP_USER}" 2>/dev/null)

echo "[$(date)] RESPONSE: $RESPONSE" | tee -a "$LOG"

case "$RESPONSE" in
  good*|nochg*)
    sed -i "s|^LAST_IP=.*|LAST_IP=\"${CURRENT_IP}\"|"     "$CONF"
    sed -i "s|^LAST_UPDATE=.*|LAST_UPDATE=\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"|" "$CONF"
    echo "[$(date)] SUCCESS: $NOIP_HOST → $CURRENT_IP" | tee -a "$LOG"
    ;;
  nohost*)  echo "[$(date)] ERROR: Hostname not in No-IP account — add it at noip.com" | tee -a "$LOG"; exit 1 ;;
  badauth*) echo "[$(date)] ERROR: Wrong credentials — update /etc/noip/noip.conf" | tee -a "$LOG"; exit 1 ;;
  abuse*)   echo "[$(date)] ERROR: Account flagged — check noip.com dashboard" | tee -a "$LOG"; exit 1 ;;
  911*)     echo "[$(date)] WARN: No-IP server error — will retry" | tee -a "$LOG"; exit 1 ;;
  *)        echo "[$(date)] WARN: Unknown response: $RESPONSE" | tee -a "$LOG" ;;
esac
UPDEOF
chmod +x /usr/local/bin/noip-update
ok "Updater created: /usr/local/bin/noip-update"

# ── 6. Create systemd service + timer ─────────────────────────────────────────
info "Setting up systemd 24/7 timer..."

cat > /etc/systemd/system/noip-update.service << 'SVCEOF'
[Unit]
Description=No-IP DDNS Update — geminivpn.zapto.org
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/noip-update
StandardOutput=journal
StandardError=journal
SVCEOF

cat > /etc/systemd/system/noip-update.timer << 'TIMEREOF'
[Unit]
Description=No-IP DDNS update every 5 minutes
After=network-online.target

[Timer]
OnBootSec=30sec
OnUnitActiveSec=5min
AccuracySec=30sec
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now noip-update.timer
ok "Timer active — updates every 5 min, survives reboots"

# ── 7. Run first update now ───────────────────────────────────────────────────
info "Running first DNS update..."
/usr/local/bin/noip-update && ok "DNS update sent" || \
  warn "Check /var/log/noip-update.log for details"

# ── 8. System hostname ────────────────────────────────────────────────────────
hostnamectl set-hostname "geminivpn" 2>/dev/null || hostname "geminivpn" || true
grep -q "geminivpn.zapto.org" /etc/hosts 2>/dev/null || \
  echo "$SERVER_IP geminivpn.zapto.org geminivpn" >> /etc/hosts
ok "System hostname: geminivpn (FQDN: $NOIP_HOST)"

# ── 9. IP forwarding ─────────────────────────────────────────────────────────
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf          || echo "net.ipv4.ip_forward=1"          >> /etc/sysctl.conf
grep -q "^net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
ok "IP forwarding enabled"

# ── 10. Firewall ─────────────────────────────────────────────────────────────
info "Configuring firewall..."
if command -v ufw &>/dev/null; then
  ufw allow 22/tcp    comment 'SSH'          >/dev/null 2>&1 || true
  ufw allow 80/tcp    comment 'HTTP'         >/dev/null 2>&1 || true
  ufw allow 443/tcp   comment 'HTTPS'        >/dev/null 2>&1 || true
  ufw allow 51820/udp comment 'WireGuard'    >/dev/null 2>&1 || true
  echo "y" | ufw enable >/dev/null 2>&1 || true
  ok "UFW: ports 22, 80, 443, 51820/udp open"
else
  for PORT in 22 80 443; do
    iptables -I INPUT -p tcp --dport $PORT -j ACCEPT 2>/dev/null || true
  done
  iptables -I INPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null || true
  iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
  ok "iptables: ports 22, 80, 443, 51820/udp open"
fi

# ── 11. Verify ────────────────────────────────────────────────────────────────
sleep 3
VERIFIED=$(dig +short "$NOIP_HOST" 2>/dev/null | grep -E '^[0-9]+\.' | tail -1 || echo "")
if [[ "$VERIFIED" == "$SERVER_IP" ]]; then
  ok "DNS verified: $NOIP_HOST → $VERIFIED ✓"
elif [[ -n "$VERIFIED" ]]; then
  warn "DNS → $VERIFIED (expected $SERVER_IP) — may take a few minutes"
else
  warn "DNS not resolving yet — No-IP usually takes 1–5 min after first update"
fi

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✓  No-IP DDNS Setup Complete!${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
echo "  Hostname : $NOIP_HOST"
echo "  Server IP: $SERVER_IP"
echo "  Updates  : Every 5 minutes, 24/7"
echo "  Log      : /var/log/noip-update.log"
echo ""
echo "  Commands:"
echo "    noip-update                           # force update now"
echo "    systemctl status noip-update.timer    # check timer"
echo "    tail -f /var/log/noip-update.log      # watch log"
echo ""
echo -e "  ${CYAN}Next: sudo bash scripts/setup-ssl.sh $NOIP_HOST${NC}"
echo ""
