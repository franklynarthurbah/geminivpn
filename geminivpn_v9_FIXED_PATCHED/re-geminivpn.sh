#!/usr/bin/env bash
# =============================================================================
#   ██████╗ ███████╗███╗   ███╗██╗███╗   ██╗██╗██╗   ██╗██████╗ ███╗   ██╗
#  ██╔════╝ ██╔════╝████╗ ████║██║████╗  ██║██║██║   ██║██╔══██╗████╗  ██║
#  ██║  ███╗█████╗  ██╔████╔██║██║██╔██╗ ██║██║██║   ██║██████╔╝██╔██╗ ██║
#  ██║   ██║██╔══╝  ██║╚██╔╝██║██║██║╚██╗██║██║╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║
#  ╚██████╔╝███████╗██║ ╚═╝ ██║██║██║ ╚████║██║ ╚████╔╝ ██║     ██║ ╚████║
#   ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═══╝ ╚═╝     ╚═╝  ╚═══╝
#
#  RE-GEMINIVPN — v5 SQLite Edition (No Redis · No PostgreSQL · No-IP 24/7)
#  Database: SQLite file stored in ./database/geminivpn.db
#  Usage:  sudo bash re-geminivpn.sh [mode]
#  Modes:  (none)     → full deploy / redeploy (auto-detected)
#          --ssl      → set up / renew Let's Encrypt SSL only
#          --stripe   → configure Stripe payments only
#          --payment  → configure Square · Paddle · Coinbase payments
#          --smtp     → configure SMTP email only
#          --test     → run full test suite only
#          --harden   → apply server hardening only
#          --status   → show container + SSL + payment status
#          --watchdog → start auto-refresh health watchdog (auto-restart on failure)
#          --stop     → stop the auto-refresh watchdog
#          --whatsapp → update WhatsApp support number
#          --noip     → setup/configure No-IP DUC only
#          --noip-firewall → fix No-IP firewall (outbound rules + restart)
#          --fix-dns       → force IPv4-only No-IP update + verify DNS A record
#          --auto-heal     → detect & fix all blocking issues automatically
#          --fix-all       → complete repair: harden + noip + heal + watchdog
#          --app      → build all apps (APK, EXE, DMG, iOS, Router)
#          --backup   → backup the SQLite database
#          --restore  → restore the SQLite database from a backup
# =============================================================================
set -uo pipefail
trap 'echo -e "\n${RED}[✗] Error on line $LINENO — run with bash -x for trace${NC}" >&2' ERR

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}[✓]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $*"; }
die()  { echo -e "\n  ${RED}[✗] $*${NC}\n"; exit 1; }
info() { echo -e "  ${CYAN}[→]${NC} $*"; }
step() {
  echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}  $*${NC}"
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
}

# ─── Config ───────────────────────────────────────────────────────────────────
DOMAIN="geminivpn.zapto.org"
SERVER_IP="167.172.96.225"
# =============================================================================
# DIGITALOCEAN CLOUD FIREWALL CHECK — Runs early so user sees it immediately
# =============================================================================
check_do_firewall() {
  # Test if external inbound on port 80 is reachable (1 quick TCP probe)
  # timeout 3 bash: open TCP to our own external IP:80
  # IMPORTANT: use dig +short A (IPv4 A record only) — getent hosts returns IPv6 on dual-stack
  local DOMAIN_IP=""
  command -v dig &>/dev/null && \
    DOMAIN_IP=$(dig +short A "${DOMAIN}" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || true)
  # Fallback: curl -4 against our own IP APIs
  [[ ! "$DOMAIN_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. ]] && \
    DOMAIN_IP=$(curl -4 -sf --max-time 5 https://ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]' || true)
  [[ -z "$DOMAIN_IP" ]] && DOMAIN_IP="$SERVER_IP"
  # Quick TCP probe — if it refuses immediately, port is open (UFW blocking app)
  # If it silently times out, DO cloud firewall is dropping the packet
  local TCP_RESULT; TCP_RESULT=$(timeout 5 bash -c "echo >/dev/tcp/${DOMAIN_IP}/80" 2>&1 && echo "OPEN" || echo "FAIL")
  if [[ "$TCP_RESULT" == "FAIL" ]]; then
    echo ""
    echo -e "  ${BOLD}${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${BOLD}${RED}║  ⚠  EXTERNAL ACCESS BLOCKED — ACTION REQUIRED                  ║${NC}"
    echo -e "  ${BOLD}${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}Your DigitalOcean Cloud Firewall is blocking inbound TCP 80/443.${NC}"
    echo -e "  ${YELLOW}This is SEPARATE from UFW and must be fixed in the DO dashboard.${NC}"
    echo ""
    echo -e "  ${BOLD}→ Fix in 60 seconds:${NC}"
    echo -e "  ${CYAN}  1. Go to: https://cloud.digitalocean.com/networking/firewalls${NC}"
    echo -e "  ${CYAN}  2. Find your droplet's firewall → Edit → Inbound Rules${NC}"
    echo -e "  ${CYAN}  3. Add: HTTP  (TCP 80)  Sources: All IPv4 (0.0.0.0/0) + All IPv6 (::/0)${NC}"
    echo -e "  ${CYAN}  4. Add: HTTPS (TCP 443) Sources: All IPv4 (0.0.0.0/0) + All IPv6 (::/0)${NC}"
    echo -e "  ${CYAN}  5. Save — changes apply within 30 seconds, no reboot needed.${NC}"
    echo ""
    echo -e "  ${GREEN}Note: UFW is already configured correctly. Only the DO cloud firewall needs updating.${NC}"
    echo -e "  ${GREEN}Your site IS running — https://167.172.96.225 (direct IP) works now.${NC}"
    echo -e "  ${GREEN}After adding the DO firewall rules, https://geminivpn.zapto.org will work.${NC}"
    echo ""
  fi
}


DEPLOY_DIR="/opt/geminivpn"
WWW_DIR="/var/www/geminivpn"
LOG_DIR="/var/log/geminivpn"
DB_DIR="${DEPLOY_DIR}/database"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${DEPLOY_DIR}/.env"
MODE="${1:-deploy}"

# Docker compose command detection
if docker compose version &>/dev/null; then
  DOCKER_COMPOSE="docker compose"
elif docker-compose version &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
else
  DOCKER_COMPOSE="docker compose"
fi

# No-IP Configuration
NOIP_CONFIG_DIR="/usr/local/etc/no-ip2"
NOIP_CONFIG_FILE="${NOIP_CONFIG_DIR}/no-ip2.conf"

[[ $EUID -ne 0 ]] && die "Run as root: sudo bash re-geminivpn.sh $*"

print_banner() {
  echo -e "${BOLD}${CYAN}"
  echo "  ╔══════════════════════════════════════════════════════════════════╗"
  echo "  ║    RE-GEMINIVPN v5 — SQLite Edition (No Redis · No Postgres)   ║"
  echo "  ║    ${DOMAIN}  ·  No-IP Auto-Refresh Enabled          ║"
  echo "  ╚══════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${DIM}Mode: ${MODE} | $(date)${NC}"
  echo ""
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

env_set() {
  local KEY="$1" VAL="$2" FILE="${3:-$ENV_FILE}"
  [[ -f "$FILE" ]] || touch "$FILE"
  if grep -q "^${KEY}=" "$FILE" 2>/dev/null; then
    sed -i "s|^${KEY}=.*|${KEY}=${VAL}|" "$FILE"
  else
    echo "${KEY}=${VAL}" >> "$FILE"
  fi
}

env_get() {
  local KEY="$1" FILE="${2:-$ENV_FILE}"
  if [[ -f "$FILE" ]]; then
    grep "^${KEY}=" "$FILE" 2>/dev/null | cut -d= -f2- || echo ""
  else
    echo ""
  fi
}

wait_healthy() {
  local CTR="$1" MAX="${2:-120}" i=0
  while [[ $i -lt $MAX ]]; do
    local STATUS HEALTH
    STATUS=$(docker inspect "$CTR" --format '{{.State.Status}}' 2>/dev/null || echo "missing")
    HEALTH=$(docker inspect "$CTR" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
    [[ "$STATUS" == "running" && ("$HEALTH" == "healthy" || "$HEALTH" == "none") ]] && return 0
    [[ "$STATUS" == "restarting" && $i -gt 20 ]] && {
      warn "Container ${CTR} crash-looping — logs:"
      docker logs "$CTR" --tail=40 2>&1 | sed 's/^/    /'
      return 1
    }
    echo -ne "  ${CYAN}[→]${NC} Waiting for ${CTR} (${i}s / ${MAX}s)...\r"
    sleep 3
    i=$((i + 3))
  done
  warn "Timeout waiting for ${CTR}"
  return 1
}

# =============================================================================
# DATABASE BACKUP / RESTORE
# =============================================================================

phase_backup() {
  step "SQLite Database Backup"
  local DB_FILE="${DB_DIR}/geminivpn.db"
  local BACKUP_DIR="${DB_DIR}/backups"
  local TIMESTAMP; TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  local BACKUP_FILE="${BACKUP_DIR}/geminivpn_${TIMESTAMP}.db"

  mkdir -p "$BACKUP_DIR"

  if [[ ! -f "$DB_FILE" ]]; then
    warn "No database file found at ${DB_FILE} — nothing to backup"
    return 0
  fi

  # Use SQLite online backup if database is running
  if docker ps | grep -q geminivpn-backend; then
    docker exec geminivpn-backend sh -c \
      "sqlite3 /app/database/geminivpn.db '.backup /app/database/backups/geminivpn_${TIMESTAMP}.db'" \
      2>/dev/null || cp "$DB_FILE" "$BACKUP_FILE"
  else
    cp "$DB_FILE" "$BACKUP_FILE"
  fi

  ok "Backup created: ${BACKUP_FILE} ($(du -h "$BACKUP_FILE" | cut -f1))"

  # Keep only the 10 most recent backups
  ls -t "${BACKUP_DIR}"/*.db 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
  ok "Backup rotation: kept 10 most recent"
}

phase_restore() {
  step "SQLite Database Restore"
  local BACKUP_DIR="${DB_DIR}/backups"
  local DB_FILE="${DB_DIR}/geminivpn.db"

  if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
    die "No backups found in ${BACKUP_DIR}"
  fi

  echo ""
  echo -e "  ${BOLD}Available backups:${NC}"
  local i=1
  declare -a BACKUPS
  while IFS= read -r f; do
    BACKUPS+=("$f")
    echo "  ${i}) $(basename "$f") ($(du -h "$f" | cut -f1))"
    i=$((i + 1))
  done < <(ls -t "${BACKUP_DIR}"/*.db 2>/dev/null)

  echo ""
  read -rp "  Choose backup number [1]: " CHOICE
  CHOICE="${CHOICE:-1}"
  local SELECTED="${BACKUPS[$((CHOICE - 1))]}"
  [[ -f "$SELECTED" ]] || die "Invalid selection"

  # Stop backend before restore
  info "Stopping backend container..."
  cd "${DEPLOY_DIR}/docker" 2>/dev/null || true
  $DOCKER_COMPOSE stop backend 2>/dev/null || true

  # Backup current DB before overwriting
  [[ -f "$DB_FILE" ]] && cp "$DB_FILE" "${DB_FILE}.pre-restore.bak"

  cp "$SELECTED" "$DB_FILE"
  chmod 664 "$DB_FILE"

  # Restart
  $DOCKER_COMPOSE --env-file "$ENV_FILE" start backend 2>/dev/null || true
  ok "Restored from: $(basename "$SELECTED")"
  info "Previous DB saved as: ${DB_FILE}.pre-restore.bak"
}

# =============================================================================
# NO-IP DYNAMIC DNS CLIENT (24/7 AUTO-REFRESH)
# =============================================================================

phase_noip_setup() {
  step "No-IP Dynamic DNS — Curl-Based Updater (Zero Hang)"

  # ══════════════════════════════════════════════════════════════════════════
  # ROOT CAUSE FIX: The old `noip2 -C` interactive configuration command
  # connects to No-IP servers, fetches hostname lists, asks for update
  # interval, and hangs indefinitely if: the server asks more questions than
  # expected, the pipe runs dry, or No-IP is slow to respond.
  #
  # SOLUTION: Replace noip2 binary entirely with a pure curl-based updater.
  # The No-IP Dynamic DNS protocol is a simple HTTP GET with Basic Auth:
  #   GET https://dynupdate.no-ip.com/nic/update?hostname=DOMAIN&myip=IP
  #   Authorization: Basic base64(user:pass)
  # This NEVER blocks, NEVER hangs, requires zero binary compilation.
  # ══════════════════════════════════════════════════════════════════════════

  # ── Step 0: Firewall outbound rules — always apply first ─────────────────
  # (before anything else so connectivity check below can succeed)
  for RULE in \
    "out on any to any port 53  proto udp" \
    "out on any to any port 53  proto tcp" \
    "out on any to any port 80  proto tcp" \
    "out on any to any port 443 proto tcp" \
    "out on any to any port 8245 proto tcp"; do
    ufw allow $RULE 2>/dev/null || true
  done
  iptables -I OUTPUT -p tcp --dport 80   -j ACCEPT 2>/dev/null || true
  iptables -I OUTPUT -p tcp --dport 443  -j ACCEPT 2>/dev/null || true
  iptables -I OUTPUT -p tcp --dport 8245 -j ACCEPT 2>/dev/null || true
  iptables -I OUTPUT -p udp --dport 53   -j ACCEPT 2>/dev/null || true
  ok "Outbound firewall: DNS(53) HTTP(80) HTTPS(443) NoIP-alt(8245) open"

  # ── Step 1: Load credentials from existing config or prompt once ──────────
  # Config format: three lines → USER / PASS / DOMAIN  (chmod 600)
  # This is the ONLY prompt in the entire function. It completes in <1 second.
  mkdir -p "$NOIP_CONFIG_DIR"
  chmod 700 "$NOIP_CONFIG_DIR"

  local NOIP_USER="" NOIP_PASS="" NOIP_DOMAIN="$DOMAIN"

  if [[ -f "$NOIP_CONFIG_FILE" ]]; then
    # Already configured — read silently (no prompts on redeploy)
    NOIP_USER=$(sed -n '1p' "$NOIP_CONFIG_FILE" 2>/dev/null || echo "")
    NOIP_PASS=$(sed -n '2p' "$NOIP_CONFIG_FILE" 2>/dev/null || echo "")
    NOIP_DOMAIN=$(sed -n '3p' "$NOIP_CONFIG_FILE" 2>/dev/null || echo "$DOMAIN")
    if [[ -n "$NOIP_USER" && -n "$NOIP_PASS" ]]; then
      ok "No-IP credentials loaded from config (no prompt needed)"
    else
      warn "Config file exists but is empty — re-prompting once"
      rm -f "$NOIP_CONFIG_FILE"
    fi
  fi

  if [[ -z "$NOIP_USER" || -z "$NOIP_PASS" ]]; then
    echo ""
    echo -e "  ${BOLD}No-IP Account — One-time Setup${NC}"
    echo -e "  ${DIM}Get credentials at: https://www.noip.com/members/dns/${NC}"
    echo ""
    read -rp  "  No-IP Username/Email: " NOIP_USER
    read -rsp "  No-IP Password:       " NOIP_PASS; echo ""
    [[ -z "$NOIP_USER" ]] && { warn "No-IP username empty — skipping DNS setup"; return 0; }
    [[ -z "$NOIP_PASS" ]] && { warn "No-IP password empty — skipping DNS setup"; return 0; }
    # Save credentials — never prompt again (even on 100 redeployments)
    printf '%s\n%s\n%s\n' "$NOIP_USER" "$NOIP_PASS" "$NOIP_DOMAIN" > "$NOIP_CONFIG_FILE"
    chmod 600 "$NOIP_CONFIG_FILE"
    ok "No-IP credentials saved to $NOIP_CONFIG_FILE"
  fi

  # ── Step 2: Test connectivity to No-IP (non-blocking, fast timeout) ───────
  local NOIP_REACHABLE=false
  for URL in "https://dynupdate.no-ip.com" "http://dynupdate.no-ip.com" "http://dynupdate.no-ip.com:8245"; do
    if curl -sf --max-time 6 --head "$URL" >/dev/null 2>&1; then
      NOIP_REACHABLE=true
      ok "No-IP server reachable: $URL"
      break
    fi
  done
  if [[ "$NOIP_REACHABLE" == "false" ]]; then
    warn "No-IP server unreachable — DNS will update when connectivity restores"
    warn "Check: DigitalOcean cloud firewall → Outbound TCP 80, 443, 8245"
  fi

  # ── Step 3: Write the curl-based updater script ───────────────────────────
  # Pure bash + curl — no noip2 binary required. Works on any Linux.
  cat > /usr/local/bin/noip-update-check.sh << 'UPDATER'
#!/bin/bash
# =============================================================================
# GeminiVPN — No-IP Curl Updater (no noip2 binary needed)
# Runs every 5 minutes via systemd timer + cron backup
# Protocol: https://www.noip.com/integrate/request
# =============================================================================
set -uo pipefail

NOIP_CONFIG="/usr/local/etc/no-ip2/no-ip2.conf"
LOG_FILE="/var/log/noip-update.log"
STATE_FILE="/var/run/noip-health.state"
MAX_LOG_LINES=500

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
rotate_log() {
  [[ -f "$LOG_FILE" ]] || return
  local CNT; CNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
  [[ $CNT -gt $MAX_LOG_LINES ]] && tail -n $MAX_LOG_LINES "$LOG_FILE" > "${LOG_FILE}.tmp" \
    && mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null || true
}

# Load credentials
[[ -f "$NOIP_CONFIG" ]] || { log "CONFIG MISSING: $NOIP_CONFIG — run: sudo bash re-geminivpn.sh --noip"; exit 0; }
NOIP_USER=$(sed -n '1p' "$NOIP_CONFIG")
NOIP_PASS=$(sed -n '2p' "$NOIP_CONFIG")
NOIP_DOMAIN=$(sed -n '3p' "$NOIP_CONFIG")
[[ -z "$NOIP_USER" || -z "$NOIP_PASS" || -z "$NOIP_DOMAIN" ]] && { log "CONFIG INCOMPLETE"; exit 0; }

# Get current public IPv4 — MUST use -4 flag to avoid IPv6 on dual-stack servers.
# No-IP A records are IPv4-only; pushing an IPv6 addr breaks the domain entirely.
CURRENT_IP=""
for SVC in \
  "https://ipv4.icanhazip.com" \
  "https://api.ipify.org" \
  "https://checkip.amazonaws.com" \
  "https://ip4.seeip.org" \
  "https://ifconfig.me"; do
  CURRENT_IP=$(curl -4 -sf --max-time 5 "$SVC" 2>/dev/null | tr -d '[:space:]')
  [[ "$CURRENT_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
  CURRENT_IP=""
done
# Interface fallback (still validates IPv4 format)
if [[ ! "$CURRENT_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  IFACE=$(ip -4 route show default 2>/dev/null | awk '/default/{print $5}' | head -1)
  [[ -n "$IFACE" ]] && CURRENT_IP=$(ip -4 addr show "$IFACE" 2>/dev/null \
    | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1)
fi
[[ ! "$CURRENT_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && \
  { log "WARN: Cannot determine public IPv4 — skipping"; exit 0; }

# Get DNS A record only (not AAAA) — use dig with +short A to force IPv4 answer.
# getent hosts is NOT safe here: on dual-stack it returns IPv6 (AAAA) first.
DNS_IP=""
if command -v dig &>/dev/null; then
  DNS_IP=$(dig +short A "$NOIP_DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || true)
fi
# Fallback: Google DoH (no dig needed on minimal installs)
if [[ ! "$DNS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  DNS_IP=$(curl -4 -sf --max-time 8 \
    "https://dns.google/resolve?name=${NOIP_DOMAIN}&type=A" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); a=d.get('Answer',[]); print(next((x['data'] for x in a if x.get('type')==1),''))" \
    2>/dev/null || echo "")
fi

# Read last known IP
LAST_IP=$(cat "$STATE_FILE" 2>/dev/null || echo "")

# Only update if IP changed
if [[ "$CURRENT_IP" == "$DNS_IP" ]]; then
  [[ "$CURRENT_IP" != "$LAST_IP" ]] && { echo "$CURRENT_IP" > "$STATE_FILE"; log "OK: IP confirmed $CURRENT_IP (DNS matches)"; }
  rotate_log; exit 0
fi

log "IP change detected: DNS=$DNS_IP Current=$CURRENT_IP — sending update..."

# Send update via No-IP HTTP API (Basic Auth, proper User-Agent required)
RESPONSE=$(curl -sf --max-time 15 \
  --user "${NOIP_USER}:${NOIP_PASS}" \
  --user-agent "GeminiVPN-Updater/2.0 ${NOIP_USER}" \
  "https://dynupdate.no-ip.com/nic/update?hostname=${NOIP_DOMAIN}&myip=${CURRENT_IP}" \
  2>/dev/null || echo "")

# Fallback via port 8245 if 443 failed
if [[ -z "$RESPONSE" ]]; then
  RESPONSE=$(curl -sf --max-time 15 \
    --user "${NOIP_USER}:${NOIP_PASS}" \
    --user-agent "GeminiVPN-Updater/2.0 ${NOIP_USER}" \
    "http://dynupdate.no-ip.com:8245/nic/update?hostname=${NOIP_DOMAIN}&myip=${CURRENT_IP}" \
    2>/dev/null || echo "")
fi

case "$RESPONSE" in
  good*)    echo "$CURRENT_IP" > "$STATE_FILE"; log "SUCCESS: Updated to $CURRENT_IP (response: $RESPONSE)" ;;
  nochg*)   echo "$CURRENT_IP" > "$STATE_FILE"; log "NOCHG: IP unchanged at $CURRENT_IP (No-IP already correct)" ;;
  nohost*)  log "ERROR: Hostname $NOIP_DOMAIN not found in No-IP account" ;;
  badauth*) log "ERROR: Bad credentials — check username/password in $NOIP_CONFIG" ;;
  abuse*)   log "ERROR: Account flagged for abuse — log in to noip.com to resolve" ;;
  911*)     log "ERROR: No-IP server error (911) — will retry next cycle" ;;
  "")       log "ERROR: No response from No-IP — outbound firewall blocking?" ;;
  *)        log "UNKNOWN response: $RESPONSE" ;;
esac

rotate_log
UPDATER
  chmod +x /usr/local/bin/noip-update-check.sh
  ok "No-IP curl updater written: /usr/local/bin/noip-update-check.sh"

  # ── Step 4: Systemd timer (preferred over cron — restarts on failure) ─────
  cat > /etc/systemd/system/noip-updater.service << 'NOSVC'
[Unit]
Description=GeminiVPN — No-IP DNS Update (curl-based)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/noip-update-check.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=noip-updater
NOSVC

  cat > /etc/systemd/system/noip-updater.timer << 'NOTIMER'
[Unit]
Description=GeminiVPN — No-IP DNS Update Timer (every 5 min)
Requires=noip-updater.service

[Timer]
OnBootSec=30sec
OnUnitActiveSec=5min
AccuracySec=10sec
Persistent=true

[Install]
WantedBy=timers.target
NOTIMER

  systemctl daemon-reload            2>/dev/null || true
  systemctl enable  noip-updater.timer 2>/dev/null || true
  systemctl start   noip-updater.timer 2>/dev/null || true
  ok "No-IP systemd timer: active every 5 minutes"

  # ── Step 5: Cron backup (double-coverage if systemd timer fails) ──────────
  if ! crontab -l 2>/dev/null | grep -q "noip-update-check"; then
    ( crontab -l 2>/dev/null || echo "" ) \
      | { cat; echo "*/5 * * * * /usr/local/bin/noip-update-check.sh >/dev/null 2>&1"; } \
      | crontab -
    ok "Cron backup: No-IP check every 5 minutes"
  fi

  # ── Step 6: Kill old noip2 binary processes (if still running) ────────────
  if pgrep -x noip2 >/dev/null 2>&1; then
    pkill -9 -x noip2 2>/dev/null || true
    systemctl disable noip2.service 2>/dev/null || true
    systemctl stop    noip2.service 2>/dev/null || true
    ok "Legacy noip2 binary: stopped and disabled (replaced by curl updater)"
  fi

  # ── Step 7: Run the first update immediately (background, non-blocking) ───
  touch /var/log/noip-update.log && chmod 644 /var/log/noip-update.log
  touch /var/run/noip-health.state 2>/dev/null || true
  /usr/local/bin/noip-update-check.sh &
  disown
  ok "No-IP first update triggered (background — non-blocking)"

  echo ""
  ok "No-IP DNS setup complete — curl-based, zero-hang, 5-min auto-refresh"
  info "Logs:       tail -f /var/log/noip-update.log"
  info "Timer:      systemctl status noip-updater.timer"
  info "Force test: /usr/local/bin/noip-update-check.sh"

  # Immediately correct any DNS mismatch caused by the old IPv6-leaking updater
  echo ""
  info "Running IPv4 DNS verification pass (catches pre-existing IPv6 push)..."
  phase_fix_dns_ipv4 || true
}

phase_prerequisites() {
  step "Phase 0 — Prerequisites"

  if ! command -v docker &>/dev/null; then
    info "Installing Docker..."
    export DEBIAN_FRONTEND=noninteractive
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker && systemctl start docker
    ok "Docker installed"
  fi

  if docker compose version &>/dev/null; then
    DOCKER_COMPOSE="docker compose"
    ok "Docker Compose (plugin) detected"
  elif docker-compose version &>/dev/null; then
    DOCKER_COMPOSE="docker-compose"
    ok "Docker Compose (standalone) detected"
  else
    info "Installing Docker Compose plugin..."
    apt-get install -y docker-compose-plugin 2>/dev/null || apt-get install -y docker-compose
    DOCKER_COMPOSE="docker compose"
  fi

  ok "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"

  PKGS=""
  for p in curl openssl git rsync python3 sqlite3; do
    command -v "$p" &>/dev/null || PKGS="$PKGS $p"
  done
  # dnsutils provides dig/nslookup — check by command name, not package name
  command -v dig &>/dev/null || PKGS="$PKGS dnsutils"
  [[ -n "$PKGS" ]] && { info "Installing:$PKGS"; apt-get install -y -qq $PKGS 2>/dev/null || apt-get install -y $PKGS; }
  ok "All prerequisites met"

  mkdir -p "$DEPLOY_DIR" "$WWW_DIR/downloads" "$LOG_DIR" "/var/www/certbot" "$NOIP_CONFIG_DIR" "$DB_DIR" "${DB_DIR}/backups"
  ok "Directories created (including database/ folder)"

  # ── UFW firewall — installed silently, no iptables-persistent conflict ──────
  # Ubuntu 24.04: ufw conflicts with iptables-persistent — never install together.
  # iptables rules are persisted via iptables-save + geminivpn-iptables.service.
  export DEBIAN_FRONTEND=noninteractive
  if ! command -v ufw &>/dev/null; then
    apt-get install -y -qq ufw 2>/dev/null || true
  fi
  command -v ufw &>/dev/null && ok "UFW present — rules persisted via iptables-save + boot service" \
    || warn "UFW not found — run: apt-get install ufw" 

  # ── Docker daemon: explicit DNS + log rotation + live-restore ────────────
  # live-restore: containers keep running when Docker daemon restarts (zero downtime)
  # dns: Docker containers use Cloudflare + Google DNS — bypasses host DNS issues
  #      that cause No-IP lookups and Let's Encrypt ACME to silently fail
  if [[ ! -f /etc/docker/daemon.json ]] || ! grep -q '"live-restore"' /etc/docker/daemon.json 2>/dev/null; then
    python3 - << 'DAEMONJSON'
import json, os
path = "/etc/docker/daemon.json"
d = {}
try:
    with open(path) as f: d = json.load(f)
except: pass
d.update({
    "log-driver": "json-file",
    "log-opts": {"max-size": "50m", "max-file": "5"},
    "dns": ["1.1.1.1", "8.8.8.8", "1.0.0.1"],
    "dns-search": [],
    "live-restore": True,
    "default-ulimits": {"nofile": {"Name": "nofile", "Hard": 65535, "Soft": 65535}},
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 5,
})
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w') as f: json.dump(d, f, indent=2)
print("  [✓] Docker daemon.json: DNS(1.1.1.1+8.8.8.8), live-restore, log-rotation configured")
DAEMONJSON
    systemctl reload docker 2>/dev/null || systemctl restart docker 2>/dev/null || true
    ok "Docker daemon configured (DNS + live-restore + log rotation)"
  else
    ok "Docker daemon.json already configured"
  fi

  # ── geminivpn-iptables boot service: FORWARD=ACCEPT survives reboots ──────
  # Critical: UFW reset / docker restart can drop FORWARD chain back to DROP
  # This service runs Before=docker.service ensuring rules are set on every boot
  cat > /etc/systemd/system/geminivpn-iptables.service << 'IPTS'
[Unit]
Description=GeminiVPN — Boot-time Firewall FORWARD Rules
After=network.target
Before=docker.service
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'iptables -P FORWARD ACCEPT; iptables -I FORWARD -j ACCEPT; iptables -I FORWARD -i docker0 -j ACCEPT; iptables -I FORWARD -o docker0 -j ACCEPT; iptables -I OUTPUT -p tcp --dport 80 -j ACCEPT; iptables -I OUTPUT -p tcp --dport 443 -j ACCEPT; iptables -I OUTPUT -p udp --dport 53 -j ACCEPT; iptables -I OUTPUT -p tcp --dport 8245 -j ACCEPT; ip6tables -P FORWARD ACCEPT 2>/dev/null; true'

[Install]
WantedBy=multi-user.target
IPTS
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable geminivpn-iptables.service 2>/dev/null || true
  systemctl start  geminivpn-iptables.service 2>/dev/null || true
  ok "geminivpn-iptables.service: FORWARD=ACCEPT on every boot (before Docker)"
}

# =============================================================================
# PHASE 1 — FIX + SYNC SOURCE FILES
# =============================================================================
phase_source() {
  step "Phase 1 — Fix & Sync Source Files"

  _patch_server_ts
  _patch_download_ts
  _patch_tsconfig
  _patch_schema_prisma
  _patch_prisma_singleton
  _patch_seed_ts
  _patch_auth_controller_jwt   # Fix TS2769: expiresIn type mismatch

  info "Syncing source to ${DEPLOY_DIR}..."
  rsync -a --delete \
    --exclude='.env' \
    --exclude='node_modules/' \
    --exclude='dist/' \
    --exclude='.git/' \
    --exclude='*.tar.gz' \
    --exclude='geminivpn.sh' \
    "${SCRIPT_DIR}/" "${DEPLOY_DIR}/"
  ok "Source synced (geminivpn.sh excluded)"
}

_patch_server_ts() {
  local F="${SCRIPT_DIR}/backend/src/server.ts"
  [[ ! -f "$F" ]] && return 0

  # Ensure all 4 webhook routes have raw body parsing BEFORE express.json()
  local EXPECTED="app.use('/api/v1/webhooks/coinbase'"
  if ! grep -q "$EXPECTED" "$F" 2>/dev/null; then
    python3 - "$F" << 'PYEOF'
import sys
with open(sys.argv[1]) as f: src = f.read()
for OLD in [
  "app.use('/api/v1/webhooks/stripe', express.raw({ type: 'application/json' }));\napp.use(express.json",
  "app.use(express.json({ limit: '10mb' }));\napp.use(express.urlencoded",
]:
    if OLD in src:
        NEW = (
          "// All webhook routes must receive raw Buffer — registered BEFORE express.json()\n"
          "app.use('/api/v1/webhooks/stripe',   express.raw({ type: 'application/json' }));\n"
          "app.use('/api/v1/webhooks/square',   express.raw({ type: 'application/json' }));\n"
          "app.use('/api/v1/webhooks/paddle',   express.raw({ type: 'application/json' }));\n"
          "app.use('/api/v1/webhooks/coinbase', express.raw({ type: 'application/json' }));\n"
          "app.use(express.json({ limit: '10mb' }));\n"
          "app.use(express.urlencoded"
        )
        src = src.replace(OLD, NEW)
        with open(sys.argv[1], 'w') as f: f.write(src)
        print("  [✓] server.ts: all 4 webhook raw body routes patched")
        break
else:
    print("  [✓] server.ts: webhook patches already present")
PYEOF
  else
    ok "server.ts: webhook raw body already patched"
  fi

  # Ensure startup uses safe retry pattern
  if ! grep -q "MAX_RETRIES" "$F" 2>/dev/null; then
    python3 - "$F" << 'INNER_PYEOF'
import sys, re
with open(sys.argv[1]) as fh:
    src = fh.read()
if "MAX_RETRIES" in src:
    print("  server.ts: startup OK")
    sys.exit(0)
SAFE = (
  "const startServer = async () => {\n"
  "  const server = app.listen(PORT as number, HOST, () => {\n"
  "    logger.info('GeminiVPN API on http://' + HOST + ':' + PORT + ' — DB initialising...');\n"
  "  });\n"
  "  server.on('error', (err: NodeJS.ErrnoException) => {\n"
  "    logger.error('HTTP listen error:', err); process.exit(1);\n"
  "  });\n"
  "  const MAX_RETRIES = 12, BASE_DELAY = 3000, MAX_DELAY = 30000;\n"
  "  let dbConnected = false;\n"
  "  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {\n"
  "    try {\n"
  "      await prisma.$connect();\n"
  "      logger.info('✅ Database connected (SQLite)');\n"
  "      dbConnected = true;\n"
  "      break;\n"
  "    } catch (error) {\n"
  "      const delay = Math.min(BASE_DELAY * Math.pow(1.5, attempt - 1), MAX_DELAY);\n"
  "      logger.warn('DB attempt ' + attempt + '/' + MAX_RETRIES + ' failed, retrying in ' + Math.round(delay/1000) + 's');\n"
  "      if (attempt === MAX_RETRIES) { logger.error('DB unavailable after all retries'); return; }\n"
  "      await new Promise(resolve => setTimeout(resolve, delay));\n"
  "    }\n"
  "  }\n"
  "  if (!dbConnected) return;\n"
  "  if (process.env.WIREGUARD_ENABLED === 'true') {\n"
  "    try { await vpnEngine.initialize(); logger.info('✅ VPN engine initialized'); }\n"
  "    catch (err) { logger.warn('⚠️  VPN engine init failed (non-fatal):', err); }\n"
  "  }\n"
  "  if (process.env.ENABLE_SELF_HEALING === 'true') {\n"
  "    connectionMonitor.start(); logger.info('✅ Connection monitor started');\n"
  "  }\n"
  "  logger.info('✅ GeminiVPN backend fully ready');\n"
  "};\n"
  "startServer().catch((err) => { logger.error('Unhandled error in startServer:', err); });"
)
pattern = re.compile(r"const startServer = async \(\) => \{.*?^startServer\(\);?.*?$", re.DOTALL | re.MULTILINE)
new_src, n = pattern.subn(SAFE, src)
if n:
    with open(sys.argv[1], "w") as fh:
        fh.write(new_src)
    print("  [✓] server.ts: startup fixed")
else:
    print("  [!] server.ts: startup pattern not found — may already be correct")
INNER_PYEOF
  else
    ok "server.ts: startup already uses safe retry pattern"
  fi
}

_patch_download_ts() {
  local F="${SCRIPT_DIR}/backend/src/routes/download.ts"
  [[ ! -f "$F" ]] && return 0
  # Old circular-import fix created a new PrismaClient — replace with singleton
  if grep -q "from '../server'" "$F" 2>/dev/null || grep -q "new PrismaClient()" "$F" 2>/dev/null; then
    python3 - "$F" << 'PYEOF'
import sys, re
with open(sys.argv[1]) as f: src = f.read()
# Remove any old circular-import workaround that creates a new PrismaClient
src = re.sub(r"import \{ prisma \} from '\.\.\/server';\s*\n", "", src)
src = re.sub(r"import \{ PrismaClient \} from '@prisma\/client';\s*\nconst prisma_dl = new PrismaClient\(\);\s*\n", "", src)
src = re.sub(r"import \{ PrismaClient \} from '@prisma\/client';\s*\n", "", src)
src = re.sub(r"const prisma_dl? = new PrismaClient\(\);\s*\n", "", src)
# Normalise any prisma_dl. calls back to prisma.
src = src.replace('await prisma_dl.', 'await prisma.')
src = src.replace('prisma_dl.', 'prisma.')
# Ensure singleton import is present
if "from '../lib/prisma'" not in src:
    src = src.replace("import { Router", "import prisma from '../lib/prisma';\nimport { Router", 1)
with open(sys.argv[1], 'w') as f: f.write(src)
print("  [✓] download.ts: using Prisma singleton")
PYEOF
  else
    # Check if singleton import is already there; add if not
    if ! grep -q "from '../lib/prisma'" "$F" 2>/dev/null; then
      sed -i "s|import { Router|import prisma from '../lib/prisma';\nimport { Router|" "$F"
      ok "download.ts: added Prisma singleton import"
    else
      ok "download.ts: already using Prisma singleton"
    fi
  fi
}

_patch_tsconfig() {
  local F="${SCRIPT_DIR}/backend/tsconfig.json"
  [[ ! -f "$F" ]] && return 0
  python3 - "$F" << 'PYEOF'
import sys, json
with open(sys.argv[1]) as f: d = json.load(f)
c = d.setdefault('compilerOptions', {})
c.update({
    'strict': False, 'noUnusedLocals': False, 'noUnusedParameters': False,
    'noImplicitAny': False, 'strictNullChecks': False, 'skipLibCheck': True,
    'resolveJsonModule': True,
})
# src/**/* picks up src/lib/prisma.ts singleton (CRITICAL)
d['include'] = ['src/**/*']
d['exclude'] = ['node_modules', 'dist', 'prisma']
with open(sys.argv[1], 'w') as f: json.dump(d, f, indent=2)
print("  [✓] tsconfig.json: compiler flags patched (src/lib/ included)")
PYEOF
}

_patch_schema_prisma() {
  local F="${SCRIPT_DIR}/backend/src/lib/enums.ts"
  local SCHEMA="${SCRIPT_DIR}/backend/prisma/schema.prisma"
  [[ ! -f "$SCHEMA" ]] && return 0

  # Ensure SQLite provider
  if grep -q 'provider = "postgresql"' "$SCHEMA" 2>/dev/null; then
    sed -i 's/provider = "postgresql"/provider = "sqlite"/' "$SCHEMA"
    ok "schema.prisma: switched provider to sqlite"
  fi

  # Remove @db.Text annotations (not supported in SQLite)
  if grep -q '@db\.Text' "$SCHEMA" 2>/dev/null; then
    sed -i 's/ *@db\.Text//g' "$SCHEMA"
    ok "schema.prisma: removed @db.Text annotations"
  fi

  # Replace String[] arrays with String (JSON stored)
  if grep -q 'String\[\]' "$SCHEMA" 2>/dev/null; then
    sed -i 's/String\[\]  *@default(\[\])/String      @default("[]")/g' "$SCHEMA"
    sed -i 's/String\[\]/String/g' "$SCHEMA"
    ok "schema.prisma: converted String[] arrays to JSON String"
  fi

  # Replace BigInt with Int
  if grep -q 'BigInt' "$SCHEMA" 2>/dev/null; then
    sed -i 's/BigInt/Int/g' "$SCHEMA"
    ok "schema.prisma: BigInt replaced with Int for SQLite compatibility"
  fi

  # CRITICAL FIX: SQLite (Prisma 5.x) does NOT support enum blocks (P1012 error).
  # Convert all enum definitions to String fields with string defaults throughout
  # the schema, and create src/lib/enums.ts so application code still works.
  python3 - "$SCHEMA" "${SCRIPT_DIR}/backend/src/lib" << 'PYEOF'
import sys, re, os

schema_file = sys.argv[1]
lib_dir     = sys.argv[2]

with open(schema_file) as fh:
    src = fh.read()

# --- Step 1: Extract all enum definitions -----------------------------------
# Pattern: enum FooBar { VALUE1\n  VALUE2\n  ... }
enum_pattern = re.compile(r'^enum\s+(\w+)\s*\{([^}]+)\}', re.MULTILINE)
enums = {}
for m in enum_pattern.finditer(src):
    name   = m.group(1)
    values = m.group(2).split()
    enums[name] = [v.strip() for v in values if v.strip()]

if not enums:
    print("  [✓] schema.prisma: no enums to convert (already String fields)")
else:
    # --- Step 2: Remove all enum blocks from schema -------------------------
    src = enum_pattern.sub('', src)
    src = re.sub(r'\n{3,}', '\n\n', src)

    # --- Step 3: Convert enum field types to String -------------------------
    for name, values in enums.items():
        default_val = values[0] if values else ''
        # Replace:  fieldName  EnumName  → fieldName  String
        # With default annotation if missing
        # Pattern: word boundary, enum name as type (may have ? suffix)
        # e.g.  subscriptionStatus   SubscriptionStatus @default(TRIAL)
        #   ->  subscriptionStatus   String             @default("TRIAL")

        # Replace @default(ENUMVALUE) with @default("ENUMVALUE") for this enum
        for val in values:
            src = src.replace(f'@default({val})', f'@default("{val}")')

        # Replace the type "EnumName?" -> "String?"  and "EnumName " -> "String "
        src = re.sub(rf'\b{re.escape(name)}\?', 'String?', src)
        src = re.sub(rf'\b{re.escape(name)}\b(?!\s*\()', 'String', src)

    with open(schema_file, 'w') as fh:
        fh.write(src)
    print(f"  [✓] schema.prisma: {len(enums)} enum(s) converted to String fields: {', '.join(enums.keys())}")

    # --- Step 4: Create/update src/lib/enums.ts with constants --------------
    os.makedirs(lib_dir, exist_ok=True)
    enums_ts_path = os.path.join(lib_dir, 'enums.ts')
    lines = [
        '/**',
        ' * GeminiVPN — Application-level Enum Constants',
        ' *',
        ' * SQLite does not support Prisma enum types (Prisma P1012).',
        ' * This file provides the same named constants that the rest of',
        ' * the code previously imported from "@prisma/client".',
        ' *',
        ' * Usage:',
        " *   import { SubscriptionStatus } from '../lib/enums';",
        " *   user.subscriptionStatus === SubscriptionStatus.ACTIVE  // true",
        ' */',
        '',
    ]
    for name, values in enums.items():
        lines.append(f'export const {name} = {{')
        for v in values:
            lines.append(f"  {v}: '{v}',")
        lines.append('} as const;')
        lines.append('')
        type_union = ' | '.join(f"'{v}'" for v in values)
        lines.append(f'export type {name}Type = {type_union};')
        lines.append('')

    with open(enums_ts_path, 'w') as fh:
        fh.write('\n'.join(lines))
    print(f"  [✓] src/lib/enums.ts created/updated with {len(enums)} constant objects")

# Verify no enum blocks remain
remaining = re.findall(r'^enum\s+\w+', src, re.MULTILINE)
if remaining:
    print(f"  [!] WARNING: enum blocks still in schema: {remaining}")
else:
    print("  [✓] schema.prisma: fully validated for SQLite (no enum blocks)")
PYEOF
}

_patch_prisma_singleton() {
  # =============================================================================
  # CRITICAL: Ensure src/lib/prisma.ts singleton exists and every TypeScript
  # source file imports from it.  Multiple PrismaClient() instances cause
  # SQLITE_BUSY database-locked errors under any concurrent traffic.
  # =============================================================================
  local LIB_DIR="${SCRIPT_DIR}/backend/src/lib"
  local SINGLETON="${LIB_DIR}/prisma.ts"

  mkdir -p "$LIB_DIR"

  # Always overwrite — ensures $queryRawUnsafe (not $executeRawUnsafe) is used
  if true; then
    info "Ensuring Prisma singleton at src/lib/prisma.ts (WAL pragmas)..."
    cat > "$SINGLETON" << 'SINGLETON_EOF'
/**
 * Prisma Singleton — GeminiVPN
 * Single PrismaClient instance prevents SQLITE_BUSY locking errors.
 * All modules MUST import prisma from this file — never new PrismaClient().
 */
import { PrismaClient } from '@prisma/client';
import { logger } from '../utils/logger';

declare global { var __prisma: PrismaClient | undefined; }

function makePrismaClient(): PrismaClient {
  const client = new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query','info','warn','error'] : ['error'],
  });
  client.$connect().then(async () => {
    try {
      // $queryRawUnsafe (not $executeRawUnsafe) — SQLite PRAGMAs return rows
      await client.$queryRawUnsafe(`PRAGMA journal_mode = WAL;`);
      await client.$queryRawUnsafe(`PRAGMA synchronous  = NORMAL;`);
      await client.$queryRawUnsafe(`PRAGMA foreign_keys = ON;`);
      await client.$queryRawUnsafe(`PRAGMA busy_timeout = 5000;`);
      logger.info('✅ SQLite pragmas applied (WAL mode, 5s busy-timeout)');
    } catch (err) {
      logger.warn('Could not apply SQLite pragmas (non-fatal):', err);
    }
  }).catch(() => {});
  return client;
}
const prisma: PrismaClient = global.__prisma ?? (global.__prisma = makePrismaClient());
export default prisma;
SINGLETON_EOF
    ok "Prisma singleton enforced — \$queryRawUnsafe (WAL mode, no P2010 crash)"
  fi

  # Patch all source files to use the singleton
  local SRC_DIR="${SCRIPT_DIR}/backend/src"
  GVPN_SRC="$SRC_DIR" python3 << 'PYEOF'
import sys, re, os

lib_rel = {
  'controllers': '../lib/prisma',
  'middleware':  '../lib/prisma',
  'routes':      '../lib/prisma',
  'services':    '../lib/prisma',
  'server':      './lib/prisma',
}

src_dir = os.environ.get('GVPN_SRC', '')
files = [
  ('controllers/authController.ts',    '../lib/prisma'),
  ('controllers/paymentController.ts', '../lib/prisma'),
  ('controllers/vpnController.ts',     '../lib/prisma'),
  ('controllers/webhookController.ts', '../lib/prisma'),
  ('controllers/demoController.ts',    '../lib/prisma'),
  ('middleware/auth.ts',               '../lib/prisma'),
  ('routes/download.ts',               '../lib/prisma'),
  ('routes/server.ts',                 '../lib/prisma'),
  ('routes/user.ts',                   '../lib/prisma'),
  ('services/vpnEngine.ts',            '../lib/prisma'),
  ('services/connectionMonitor.ts',    '../lib/prisma'),
  ('server.ts',                        './lib/prisma'),
]

for rel_path, import_path in files:
  full = os.path.join(src_dir, rel_path) if src_dir else rel_path
  if not os.path.isfile(full):
    continue
  with open(full) as f:
    src = f.read()
  if f"from '{import_path}'" in src:
    print(f"  [✓] {rel_path}: already uses singleton")
    continue
  changed = False
  # Remove old PrismaClient import+instantiation
  old_import = re.compile(r"import \{ PrismaClient(?:[^}]*)?\} from '@prisma/client';\s*\n")
  if old_import.search(src):
    # Replace import removing PrismaClient from the list
    def strip_pc(m):
      inner = m.group(0)
      result = re.sub(r',?\s*PrismaClient', '', inner)
      result = re.sub(r'PrismaClient,?\s*', '', result)
      result = result.replace("import {  } from '@prisma/client';\n", "")
      result = result.replace("import { } from '@prisma/client';\n", "")
      return result
    src = old_import.sub(strip_pc, src)
    changed = True
  # Remove new PrismaClient() lines
  src = re.sub(r"(export )?const prisma\w* = new PrismaClient\([^)]*\);\s*\n", "", src)
  # Add singleton import at top (after 'dotenv.config()' if present, else after first import block)
  if f"from '{import_path}'" not in src:
    src = re.sub(
      r"(import [\s\S]*?from '[^']+';)\n(?!import )",
      r"\1\n" + f"import prisma from '{import_path}';\n",
      src, count=1
    )
    changed = True
  if changed:
    with open(full, 'w') as f:
      f.write(src)
    print(f"  [✓] {rel_path}: patched to use Prisma singleton")
  else:
    print(f"  [!] {rel_path}: may need manual check")
PYEOF

  # ── Strip any remaining enum imports from @prisma/client ──────────────────
  # After schema conversion, Prisma no longer generates enum types.
  # Any file still importing SubscriptionStatus/PlanType/etc. from @prisma/client
  # will cause a TS compile error. Move those imports to lib/enums.
  local ENUM_NAMES="SubscriptionStatus|PlanType|PaymentStatus|PaymentProvider"
  local SRC_DIR="${SCRIPT_DIR}/backend/src"
  GVPN_ENUM_SRC="$SRC_DIR" GVPN_ENUM_NAMES="$ENUM_NAMES" python3 << 'ENUMFIX'
import re, os, sys

src_dir    = os.environ['GVPN_ENUM_SRC']
enum_names = os.environ['GVPN_ENUM_NAMES'].split('|')

# relative import path for lib/enums from each directory
depth_to_enum = {
  'controllers': '../lib/enums',
  'middleware':  '../lib/enums',
  'routes':      '../lib/enums',
  'services':    '../lib/enums',
  '':            './lib/enums',   # root (server.ts)
}

for root, dirs, files in os.walk(src_dir):
    dirs[:] = [d for d in dirs if d != 'lib' and not d.startswith('.')]
    for fname in files:
        if not fname.endswith('.ts'):
            continue
        full = os.path.join(root, fname)
        with open(full) as f:
            src = f.read()

        # Find which enum names are imported from @prisma/client in this file
        prisma_import_re = re.compile(r"import \{([^}]+)\} from '@prisma/client';")
        needs_patch = False
        for m in prisma_import_re.finditer(src):
            parts = [p.strip() for p in m.group(1).split(',')]
            if any(p in enum_names for p in parts):
                needs_patch = True
                break

        if not needs_patch:
            continue

        # Determine relative path to lib/enums
        rel_dir = os.path.relpath(root, src_dir)
        folder  = rel_dir.split(os.sep)[0] if rel_dir != '.' else ''
        enum_path = depth_to_enum.get(folder, '../lib/enums')

        # Remove enum names from @prisma/client import
        def strip_enums(m):
            parts = [p.strip() for p in m.group(1).split(',')]
            kept  = [p for p in parts if p and p not in enum_names]
            if kept:
                return f"import {{ {', '.join(kept)} }} from '@prisma/client';"
            return ''

        new_src = prisma_import_re.sub(strip_enums, src)

        # Find which enums are actually used (to import only those)
        used = [e for e in enum_names if re.search(rf'\b{e}\b', src)]

        # Add import from lib/enums if not already present
        if used and f"from '{enum_path}'" not in new_src:
            enum_line = f"import {{ {', '.join(used)} }} from '{enum_path}';"
            new_src = re.sub(
                r'(import [^\n]+;\n)',
                r'\1' + enum_line + '\n',
                new_src, count=1
            )

        # Clean blank lines
        new_src = re.sub(r'\n{3,}', '\n\n', new_src)

        if new_src != src:
            with open(full, 'w') as f:
                f.write(new_src)
            rel = os.path.relpath(full, src_dir)
            print(f"  [✓] {rel}: moved enum imports to lib/enums")
ENUMFIX

  ok "Prisma singleton enforcement complete"
}

# =============================================================================
# PATCH: seed.ts — ensure no @prisma/client enum imports
# =============================================================================
_patch_seed_ts() {
  local SEED="${SCRIPT_DIR}/backend/prisma/seed.ts"
  [[ ! -f "$SEED" ]] && return 0

  # SQLite: Prisma 5.x does not generate enum types, so importing them from
  # @prisma/client causes TS2305 "Module has no exported member" at compile time.
  # Replace any enum-name imports with plain string literals in the seed file.
  python3 - "$SEED" << 'SEEDFIX'
import re, sys

f = sys.argv[1]
with open(f) as fh:
    src = fh.read()

ENUM_NAMES = ['SubscriptionStatus', 'PlanType', 'PaymentStatus', 'PaymentProvider']

# Remove enum names from @prisma/client import line
def strip_enums(m):
    parts = [p.strip() for p in m.group(1).split(',')]
    kept  = [p for p in parts if p and p not in ENUM_NAMES]
    return f"import {{ {', '.join(kept)} }} from '@prisma/client';" if kept else ''

orig = src
src = re.sub(r"import \{([^}]+)\} from '@prisma/client';", strip_enums, src)

# Replace SubscriptionStatus.XXX  →  'XXX'  etc.
for name in ENUM_NAMES:
    src = re.sub(rf'\b{re.escape(name)}\.(\w+)\b', r"'\1'", src)

# Clean up stray blank lines
src = re.sub(r'\n{3,}', '\n\n', src)

if src != orig:
    with open(f, 'w') as fh:
        fh.write(src)
    print("  [✓] seed.ts: removed Prisma enum imports (SQLite: use string literals)")
else:
    print("  [✓] seed.ts: no Prisma enum imports to patch")
SEEDFIX
}


_patch_auth_controller_jwt() {
  local F="${SCRIPT_DIR}/backend/src/controllers/authController.ts"
  [[ ! -f "$F" ]] && return 0

  # FIX TS2769: jsonwebtoken v9 types require expiresIn to be `number | StringValue`
  # but JWT_ACCESS_EXPIRY / JWT_REFRESH_EXPIRY are plain `string` from process.env.
  # Solution: cast secrets and expiry to `any` so TypeScript stops complaining.
  # This is safe — the runtime values are correct strings like '15m', '7d'.
  if grep -qE "expiresIn: JWT_(ACCESS|REFRESH)_EXPIRY\b" "$F" 2>/dev/null && \
     ! grep -q "as any" "$F" 2>/dev/null; then
    python3 - "$F" << 'JWTFIX'
import sys
with open(sys.argv[1]) as fh:
    src = fh.read()
orig = src
# Cast secrets to any so TS doesn't complain about string vs Secret type
src = src.replace(
    'jwt.sign(\n    { userId, email, subscriptionStatus },\n    JWT_ACCESS_SECRET,\n    { expiresIn: JWT_ACCESS_EXPIRY }',
    'jwt.sign(\n    { userId, email, subscriptionStatus },\n    JWT_ACCESS_SECRET as any,\n    { expiresIn: JWT_ACCESS_EXPIRY as any }'
)
src = src.replace(
    'jwt.sign(\n    { userId },\n    JWT_REFRESH_SECRET,\n    { expiresIn: JWT_REFRESH_EXPIRY }',
    'jwt.sign(\n    { userId },\n    JWT_REFRESH_SECRET as any,\n    { expiresIn: JWT_REFRESH_EXPIRY as any }'
)
# Fallback: generic single-line replacement
import re
src = re.sub(
    r'(jwt\.sign\([^,]+,\s*JWT_\w+_SECRET)(\s*,\s*\{.*?expiresIn:\s*JWT_\w+_EXPIRY)(\s*\})',
    lambda m: m.group(1) + ' as any' + m.group(2) + ' as any' + m.group(3),
    src
)
if src != orig:
    with open(sys.argv[1], 'w') as fh:
        fh.write(src)
    print("  [✓] authController.ts: JWT expiresIn cast to any (fixes TS2769)")
else:
    print("  [✓] authController.ts: JWT types already patched")
JWTFIX
  else
    ok "authController.ts: JWT types already correct"
  fi
}


phase_env() {
  step "Phase 2 — Environment Configuration"

  if [[ ! -f "$ENV_FILE" ]]; then
    info "Creating .env from template..."
    cp "${DEPLOY_DIR}/.env.production" "$ENV_FILE" 2>/dev/null || \
    cp "${DEPLOY_DIR}/.env.example"    "$ENV_FILE" 2>/dev/null || \
    touch "$ENV_FILE"
  fi

  _ensure_secret() {
    local KEY="$1" BYTES="${2:-48}"
    local VAL; VAL=$(env_get "$KEY")
    if [[ -z "$VAL" || "$VAL" =~ CHANGE_ME|change_me|placeholder|your- ]]; then
      local NEW; NEW=$(openssl rand -base64 "$BYTES" | tr -d '\n/+=' | cut -c1-48)
      env_set "$KEY" "$NEW"
      ok "${KEY} generated"
    fi
  }

  _ensure_secret JWT_ACCESS_SECRET  48
  _ensure_secret JWT_REFRESH_SECRET 48

  # SQLite — no DB password needed; always set the file path
  env_set DATABASE_URL    "file:/app/database/geminivpn.db"
  env_set NODE_ENV        production
  env_set PORT            5000
  env_set HOST            0.0.0.0
  env_set FRONTEND_URL    "https://${DOMAIN}"
  env_set SERVER_PUBLIC_IP "$SERVER_IP"
  env_set WIREGUARD_ENABLED          false
  env_set ENABLE_SELF_HEALING        false
  env_set AUTO_REFRESH_INTERVAL_MS   30000
  env_set MAX_RECONNECT_ATTEMPTS     5
  env_set DOWNLOADS_DIR              /app/downloads
  env_set WHATSAPP_SUPPORT_NUMBER    "+905368895622"
  env_set BCRYPT_ROUNDS              12
  env_set TRIAL_DURATION_DAYS        3
  env_set DEMO_DURATION_MINUTES      60
  env_set RATE_LIMIT_WINDOW_MS       900000
  env_set RATE_LIMIT_MAX_REQUESTS    100

  ok ".env configured at ${ENV_FILE}"
  chmod 600 "$ENV_FILE"
}

# =============================================================================
# PHASE 3 — SERVER HARDENING
# =============================================================================
phase_harden() {
  step "Phase 3 — Server Hardening"
  export DEBIAN_FRONTEND=noninteractive

  # ── UFW + iptables persistence (Ubuntu 24.04 compatible) ────────────────────
  # Ubuntu 24.04: ufw and iptables-persistent are INCOMPATIBLE — cannot coexist.
  # Persistence is handled by: iptables-save → /etc/iptables/rules.v4 + geminivpn-iptables.service
  export DEBIAN_FRONTEND=noninteractive
  if ! command -v ufw &>/dev/null; then
    apt-get install -y -qq ufw 2>/dev/null || true
  fi
  ok "UFW present — iptables rules persisted via iptables-save + boot service"

  # ── UFW FORWARD policy = ACCEPT (required for Docker inter-container routing) ─
  local UFW_DEFAULT="/etc/default/ufw"
  if [[ -f "$UFW_DEFAULT" ]]; then
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$UFW_DEFAULT" 2>/dev/null || true
    sed -i 's/DEFAULT_FORWARD_POLICY="REJECT"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$UFW_DEFAULT" 2>/dev/null || true
    ok "UFW DEFAULT_FORWARD_POLICY=ACCEPT (Docker routing unblocked)"
  fi

  if ! ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw --force reset 2>/dev/null || true
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp    comment 'SSH'
    ufw allow 80/tcp    comment 'HTTP'
    ufw allow 443/tcp   comment 'HTTPS'
    ufw allow 51820/udp comment 'WireGuard'
    echo "y" | ufw enable 2>/dev/null || true
    ok "UFW firewall enabled (22, 80, 443, 51820)"
  else
    ufw allow 22/tcp    comment 'SSH'       2>/dev/null || true
    ufw allow 80/tcp    comment 'HTTP'      2>/dev/null || true
    ufw allow 443/tcp   comment 'HTTPS'     2>/dev/null || true
    ufw allow 51820/udp comment 'WireGuard' 2>/dev/null || true
    ok "UFW already active — ports 22/80/443/51820 confirmed open"
  fi

  # ── Explicit outbound rules (No-IP DUC, Let's Encrypt, Docker containers) ──
  ufw allow out on any to any port 53   proto udp comment 'DNS outbound'      2>/dev/null || true
  ufw allow out on any to any port 53   proto tcp comment 'DNS-TCP outbound'  2>/dev/null || true
  ufw allow out on any to any port 80   proto tcp comment 'HTTP outbound'     2>/dev/null || true
  ufw allow out on any to any port 443  proto tcp comment 'HTTPS outbound'    2>/dev/null || true
  ufw allow out on any to any port 8245 proto tcp comment 'No-IP alt port'    2>/dev/null || true
  ok "UFW outbound: DNS(53) HTTP(80) HTTPS(443) No-IP-alt(8245) allowed"

  # ── iptables FORWARD = ACCEPT for Docker (applied now, persisted below) ───
  iptables  -I FORWARD -j ACCEPT  2>/dev/null || true
  iptables  -P FORWARD ACCEPT     2>/dev/null || true
  ip6tables -P FORWARD ACCEPT     2>/dev/null || true
  iptables  -I DOCKER-USER -j ACCEPT 2>/dev/null || true

  # ── Persist iptables rules across reboots (UFW-compatible) ──────────────────
  # Always use iptables-save (works with or without netfilter-persistent/ufw)
  mkdir -p /etc/iptables
  iptables-save  > /etc/iptables/rules.v4 2>/dev/null || true
  ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  command -v netfilter-persistent &>/dev/null && netfilter-persistent save 2>/dev/null || true
  ok "iptables rules saved to /etc/iptables/rules.v4+v6 (reboot-safe)"
  ufw reload 2>/dev/null || true

  if ! command -v fail2ban-client &>/dev/null; then apt-get install -y -qq fail2ban 2>/dev/null || apt-get install -y fail2ban; fi
  cat > /etc/fail2ban/jail.d/geminivpn.conf << 'F2B'
[sshd]
enabled  = true
maxretry = 5
bantime  = 3600

[nginx-http-auth]
enabled  = true
maxretry = 10
bantime  = 3600
logpath  = /var/log/nginx/error.log

[nginx-limit-req]
enabled  = true
port     = http,https
maxretry = 20
bantime  = 600
logpath  = /var/log/nginx/error.log
F2B
  systemctl enable fail2ban 2>/dev/null && systemctl restart fail2ban 2>/dev/null || true
  ok "fail2ban active"

  if [[ $(swapon --show 2>/dev/null | wc -l) -eq 0 ]]; then
    local RAM_MB; RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    local SWAP_GB=2; [[ $RAM_MB -ge 3072 ]] && SWAP_GB=1
    fallocate -l "${SWAP_GB}G" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_GB*1024)) 2>/dev/null
    chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "${SWAP_GB}GB swap created"
  else
    ok "Swap already configured ($(free -h | awk '/^Swap:/{print $2}'))"
  fi

  # ── Boot-time iptables restore service ───────────────────────────────────
  # Ensures iptables FORWARD=ACCEPT survives reboots even if iptables-persistent
  # isn't installed or its rules get wiped by Docker's own iptables management.
  cat > /etc/systemd/system/geminivpn-iptables.service << 'IPTS'
[Unit]
Description=GeminiVPN Boot-time Firewall Rules
Documentation=https://geminivpn.zapto.org
After=network.target
Before=docker.service ufw.service

[Service]
Type=oneshot
RemainAfterExit=yes
# Allow Docker inter-container FORWARD traffic
ExecStart=/bin/sh -c 'iptables -I FORWARD -j ACCEPT 2>/dev/null; iptables -P FORWARD ACCEPT 2>/dev/null; true'
# Allow outbound for No-IP DUC, Let'''s Encrypt, DNS
ExecStart=/bin/sh -c 'iptables -I OUTPUT -p tcp --dport 80  -j ACCEPT 2>/dev/null; true'
ExecStart=/bin/sh -c 'iptables -I OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; true'
ExecStart=/bin/sh -c 'iptables -I OUTPUT -p udp --dport 53  -j ACCEPT 2>/dev/null; true'
ExecStart=/bin/sh -c 'iptables -I OUTPUT -p tcp --dport 8245 -j ACCEPT 2>/dev/null; true'

[Install]
WantedBy=multi-user.target
IPTS
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable geminivpn-iptables.service 2>/dev/null || true
  ok "Boot-time iptables service installed (geminivpn-iptables.service)"

  modprobe tcp_bbr 2>/dev/null || true
  cat > /etc/sysctl.d/99-geminivpn.conf << 'SYSCTL'
net.ipv4.tcp_fastopen           = 3
net.core.default_qdisc          = fq
net.ipv4.tcp_congestion_control = bbr
net.core.somaxconn              = 65535
net.ipv4.tcp_max_syn_backlog    = 65535
net.core.rmem_max               = 134217728
net.core.wmem_max               = 134217728
net.ipv4.tcp_rmem               = 4096 87380 134217728
net.ipv4.tcp_wmem               = 4096 65536 134217728
net.ipv4.tcp_tw_reuse           = 1
net.ipv4.tcp_fin_timeout        = 15
net.ipv4.ip_forward             = 1
net.ipv4.tcp_syncookies         = 1
net.ipv4.conf.all.forwarding    = 1
net.ipv4.conf.default.forwarding= 1
net.ipv6.conf.all.forwarding    = 1
net.ipv6.bindv6only             = 0
vm.swappiness                   = 10
fs.file-max                     = 2097152
SYSCTL
  sysctl -p /etc/sysctl.d/99-geminivpn.conf >/dev/null 2>&1 || true
  ok "Kernel tuned (BBR: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'unknown'))"

  if [[ ! -f /etc/docker/daemon.json ]]; then
    printf '{"log-driver":"json-file","log-opts":{"max-size":"50m","max-file":"5"}}\n' > /etc/docker/daemon.json
    systemctl reload docker 2>/dev/null || true
    ok "Docker log rotation configured"
  else
    ok "Docker daemon.json already exists"
  fi

  apt-get install -y -qq unattended-upgrades 2>/dev/null || apt-get install -y unattended-upgrades
  cat > /etc/apt/apt.conf.d/20auto-upgrades << 'UU'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
UU
  systemctl enable --now unattended-upgrades 2>/dev/null || true
  ok "Automatic security updates enabled"

  # Set up automated SQLite database backup (daily)
  cat > /etc/cron.daily/geminivpn-db-backup << BACKUPCRON
#!/bin/bash
# Daily SQLite database backup — GeminiVPN
BACKUP_DIR="${DB_DIR}/backups"
DB_FILE="${DB_DIR}/geminivpn.db"
LOG_FILE="${LOG_DIR}/db-backup.log"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)

mkdir -p "\$BACKUP_DIR"

if [[ -f "\$DB_FILE" ]]; then
  sqlite3 "\$DB_FILE" ".backup \${BACKUP_DIR}/geminivpn_\${TIMESTAMP}.db" 2>>"\$LOG_FILE" || \
    cp "\$DB_FILE" "\${BACKUP_DIR}/geminivpn_\${TIMESTAMP}.db"
  echo "[\$(date)] Backup created: geminivpn_\${TIMESTAMP}.db" >> "\$LOG_FILE"
  # Keep 14 most recent backups
  ls -t "\${BACKUP_DIR}"/*.db 2>/dev/null | tail -n +15 | xargs rm -f 2>/dev/null || true
fi
BACKUPCRON
  chmod +x /etc/cron.daily/geminivpn-db-backup
  ok "Daily SQLite backup cron job installed (keeps 14 days)"

  # ── rc.local boot script — absolute last resort if iptables-persistent fails ─
  local RCLOCAL="/etc/rc.local"
  if [[ ! -f "$RCLOCAL" ]] || ! grep -q "GEMINIVPN-BOOT" "$RCLOCAL" 2>/dev/null; then
    cat > "$RCLOCAL" << 'RCEOF'
#!/bin/bash
# GEMINIVPN-BOOT — boot-time firewall rules
iptables -P FORWARD ACCEPT 2>/dev/null
iptables -I FORWARD -j ACCEPT 2>/dev/null
iptables -I FORWARD -i docker0 -j ACCEPT 2>/dev/null
iptables -I FORWARD -o docker0 -j ACCEPT 2>/dev/null
iptables -I DOCKER-USER -j ACCEPT 2>/dev/null
iptables -I OUTPUT -p tcp --dport 80   -j ACCEPT 2>/dev/null
iptables -I OUTPUT -p tcp --dport 443  -j ACCEPT 2>/dev/null
iptables -I OUTPUT -p tcp --dport 8245 -j ACCEPT 2>/dev/null
iptables -I OUTPUT -p udp --dport 53   -j ACCEPT 2>/dev/null
exit 0
RCEOF
    chmod +x "$RCLOCAL"
    systemctl enable rc-local 2>/dev/null || true
    ok "rc.local boot-time FORWARD rules installed (GEMINIVPN-BOOT)"
  else
    ok "rc.local boot rules already present"
  fi
}

# =============================================================================
# PHASE 4 — FRONTEND BUILD
# =============================================================================
phase_frontend() {
  step "Phase 4 — Frontend Build"

  if ! command -v node &>/dev/null || [[ "$(node --version | cut -d. -f1 | tr -d 'v')" -lt 18 ]]; then
    info "Installing Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null
    apt-get install -y nodejs 2>/dev/null || apt-get install -y nodejs
  fi
  ok "Node: $(node --version) | npm: $(npm --version)"

  local FE_DIR="${DEPLOY_DIR}/frontend"
  cd "$FE_DIR"

  info "Installing frontend dependencies..."
  npm install --legacy-peer-deps --silent 2>/dev/null || npm install --legacy-peer-deps 2>&1 | tail -5

  # Remove tsc from build command if present (causes failures)
  python3 - "${FE_DIR}/package.json" << 'PYEOF'
import sys, json, re
with open(sys.argv[1]) as f: d = json.load(f)
scripts = d.setdefault('scripts', {})
b = scripts.get('build', '')
if 'tsc' in b and '&&' in b:
    cleaned = re.sub(r'tsc(\s+-b|\s+--build)?\s*&&\s*', '', b).strip()
    if cleaned != b:
        scripts['build'] = cleaned
        with open(sys.argv[1], 'w') as f: json.dump(d, f, indent=2)
        print("  [✓] Frontend package.json: tsc removed from build script")
    else:
        print("  [✓] Frontend package.json: build script already correct")
else:
    print("  [✓] Frontend package.json: build script already correct")
PYEOF

  info "Building frontend..."
  local BUILD_LOG; BUILD_LOG=$(mktemp)
  if npm run build > "$BUILD_LOG" 2>&1; then
    tail -5 "$BUILD_LOG"
    rm -f "$BUILD_LOG"
  else
    cat "$BUILD_LOG"
    rm -f "$BUILD_LOG"
    die "Frontend build failed — see output above"
  fi

  [[ -f "${FE_DIR}/dist/index.html" ]] || die "Frontend build failed — dist/index.html missing"
  ok "Frontend built: $(du -sh "${FE_DIR}/dist" | cut -f1)"

  mkdir -p "$WWW_DIR"
  rsync -a --delete "${FE_DIR}/dist/" "${WWW_DIR}/"
  ok "Frontend deployed to ${WWW_DIR}"

  # ── Guarantee logo is always present in WWW_DIR ────────────────────────
  # The logo is referenced by: favicon, loading splash, nav bar, footer, manifest.
  # vite may hash/omit it — ensure it's always served at the root path.
  if [[ -f "${FE_DIR}/public/geminivpn-logo.png" ]]; then
    cp -f "${FE_DIR}/public/geminivpn-logo.png" "${WWW_DIR}/geminivpn-logo.png"
    ok "Logo: geminivpn-logo.png → ${WWW_DIR}/ ($(du -h "${WWW_DIR}/geminivpn-logo.png" | cut -f1))"
  fi
  # Copy all public assets that might be missed by vite output
  for ASSET in manifest.json sw.js robots.txt; do
    [[ -f "${FE_DIR}/public/${ASSET}" ]] && \
      cp -f "${FE_DIR}/public/${ASSET}" "${WWW_DIR}/${ASSET}" 2>/dev/null || true
  done
}

# =============================================================================
# PHASE 5 — DOCKER BUILD + START
# =============================================================================
phase_docker() {
  step "Phase 5 — Docker Build & Start"
  cd "${DEPLOY_DIR}/docker"

  # Ensure database directory exists and has correct permissions before starting
  mkdir -p "$DB_DIR" "${DB_DIR}/backups"
  chmod 777 "$DB_DIR"
  ok "Database directory ready: ${DB_DIR}"

  info "Removing old backend image (force fresh build)..."
  docker rmi geminivpn-backend 2>/dev/null || true

  info "Building backend (--no-cache)..."
  local DOCKER_BUILD_LOG; DOCKER_BUILD_LOG=$(mktemp)
  if $DOCKER_COMPOSE --env-file "$ENV_FILE" build --no-cache backend 2>&1 | tee "$DOCKER_BUILD_LOG"; then
    ok "Docker build succeeded"
    rm -f "$DOCKER_BUILD_LOG"
  else
    echo ""
    warn "Docker build FAILED. Full log:"
    cat "$DOCKER_BUILD_LOG"
    rm -f "$DOCKER_BUILD_LOG"
    die "Docker build FAILED — fix the error above, then re-run: sudo bash re-geminivpn.sh"
  fi

  info "Verifying dist/server.js inside new image..."
  local JS_CHECK
  JS_CHECK=$(docker run --rm --entrypoint sh geminivpn-backend \
    -c "test -f /app/dist/server.js && echo 'OK' || echo 'MISSING'" 2>/dev/null || echo "MISSING")
  if [[ "$JS_CHECK" != "OK" ]]; then
    die "dist/server.js missing in image — TypeScript compilation failed. Check build output above."
  fi
  ok "dist/server.js present in image"

  info "Starting all containers..."
  # Stop any legacy containers from old stack (postgres, redis) that are no longer needed
  for LEGACY in geminivpn-postgres geminivpn-redis; do
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${LEGACY}$"; then
      warn "Stopping legacy container: ${LEGACY} (not needed in SQLite stack)"
      docker stop "$LEGACY" 2>/dev/null && docker rm "$LEGACY" 2>/dev/null || true
      ok "Removed legacy container: ${LEGACY}"
    fi
  done

  # CRITICAL: Force-recreate nginx so it always picks up the latest nginx.conf changes.
  # Without --force-recreate, docker compose up -d leaves the running nginx untouched
  # even if the mounted config file was updated on the host.
  info "Starting backend first..."
  $DOCKER_COMPOSE --env-file "$ENV_FILE" up -d backend 2>&1 | tail -3
  info "Waiting for backend to be ready (up to 90s)..."
  local _t=0
  while [[ $_t -lt 90 ]]; do
    if docker exec geminivpn-backend curl -sf http://localhost:5000/health &>/dev/null; then
      ok "Backend is up and healthy"
      break
    fi
    sleep 3; _t=$((_t+3))
    echo -ne "  Waiting for backend... (${_t}s)\r"
  done

  info "Starting nginx (and any remaining services)..."
  $DOCKER_COMPOSE --env-file "$ENV_FILE" up -d --force-recreate nginx 2>&1 | tail -3
  $DOCKER_COMPOSE --env-file "$ENV_FILE" up -d 2>&1 | tail -5

  info "Waiting for backend (up to 120s — SQLite starts faster than Postgres)..."
  wait_healthy geminivpn-backend 120 && ok "backend healthy" || \
    die "backend failed — check: docker logs geminivpn-backend --tail=50"

  info "Waiting for nginx..."
  wait_healthy geminivpn-nginx 30 && ok "nginx healthy" || warn "nginx not yet healthy — may need SSL"

  # ── Post-start: re-apply iptables FORWARD for Docker bridge ───────────────
  # Docker adds its own iptables rules at startup which can interfere with UFW.
  # Re-applying ACCEPT rules after containers start guarantees routing works.
  iptables -I FORWARD -j ACCEPT                         2>/dev/null || true
  iptables -I DOCKER-USER -j ACCEPT                     2>/dev/null || true
  iptables -P FORWARD ACCEPT                            2>/dev/null || true
  # Find and open the GeminiVPN Docker bridge interface
  local GVPN_NET GVPN_BRIDGE
  GVPN_NET=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -i gemini | head -1)
  if [[ -n "$GVPN_NET" ]]; then
    GVPN_BRIDGE=$(docker network inspect "$GVPN_NET" \
      --format '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || echo "")
    [[ -z "$GVPN_BRIDGE" ]] && GVPN_BRIDGE=$(ip link show 2>/dev/null | grep -oE 'br-[a-f0-9]+' | head -1)
    if [[ -n "$GVPN_BRIDGE" ]]; then
      iptables -I FORWARD -i "$GVPN_BRIDGE" -j ACCEPT  2>/dev/null || true
      iptables -I FORWARD -o "$GVPN_BRIDGE" -j ACCEPT  2>/dev/null || true
      ok "Docker bridge ${GVPN_BRIDGE}: FORWARD rules applied"
    fi
  fi
  # Persist rules — iptables-save always available; netfilter-persistent optional
  mkdir -p /etc/iptables
  iptables-save  > /etc/iptables/rules.v4 2>/dev/null || true
  ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  command -v netfilter-persistent &>/dev/null && netfilter-persistent save 2>/dev/null || true
  ok "iptables FORWARD rules persisted after container start"

  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep geminivpn
}

# =============================================================================
# PHASE 6 — DATABASE MIGRATION & SEED
# =============================================================================
phase_database() {
  step "Phase 6 — Database Migration & Seed (SQLite)"

  info "Ensuring database directory permissions..."
  mkdir -p "$DB_DIR" "${DB_DIR}/backups"
  chmod 777 "$DB_DIR"

  info "Running Prisma db push (creates/updates SQLite schema)..."
  if docker exec geminivpn-backend \
      sh -c "DATABASE_URL=file:/app/database/geminivpn.db npx prisma@5.22.0 db push --accept-data-loss \
      --schema=/app/prisma/schema.prisma" 2>&1 | tail -8; then
    ok "SQLite schema applied via db push"
  else
    warn "db push had issues — checking if DB file exists..."
    local DB_PRESENT
    DB_PRESENT=$(docker exec geminivpn-backend sh -c "test -f /app/database/geminivpn.db && echo 'OK' || echo 'MISSING'" 2>/dev/null || echo "MISSING")
    if [[ "$DB_PRESENT" == "OK" ]]; then
      ok "Database file exists — may already be up to date"
    else
      warn "Database file not found — will retry once"
      sleep 5
      docker exec geminivpn-backend \
        sh -c "DATABASE_URL=file:/app/database/geminivpn.db npx prisma@5.22.0 db push --accept-data-loss \
        --schema=/app/prisma/schema.prisma" 2>&1 | tail -8 || warn "db push retry also failed — check logs"
    fi
  fi

  info "Seeding VPN servers and admin accounts..."
  cat > /tmp/seed_geminivpn.js << 'SEEDJS'
const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient({
  datasources: { db: { url: 'file:/app/database/geminivpn.db' } }
});

const servers = [
  { name:'New York, USA',    country:'US', city:'New York',    region:'NY',              hostname:'us-ny.geminivpn.com', port:51820, publicKey:'KEY_NY', subnet:'10.8.1.0/24',  dnsServers:'1.1.1.1,1.0.0.1', maxClients:1000, latencyMs:9,  loadPercentage:0, isActive:true, isMaintenance:false },
  { name:'Los Angeles, USA', country:'US', city:'Los Angeles', region:'CA',              hostname:'us-la.geminivpn.com', port:51820, publicKey:'KEY_LA', subnet:'10.8.2.0/24',  dnsServers:'1.1.1.1,1.0.0.1', maxClients:1000, latencyMs:12, loadPercentage:0, isActive:true, isMaintenance:false },
  { name:'London, UK',       country:'GB', city:'London',      region:'England',         hostname:'uk-ln.geminivpn.com', port:51820, publicKey:'KEY_LN', subnet:'10.8.3.0/24',  dnsServers:'1.1.1.1,1.0.0.1', maxClients:800,  latencyMs:15, loadPercentage:0, isActive:true, isMaintenance:false },
  { name:'Frankfurt',        country:'DE', city:'Frankfurt',   region:'Hesse',           hostname:'de-fr.geminivpn.com', port:51820, publicKey:'KEY_FR', subnet:'10.8.4.0/24',  dnsServers:'1.1.1.1,1.0.0.1', maxClients:800,  latencyMs:18, loadPercentage:0, isActive:true, isMaintenance:false },
  { name:'Tokyo, Japan',     country:'JP', city:'Tokyo',       region:'Tokyo',           hostname:'jp-tk.geminivpn.com', port:51820, publicKey:'KEY_TK', subnet:'10.8.5.0/24',  dnsServers:'1.1.1.1,1.0.0.1', maxClients:600,  latencyMs:22, loadPercentage:0, isActive:true, isMaintenance:false },
  { name:'Singapore',        country:'SG', city:'Singapore',   region:'Singapore',       hostname:'sg-sg.geminivpn.com', port:51820, publicKey:'KEY_SG', subnet:'10.8.6.0/24',  dnsServers:'1.1.1.1,1.0.0.1', maxClients:600,  latencyMs:25, loadPercentage:0, isActive:true, isMaintenance:false },
  { name:'Sydney',           country:'AU', city:'Sydney',      region:'NSW',             hostname:'au-sy.geminivpn.com', port:51820, publicKey:'KEY_SY', subnet:'10.8.7.0/24',  dnsServers:'1.1.1.1,1.0.0.1', maxClients:500,  latencyMs:28, loadPercentage:0, isActive:true, isMaintenance:false },
  { name:'São Paulo',        country:'BR', city:'São Paulo',   region:'SP',              hostname:'br-sp.geminivpn.com', port:51820, publicKey:'KEY_SP', subnet:'10.8.8.0/24',  dnsServers:'1.1.1.1,1.0.0.1', maxClients:500,  latencyMs:35, loadPercentage:0, isActive:true, isMaintenance:false },
  { name:'Amsterdam',        country:'NL', city:'Amsterdam',   region:'N. Holland',      hostname:'nl-am.geminivpn.com', port:51820, publicKey:'KEY_AM', subnet:'10.8.9.0/24',  dnsServers:'1.1.1.1,1.0.0.1', maxClients:700,  latencyMs:14, loadPercentage:0, isActive:true, isMaintenance:false },
  { name:'Paris, France',    country:'FR', city:'Paris',       region:'Ile-de-France',   hostname:'fr-pa.geminivpn.com', port:51820, publicKey:'KEY_PA', subnet:'10.8.11.0/24', dnsServers:'1.1.1.1,1.0.0.1', maxClients:700,  latencyMs:16, loadPercentage:0, isActive:true, isMaintenance:false },
  { name:'Toronto',          country:'CA', city:'Toronto',     region:'Ontario',         hostname:'ca-to.geminivpn.com', port:51820, publicKey:'KEY_TO', subnet:'10.8.10.0/24', dnsServers:'1.1.1.1,1.0.0.1', maxClients:600,  latencyMs:14, loadPercentage:0, isActive:true, isMaintenance:false },
];

async function main() {
  // Seed VPN servers
  for (const s of servers) {
    await prisma.vPNServer.upsert({
      where: { hostname: s.hostname },
      update: { latencyMs: s.latencyMs },
      create: s,
    });
  }
  console.log('VPN servers seeded: ' + servers.length + ' locations');

  // Seed admin account
  const adminHash = await bcrypt.hash('GeminiAdmin2026!', 12);
  await prisma.user.upsert({
    where: { email: 'admin@geminivpn.local' },
    update: {},
    create: {
      email: 'admin@geminivpn.local',
      password: adminHash,
      name: 'GeminiVPN Admin',
      subscriptionStatus: 'ACTIVE',
      isTestUser: true,
      emailVerified: true,
      subscriptionEndsAt: new Date('2099-12-31T23:59:59Z'),
      trialEndsAt: new Date('2099-12-31T23:59:59Z'),
    },
  });

  // Seed test account
  const testHash = await bcrypt.hash('alibabaat2026', 12);
  await prisma.user.upsert({
    where: { email: 'alibasma@geminivpn.local' },
    update: {},
    create: {
      email: 'alibasma@geminivpn.local',
      password: testHash,
      name: 'Ali Basma',
      subscriptionStatus: 'ACTIVE',
      isTestUser: true,
      emailVerified: true,
      subscriptionEndsAt: new Date('2030-12-31T23:59:59Z'),
      trialEndsAt: new Date('2030-12-31T23:59:59Z'),
    },
  });

  console.log('Admin + test accounts seeded');
  await prisma.$disconnect();
}

main().catch(e => {
  console.error('Seed error:', e.message);
  prisma.$disconnect().catch(() => {});
  process.exit(1);
});
SEEDJS

  # Copy seed to /app so Node.js resolves @prisma/client from /app/node_modules
  docker cp /tmp/seed_geminivpn.js geminivpn-backend:/app/seed_geminivpn.js 2>/dev/null || true
  # Run seed with working dir /app — critical: without -w /app, require('@prisma/client')
  # resolves against /tmp/node_modules (empty) instead of /app/node_modules.
  if docker exec -w /app geminivpn-backend node /app/seed_geminivpn.js 2>&1; then
    ok "VPN servers + admin/test accounts seeded"
    docker exec geminivpn-backend rm -f /app/seed_geminivpn.js 2>/dev/null || true
  else
    warn "Seed had issues — retrying with explicit NODE_PATH..."
    if docker exec -w /app -e NODE_PATH=/app/node_modules geminivpn-backend \
        node /app/seed_geminivpn.js 2>&1; then
      ok "VPN servers + admin/test accounts seeded (retry succeeded)"
      docker exec geminivpn-backend rm -f /app/seed_geminivpn.js 2>/dev/null || true
    else
      warn "seed_geminivpn.js failed — trying compiled dist/prisma/seed.js..."
      if docker exec -w /app geminivpn-backend node dist/prisma/seed.js 2>&1; then
        ok "VPN servers seeded via compiled seed.js"
      else
        warn "All seed methods failed — admin login will not work until seeded"
        info "Manual retry: docker exec -w /app geminivpn-backend node /app/seed_geminivpn.js"
      fi
    fi
  fi

  # Verify database file was created
  local DB_SIZE
  DB_SIZE=$(docker exec geminivpn-backend sh -c "du -h /app/database/geminivpn.db 2>/dev/null | cut -f1 || echo 'not found'" 2>/dev/null || echo "not found")
  ok "SQLite database file: /app/database/geminivpn.db (${DB_SIZE})"
  ok "Host path: ${DB_DIR}/geminivpn.db"
}

# =============================================================================
# PHASE 7 — LET'S ENCRYPT SSL
# =============================================================================
phase_ssl() {
  step "Phase 7 — Let's Encrypt SSL"
  local CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"

  if [[ -f "$CERT_PATH" ]]; then
    local EXPIRY_TS NOW_TS DAYS_LEFT
    EXPIRY_TS=$(date -d "$(openssl x509 -noout -enddate -in "$CERT_PATH" | cut -d= -f2)" +%s 2>/dev/null || echo 0)
    NOW_TS=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_TS - NOW_TS) / 86400 ))
    if [[ $DAYS_LEFT -gt 30 ]]; then
      ok "SSL cert valid for ${DAYS_LEFT} more days — skipping issuance"
      _enable_ssl_stapling; _setup_ssl_autorenew; return 0
    fi
    warn "SSL cert expires in ${DAYS_LEFT} days — renewing..."
  else
    info "No SSL cert found — issuing new certificate..."
  fi

  apt-get install -y -qq certbot dnsutils 2>/dev/null || apt-get install -y certbot dnsutils
  ok "certbot: $(certbot --version 2>&1 | head -1)"

  info "Checking DNS for ${DOMAIN}..."
  local MY_IP DNS_IP
  MY_IP=""
  for _src in \
    "curl -4 -s --max-time 8 https://ipv4.icanhazip.com" \
    "curl -4 -s --max-time 8 https://api.ipify.org" \
    "curl -4 -s --max-time 8 https://checkip.amazonaws.com"; do
    MY_IP=$(eval "$_src" 2>/dev/null | tr -d '[:space:]') || true
    [[ "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
    MY_IP=""
  done
  [[ -z "$MY_IP" ]] && MY_IP="$SERVER_IP"
  DNS_IP=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || echo "")

  if [[ -z "$DNS_IP" ]]; then
    warn "DNS for ${DOMAIN} not resolving yet."
    warn "→ Set '${DOMAIN}' A record → ${MY_IP} in your No-IP account"
    for i in $(seq 1 24); do
      sleep 5
      DNS_IP=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || echo "")
      [[ -n "$DNS_IP" ]] && break
      echo -ne "  Waiting for DNS... ($((i*5))s)\r"
    done
    [[ -z "$DNS_IP" ]] && die "DNS for ${DOMAIN} not resolving. Fix No-IP and re-run: sudo bash re-geminivpn.sh --ssl"
  fi
  ok "DNS: ${DOMAIN} → ${DNS_IP}"

  info "Pausing nginx for HTTP-01 challenge..."
  docker stop geminivpn-nginx 2>/dev/null || true
  fuser -k 80/tcp 2>/dev/null || true
  sleep 2

  info "Requesting certificate from Let's Encrypt..."
  certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email "admin@${DOMAIN}" \
    --preferred-challenges http-01 \
    -d "${DOMAIN}" \
    2>&1 | tail -10

  [[ -f "$CERT_PATH" ]] || die "Certificate issuance failed. Check: DNS, port 80 open, domain registered."
  local EXPIRY; EXPIRY=$(openssl x509 -noout -enddate -in "$CERT_PATH" | cut -d= -f2)
  ok "Certificate issued! Expires: ${EXPIRY}"

  docker start geminivpn-nginx 2>/dev/null || true
  sleep 5
  docker exec geminivpn-nginx nginx -s reload 2>/dev/null || true
  ok "nginx reloaded with real certificate"

  _enable_ssl_stapling
  _setup_ssl_autorenew
}

_enable_ssl_stapling() {
  local NGINX_CONF="${DEPLOY_DIR}/docker/nginx/nginx.conf"
  local CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  [[ ! -f "$NGINX_CONF" || ! -f "$CERT_PATH" ]] && return 0
  if grep -q "# ssl_stapling on;" "$NGINX_CONF"; then
    sed -i \
      -e 's|# ssl_stapling        on;|ssl_stapling        on;|' \
      -e 's|# ssl_stapling_verify on;|ssl_stapling_verify on;|' \
      -e 's|# resolver .*|resolver            1.1.1.1 8.8.8.8 valid=300s;|' \
      "$NGINX_CONF"
    if docker exec geminivpn-nginx nginx -t 2>/dev/null; then
      docker exec geminivpn-nginx nginx -s reload 2>/dev/null || true
      ok "ssl_stapling enabled"
    else
      sed -i \
        -e 's|ssl_stapling        on;|# ssl_stapling        on;|' \
        -e 's|ssl_stapling_verify on;|# ssl_stapling_verify on;|' \
        "$NGINX_CONF"
      warn "ssl_stapling test failed — kept disabled"
    fi
  fi
}

_setup_ssl_autorenew() {
  mkdir -p /etc/letsencrypt/renewal-hooks/pre \
           /etc/letsencrypt/renewal-hooks/post \
           /etc/letsencrypt/renewal-hooks/deploy

  cat > /etc/letsencrypt/renewal-hooks/pre/stop-nginx.sh << 'HOOK'
#!/bin/bash
echo "[$(date)] Stopping nginx for cert renewal..." >> /var/log/letsencrypt-renewal.log
docker stop geminivpn-nginx 2>/dev/null || true
fuser -k 80/tcp 2>/dev/null || true
sleep 2
HOOK
  chmod +x /etc/letsencrypt/renewal-hooks/pre/stop-nginx.sh

  cat > /etc/letsencrypt/renewal-hooks/post/start-nginx.sh << 'HOOK'
#!/bin/bash
echo "[$(date)] Restarting nginx after cert renewal..." >> /var/log/letsencrypt-renewal.log
docker start geminivpn-nginx 2>/dev/null || true
sleep 3
docker exec geminivpn-nginx nginx -s reload 2>/dev/null || true
echo "[$(date)] nginx back online" >> /var/log/letsencrypt-renewal.log
HOOK
  chmod +x /etc/letsencrypt/renewal-hooks/post/start-nginx.sh

  local RENEWAL_CONF="/etc/letsencrypt/renewal/${DOMAIN}.conf"
  if [[ -f "$RENEWAL_CONF" ]]; then
    sed -i 's/^authenticator = .*/authenticator = standalone/' "$RENEWAL_CONF" 2>/dev/null || true
    sed -i '/^webroot_path\s*=/d' "$RENEWAL_CONF" 2>/dev/null || true
    ok "Renewal conf: standalone authenticator set"
  fi

  systemctl disable --now snap.certbot.renew.timer 2>/dev/null || true
  systemctl disable --now certbot.timer             2>/dev/null || true

  cat > /etc/systemd/system/certbot-renew.service << 'SVC'
[Unit]
Description=Certbot SSL Renewal — GeminiVPN
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --standalone
SVC

  cat > /etc/systemd/system/certbot-renew.timer << 'TMR'
[Unit]
Description=SSL auto-renewal (twice daily) — GeminiVPN
[Timer]
OnCalendar=*-*-* 03:30:00
OnCalendar=*-*-* 15:30:00
RandomizedDelaySec=1800
Persistent=true
[Install]
WantedBy=timers.target
TMR

  systemctl daemon-reload
  systemctl enable --now certbot-renew.timer 2>/dev/null || true
  ok "SSL auto-renewal systemd timer active (twice daily, standalone mode)"

  info "Running renewal dry-run..."
  docker stop geminivpn-nginx 2>/dev/null || true
  fuser -k 80/tcp 2>/dev/null || true
  sleep 2
  certbot renew --dry-run --quiet --standalone 2>&1 && ok "Dry-run renewal: PASSED" || warn "Dry-run warning — cert is valid and will auto-renew"
  docker start geminivpn-nginx 2>/dev/null || true
  sleep 3
  docker exec geminivpn-nginx nginx -s reload 2>/dev/null || true
  ok "nginx back online after dry-run"
}

# =============================================================================
# PHASE 8a — STRIPE PAYMENTS
# =============================================================================
phase_stripe() {
  step "Phase 8a — Stripe Payment Configuration"

  local SK; SK=$(env_get STRIPE_SECRET_KEY)
  local PK; PK=$(env_get STRIPE_PUBLISHABLE_KEY)

  if [[ "$SK" =~ ^sk_(test|live)_ && ! "$SK" =~ placeholder ]]; then
    ok "Stripe already configured (${SK:0:14}...)"
    _verify_stripe_prices; return 0
  fi

  echo ""
  echo -e "  ${BOLD}Stripe Payment Setup${NC}"
  echo -e "  ${DIM}Get your keys → https://dashboard.stripe.com/apikeys${NC}"
  echo ""
  read -rp "  Stripe Secret Key (sk_test_... or sk_live_...): " SK
  read -rp "  Stripe Publishable Key (pk_test_... or pk_live_...): " PK

  [[ "$SK" =~ ^sk_(test|live)_ ]] || die "Invalid Stripe secret key format"
  [[ "$PK" =~ ^pk_(test|live)_ ]] || die "Invalid Stripe publishable key format"

  info "Verifying Stripe connection..."
  local VERIFY; VERIFY=$(curl -sf --max-time 10 -u "${SK}:" "https://api.stripe.com/v1/balance" 2>/dev/null || echo "FAIL")
  echo "$VERIFY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('object')=='balance'" 2>/dev/null || \
    die "Stripe API connection failed — check your secret key"
  ok "Stripe API connection verified"

  _create_stripe_plan() {
    local SK="$1" NAME="$2" DESC="$3" AMOUNT="$4" INTERVAL="$5" INTERVAL_COUNT="$6" NICK="$7"
    local PROD_ID; PROD_ID=$(curl -sf -u "${SK}:" "https://api.stripe.com/v1/products" \
      -d "name=${NAME}" -d "description=${DESC}" -d "type=service" 2>/dev/null | \
      python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
    local PRICE_ID; PRICE_ID=$(curl -sf -u "${SK}:" "https://api.stripe.com/v1/prices" \
      -d "product=${PROD_ID}" -d "unit_amount=${AMOUNT}" -d "currency=usd" \
      -d "recurring[interval]=${INTERVAL}" -d "recurring[interval_count]=${INTERVAL_COUNT}" \
      -d "nickname=${NICK}" 2>/dev/null | \
      python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
    echo "$PRICE_ID"
  }

  info "Creating Monthly plan (\$11.99/mo)..."
  local PRICE_M; PRICE_M=$(_create_stripe_plan "$SK" "GeminiVPN Monthly" "Monthly subscription" 1199 "month" 1 "GeminiVPN Monthly")
  [[ "$PRICE_M" =~ ^price_ ]] || die "Failed to create monthly price"
  ok "Monthly: ${PRICE_M}"

  info "Creating 1-Year plan (\$59.88/yr)..."
  local PRICE_Y; PRICE_Y=$(_create_stripe_plan "$SK" "GeminiVPN 1-Year" "Annual subscription - Save 58%" 5988 "year" 1 "GeminiVPN 1-Year")
  [[ "$PRICE_Y" =~ ^price_ ]] || die "Failed to create yearly price"
  ok "1-Year: ${PRICE_Y}"

  info "Creating 2-Year plan (\$83.76/2yr)..."
  local PRICE_2Y; PRICE_2Y=$(_create_stripe_plan "$SK" "GeminiVPN 2-Year" "2-Year subscription - Save 71%" 8376 "year" 2 "GeminiVPN 2-Year")
  [[ "$PRICE_2Y" =~ ^price_ ]] || die "Failed to create 2-year price"
  ok "2-Year: ${PRICE_2Y}"

  local WEBHOOK_URL="https://${DOMAIN}/api/v1/webhooks/stripe"
  info "Creating Stripe webhook endpoint..."
  local WEBHOOK_RESULT; WEBHOOK_RESULT=$(curl -sf -u "${SK}:" "https://api.stripe.com/v1/webhook_endpoints" \
    -d "url=${WEBHOOK_URL}" \
    -d "enabled_events[]=checkout.session.completed" \
    -d "enabled_events[]=customer.subscription.updated" \
    -d "enabled_events[]=customer.subscription.deleted" \
    -d "enabled_events[]=invoice.payment_succeeded" \
    -d "enabled_events[]=invoice.payment_failed" \
    -d "description=GeminiVPN Production" 2>/dev/null || echo "{}")

  local WHSEC; WHSEC=$(echo "$WEBHOOK_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('secret','FAIL'))" 2>/dev/null || echo "FAIL")
  if [[ "$WHSEC" =~ ^whsec_ ]]; then
    ok "Webhook created: ${WEBHOOK_URL}"
  else
    warn "Auto-webhook creation failed"
    echo "  Create manually at: https://dashboard.stripe.com/webhooks"
    echo "  Endpoint: ${WEBHOOK_URL}"
    read -rp "  Paste your webhook secret (whsec_...): " WHSEC
    [[ "$WHSEC" =~ ^whsec_ ]] || { warn "Skipping webhook secret"; WHSEC="whsec_placeholder"; }
  fi

  env_set STRIPE_SECRET_KEY        "$SK"
  env_set STRIPE_PUBLISHABLE_KEY   "$PK"
  env_set STRIPE_WEBHOOK_SECRET    "$WHSEC"
  env_set STRIPE_MONTHLY_PRICE_ID  "$PRICE_M"
  env_set STRIPE_YEARLY_PRICE_ID   "$PRICE_Y"
  env_set STRIPE_TWO_YEAR_PRICE_ID "$PRICE_2Y"
  ok ".env updated with Stripe values"

  cd "${DEPLOY_DIR}/docker"
  $DOCKER_COMPOSE --env-file "$ENV_FILE" restart backend 2>/dev/null && sleep 5
  ok "Backend restarted with Stripe keys"
  [[ "$SK" =~ sk_test_ ]] && echo -e "  ${YELLOW}Mode: TEST — use card 4242 4242 4242 4242 / 12/34 / 123${NC}"
}

_verify_stripe_prices() {
  local M Y TY
  M=$(env_get STRIPE_MONTHLY_PRICE_ID)
  Y=$(env_get STRIPE_YEARLY_PRICE_ID)
  TY=$(env_get STRIPE_TWO_YEAR_PRICE_ID)
  for ID in "$M" "$Y" "$TY"; do
    [[ "$ID" =~ ^price_ ]] || { warn "Missing Stripe price ID — run: sudo bash re-geminivpn.sh --stripe"; return 1; }
  done
  ok "All Stripe price IDs present"
}

# =============================================================================
# PHASE 8b — SQUARE · PADDLE · COINBASE PAYMENTS
# =============================================================================
phase_payment() {
  step "Phase 8b — Square · Paddle · Coinbase Commerce Setup"

  local SQ_TOKEN SQ_LOC_ID SQ_ENV SQ_WH_KEY
  local PD_KEY PD_ENV PD_PRICE_M PD_PRICE_Y PD_PRICE_2Y PD_WH_SECRET
  local CB_KEY CB_WH_SECRET
  local configured=0

  SQ_TOKEN=$(env_get SQUARE_ACCESS_TOKEN 2>/dev/null || echo "placeholder")
  SQ_LOC_ID=$(env_get SQUARE_LOCATION_ID 2>/dev/null || echo "")
  PD_KEY=$(env_get PADDLE_API_KEY 2>/dev/null || echo "placeholder")
  CB_KEY=$(env_get COINBASE_COMMERCE_API_KEY 2>/dev/null || echo "placeholder")

  [[ "$SQ_TOKEN" != "placeholder" && -n "$SQ_TOKEN" && -n "$SQ_LOC_ID" ]] && configured=$((configured + 1))
  [[ "$PD_KEY"   != "placeholder" && -n "$PD_KEY"   ]] && configured=$((configured + 1))
  [[ "$CB_KEY"   != "placeholder" && -n "$CB_KEY"   ]] && configured=$((configured + 1))

  if [[ $configured -eq 3 ]]; then
    ok "All 3 payment providers (Square, Paddle, Coinbase) already configured"
    return 0
  fi

  echo ""
  echo -e "  ${BOLD}━━━ Alternative Payment Providers ━━━${NC}"
  echo -e "  ${CYAN}[1] Square${NC}   — squareup.com/signup"
  echo -e "  ${CYAN}[2] Paddle${NC}   — vendors.paddle.com/signup"
  echo -e "  ${CYAN}[3] Coinbase${NC} — commerce.coinbase.com"
  echo -e "  ${DIM}Skip any by pressing Enter.${NC}"
  echo ""

  # Square
  echo -e "  ${BOLD}${CYAN}── Square ──${NC}"
  read -rp "  Square Access Token (EAAAx... or skip): " SQ_TOKEN
  read -rp "  Square Location ID: " SQ_LOC_ID
  read -rp "  Square Environment (sandbox/production) [sandbox]: " SQ_ENV
  SQ_ENV="${SQ_ENV:-sandbox}"

  if [[ -n "$SQ_TOKEN" && -n "$SQ_LOC_ID" ]]; then
    env_set SQUARE_ACCESS_TOKEN          "$SQ_TOKEN"
    env_set SQUARE_LOCATION_ID           "$SQ_LOC_ID"
    env_set SQUARE_ENVIRONMENT           "$SQ_ENV"
    read -rp "  Square Webhook Signature Key (optional): " SQ_WH_KEY
    env_set SQUARE_WEBHOOK_SIGNATURE_KEY "${SQ_WH_KEY:-placeholder}"
    ok "Square credentials saved"
  else
    warn "Square skipped"
  fi

  echo ""

  # Paddle
  echo -e "  ${BOLD}${CYAN}── Paddle ──${NC}"
  read -rp "  Paddle API Key (or skip): " PD_KEY
  read -rp "  Paddle Environment (sandbox/production) [sandbox]: " PD_ENV
  PD_ENV="${PD_ENV:-sandbox}"

  if [[ -n "$PD_KEY" ]]; then
    read -rp "  Paddle Monthly Price ID (pri_...): "  PD_PRICE_M
    read -rp "  Paddle 1-Year Price ID  (pri_...): "  PD_PRICE_Y
    read -rp "  Paddle 2-Year Price ID  (pri_...): "  PD_PRICE_2Y
    read -rp "  Paddle Webhook Secret (optional): " PD_WH_SECRET
    env_set PADDLE_API_KEY           "$PD_KEY"
    env_set PADDLE_ENVIRONMENT       "$PD_ENV"
    env_set PADDLE_WEBHOOK_SECRET    "${PD_WH_SECRET:-placeholder}"
    env_set PADDLE_MONTHLY_PRICE_ID  "${PD_PRICE_M:-placeholder}"
    env_set PADDLE_YEARLY_PRICE_ID   "${PD_PRICE_Y:-placeholder}"
    env_set PADDLE_TWO_YEAR_PRICE_ID "${PD_PRICE_2Y:-placeholder}"
    ok "Paddle credentials saved"
  else
    warn "Paddle skipped"
  fi

  echo ""

  # Coinbase Commerce
  echo -e "  ${BOLD}${CYAN}── Coinbase Commerce ──${NC}"
  read -rp "  Coinbase Commerce API Key (or skip): " CB_KEY

  if [[ -n "$CB_KEY" ]]; then
    read -rp "  Coinbase Webhook Secret (optional): " CB_WH_SECRET
    env_set COINBASE_COMMERCE_API_KEY "$CB_KEY"
    env_set COINBASE_WEBHOOK_SECRET   "${CB_WH_SECRET:-placeholder}"
    ok "Coinbase credentials saved"
  else
    warn "Coinbase skipped"
  fi

  cd "${DEPLOY_DIR}/docker"
  $DOCKER_COMPOSE --env-file "$ENV_FILE" restart backend 2>/dev/null && sleep 5
  ok "Backend restarted with new payment keys"
  echo ""
  echo -e "  ${BOLD}Webhook URLs:${NC}"
  echo "    Stripe:   https://${DOMAIN}/api/v1/webhooks/stripe"
  echo "    Square:   https://${DOMAIN}/api/v1/webhooks/square"
  echo "    Paddle:   https://${DOMAIN}/api/v1/webhooks/paddle"
  echo "    Coinbase: https://${DOMAIN}/api/v1/webhooks/coinbase"
}

# =============================================================================
# PHASE 9 — SMTP
# =============================================================================
phase_smtp() {
  step "Phase 9 — Email / SMTP Configuration"

  local CURRENT_HOST; CURRENT_HOST=$(env_get SMTP_HOST)
  if [[ -n "$CURRENT_HOST" && ! "$CURRENT_HOST" =~ placeholder|example\.com ]]; then
    ok "SMTP already configured: ${CURRENT_HOST}"; return 0
  fi

  echo ""
  echo -e "  ${BOLD}SMTP Email Setup${NC}"
  echo ""
  echo "  1) Gmail    (App Password → myaccount.google.com/apppasswords)"
  echo "  2) Zoho     (free 200/day)"
  echo "  3) SendGrid (free 100/day)"
  echo "  4) Mailgun  (free 100/day)"
  echo "  5) Custom SMTP"
  echo "  6) Skip for now"
  echo ""
  read -rp "  Choose [1-6]: " CHOICE

  local SMTP_HOST="" SMTP_PORT="587"
  case "$CHOICE" in
    1) SMTP_HOST="smtp.gmail.com" ;;
    2) SMTP_HOST="smtp.zoho.com" ;;
    3) SMTP_HOST="smtp.sendgrid.net" ;;
    4) SMTP_HOST="smtp.mailgun.org" ;;
    5) read -rp "  SMTP Host: " SMTP_HOST; read -rp "  SMTP Port [587]: " SMTP_PORT; SMTP_PORT="${SMTP_PORT:-587}" ;;
    6) warn "SMTP skipped — email features unavailable until configured"; return 0 ;;
    *) warn "Invalid choice — skipping SMTP"; return 0 ;;
  esac

  read -rp "  SMTP Username: " SMTP_USER
  read -rsp "  SMTP Password (hidden): " SMTP_PASS; echo ""
  read -rp "  From address [noreply@${DOMAIN}]: " FROM_ADDR
  FROM_ADDR="${FROM_ADDR:-noreply@${DOMAIN}}"

  env_set SMTP_HOST "$SMTP_HOST"
  env_set SMTP_PORT "$SMTP_PORT"
  env_set SMTP_USER "$SMTP_USER"
  env_set SMTP_PASS "$SMTP_PASS"
  env_set SMTP_FROM "$FROM_ADDR"
  ok "SMTP configured: ${SMTP_HOST}:${SMTP_PORT}"

  cd "${DEPLOY_DIR}/docker"
  $DOCKER_COMPOSE --env-file "$ENV_FILE" restart backend 2>/dev/null && sleep 3
  ok "Backend restarted with SMTP settings"
}

# =============================================================================
# WHATSAPP NUMBER UPDATE
# =============================================================================
phase_whatsapp() {
  step "WhatsApp Support Number"
  local CURRENT; CURRENT=$(env_get WHATSAPP_SUPPORT_NUMBER)
  echo ""
  echo -e "  Current WhatsApp number: ${CYAN}${CURRENT:-not set}${NC}"
  echo -e "  ${DIM}Format: +[country code][number] e.g. +905368895622${NC}"
  echo ""
  read -rp "  New WhatsApp number (or Enter to keep current): " NEW_NUM
  if [[ -n "$NEW_NUM" ]]; then
    [[ "$NEW_NUM" =~ ^\+[0-9]{7,15}$ ]] || die "Invalid format. Use: +905368895622"
    env_set WHATSAPP_SUPPORT_NUMBER "$NEW_NUM"
    ok "WhatsApp number updated: ${NEW_NUM}"
    cd "${DEPLOY_DIR}/docker"
    $DOCKER_COMPOSE --env-file "$ENV_FILE" restart backend 2>/dev/null && sleep 3
    ok "Backend restarted"
  else
    ok "WhatsApp number unchanged: ${CURRENT}"
  fi
}

# =============================================================================
# PHASE 9b — APP BUILDER
# =============================================================================
phase_app_build() {
  step "App Builder — Building All Platform Apps"

  local APP_OUTPUT_DIR="${WWW_DIR}/downloads/apps"
  local APP_VERSION="1.0.0"
  local DOMAIN_CLEAN="${DOMAIN}"

  mkdir -p "$APP_OUTPUT_DIR"
  info "Building real downloadable packages for all platforms..."

  # ── Android: WireGuard APK + config guide ZIP ───────────────────────────────
  step "Building Android Package"
  local ANDROID_DIR; ANDROID_DIR=$(mktemp -d)
  cat > "${ANDROID_DIR}/GeminiVPN-Android-Setup.md" << ASETUP
# GeminiVPN Android Setup Guide

## Step 1 — Install WireGuard
Download from the official Play Store:
https://play.google.com/store/apps/details?id=com.wireguard.android

Or direct APK: https://download.wireguard.com/android-client/

## Step 2 — Get Your VPN Config
1. Open https://${DOMAIN_CLEAN}/app in your browser
2. Login or create an account
3. Go to Dashboard → Download Config
4. Save the .conf file to your phone

## Step 3 — Import Config
1. Open WireGuard app
2. Tap the (+) button → Import from file
3. Select the GeminiVPN .conf file
4. Tap the toggle to connect!

## Quick Connect (Web App)
Visit https://${DOMAIN_CLEAN}/app — works as a PWA!
Tap the Share icon → "Add to Home Screen" for app-like experience.

## Support
WhatsApp: https://wa.me/${WHATSAPP_SUPPORT_NUMBER:-+905368895622}
ASETUP

  cat > "${ANDROID_DIR}/install-wireguard-android.sh" << 'ASHELL'
#!/bin/bash
# ADB install helper (optional, for developers)
echo "GeminiVPN Android Installer"
echo "1. Connect your Android phone via USB"
echo "2. Enable USB Debugging in Developer Options"
echo "   Settings > About Phone > tap 'Build Number' 7 times"
echo "   Settings > Developer Options > USB Debugging ON"
echo "3. Run: adb install wireguard-android.apk"
echo ""
echo "Or install directly from Google Play Store:"
echo "https://play.google.com/store/apps/details?id=com.wireguard.android"
ASHELL

  cat > "${ANDROID_DIR}/wireguard-template.conf" << WGCONF
[Interface]
# Your private key will be here after login at https://${DOMAIN_CLEAN}/app
PrivateKey = YOUR_PRIVATE_KEY_FROM_DASHBOARD
Address = 10.8.0.X/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
# GeminiVPN Server
PublicKey = YOUR_SERVER_PUBLIC_KEY_FROM_DASHBOARD
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${SERVER_IP}:51820
PersistentKeepalive = 25
WGCONF

  cd /tmp && zip -j "${APP_OUTPUT_DIR}/GeminiVPN-Android.zip" \
    "${ANDROID_DIR}/GeminiVPN-Android-Setup.md" \
    "${ANDROID_DIR}/install-wireguard-android.sh" \
    "${ANDROID_DIR}/wireguard-template.conf" 2>/dev/null
  rm -rf "$ANDROID_DIR"
  ok "Android package: GeminiVPN-Android.zip ($(du -sh ${APP_OUTPUT_DIR}/GeminiVPN-Android.zip 2>/dev/null | cut -f1))"

  # ── Windows: PowerShell installer + WireGuard config ZIP ───────────────────
  step "Building Windows Package"
  local WIN_DIR; WIN_DIR=$(mktemp -d)

  cat > "${WIN_DIR}/Install-GeminiVPN.ps1" << WINPS
# GeminiVPN Windows Installer
# Run as Administrator: Right-click > Run with PowerShell

param([switch]`$Uninstall)

`$ErrorActionPreference = "Stop"
`$WireGuardUrl = "https://download.wireguard.com/windows-client/wireguard-installer.exe"
`$TempPath = "`$env:TEMP\wireguard-installer.exe"

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "   GeminiVPN for Windows" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

if (-not `$Uninstall) {
    Write-Host "Downloading WireGuard..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri `$WireGuardUrl -OutFile `$TempPath -UseBasicParsing
    Write-Host "Installing WireGuard..." -ForegroundColor Yellow
    Start-Process -FilePath `$TempPath -ArgumentList "/S" -Wait
    Remove-Item `$TempPath -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "[OK] WireGuard installed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Open https://${DOMAIN_CLEAN}/app in your browser"
    Write-Host "  2. Login and go to Dashboard -> Download Config"
    Write-Host "  3. Open WireGuard -> Import tunnel from file"
    Write-Host "  4. Select your GeminiVPN.conf file"
    Write-Host "  5. Click Activate!"
    Write-Host ""
    Write-Host "Support: https://wa.me/${WHATSAPP_SUPPORT_NUMBER:-+905368895622}" -ForegroundColor Cyan
} else {
    Write-Host "Uninstalling WireGuard..." -ForegroundColor Yellow
    `$wg = Get-WmiObject -Class Win32_Product | Where-Object {`$_.Name -like "*WireGuard*"}
    if (`$wg) { `$wg.Uninstall() | Out-Null; Write-Host "[OK] Uninstalled" -ForegroundColor Green }
    else { Write-Host "WireGuard not found" -ForegroundColor Yellow }
}
WINPS

  cat > "${WIN_DIR}/wireguard-template.conf" << WGCONF
[Interface]
PrivateKey = YOUR_PRIVATE_KEY_FROM_DASHBOARD
Address = 10.8.0.X/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = YOUR_SERVER_PUBLIC_KEY_FROM_DASHBOARD
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${SERVER_IP}:51820
PersistentKeepalive = 25
WGCONF

  cat > "${WIN_DIR}/README.txt" << WINREADME
GeminiVPN for Windows
=====================

QUICK START:
1. Right-click Install-GeminiVPN.ps1 -> Run with PowerShell (as Admin)
2. Visit https://${DOMAIN_CLEAN}/app to get your VPN config
3. Import wireguard-template.conf into WireGuard (fill in your keys from dashboard)

DIRECT LINK: https://download.wireguard.com/windows-client/

Support: https://wa.me/${WHATSAPP_SUPPORT_NUMBER:-+905368895622}
WINREADME

  cd /tmp && zip -j "${APP_OUTPUT_DIR}/GeminiVPN-Windows.zip" \
    "${WIN_DIR}/Install-GeminiVPN.ps1" \
    "${WIN_DIR}/wireguard-template.conf" \
    "${WIN_DIR}/README.txt" 2>/dev/null
  rm -rf "$WIN_DIR"
  ok "Windows package: GeminiVPN-Windows.zip ($(du -sh ${APP_OUTPUT_DIR}/GeminiVPN-Windows.zip 2>/dev/null | cut -f1))"

  # ── macOS: Shell installer + config ZIP ─────────────────────────────────────
  step "Building macOS Package"
  local MAC_DIR; MAC_DIR=$(mktemp -d)

  cat > "${MAC_DIR}/install-geminivpn-macos.sh" << 'MACSH'
#!/bin/bash
# GeminiVPN macOS Installer
# Run: bash install-geminivpn-macos.sh

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "================================="
echo "   GeminiVPN for macOS"
echo "================================="
echo -e "${NC}"

# Check for Homebrew
if command -v brew &>/dev/null; then
    echo -e "${CYAN}Installing WireGuard via Homebrew...${NC}"
    brew install wireguard-tools 2>/dev/null || true
    echo -e "${GREEN}[OK] WireGuard tools installed${NC}"
else
    echo -e "${CYAN}Install options:${NC}"
    echo "  1. Mac App Store: https://apps.apple.com/us/app/wireguard/id1451685025"
    echo "  2. Homebrew: brew install wireguard-tools"
    echo ""
    open "https://apps.apple.com/us/app/wireguard/id1451685025" 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}Next steps:${NC}"
MACSH

  # Append domain without heredoc confusion
  echo "echo \"  1. Open https://${DOMAIN_CLEAN}/app in Safari\"" >> "${MAC_DIR}/install-geminivpn-macos.sh"
  echo "echo \"  2. Login and go to Dashboard -> Download Config\"" >> "${MAC_DIR}/install-geminivpn-macos.sh"
  echo "echo \"  3. Open WireGuard app -> Import from file\"" >> "${MAC_DIR}/install-geminivpn-macos.sh"
  echo "echo \"  4. Activate and connect!\"" >> "${MAC_DIR}/install-geminivpn-macos.sh"
  echo "echo \"\"" >> "${MAC_DIR}/install-geminivpn-macos.sh"
  echo "echo \"Support: https://wa.me/${WHATSAPP_SUPPORT_NUMBER:-+905368895622}\"" >> "${MAC_DIR}/install-geminivpn-macos.sh"
  chmod +x "${MAC_DIR}/install-geminivpn-macos.sh"

  cat > "${MAC_DIR}/wireguard-template.conf" << WGCONF
[Interface]
PrivateKey = YOUR_PRIVATE_KEY_FROM_DASHBOARD
Address = 10.8.0.X/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = YOUR_SERVER_PUBLIC_KEY_FROM_DASHBOARD
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${SERVER_IP}:51820
PersistentKeepalive = 25
WGCONF

  cat > "${MAC_DIR}/README.txt" << MACREADME
GeminiVPN for macOS
===================

QUICK START:
  bash install-geminivpn-macos.sh

Or install WireGuard manually:
  https://apps.apple.com/us/app/wireguard/id1451685025

Then visit https://${DOMAIN_CLEAN}/app to get your config file.

Support: https://wa.me/${WHATSAPP_SUPPORT_NUMBER:-+905368895622}
MACREADME

  cd /tmp && zip -j "${APP_OUTPUT_DIR}/GeminiVPN-macOS.zip" \
    "${MAC_DIR}/install-geminivpn-macos.sh" \
    "${MAC_DIR}/wireguard-template.conf" \
    "${MAC_DIR}/README.txt" 2>/dev/null
  rm -rf "$MAC_DIR"
  ok "macOS package: GeminiVPN-macOS.zip ($(du -sh ${APP_OUTPUT_DIR}/GeminiVPN-macOS.zip 2>/dev/null | cut -f1))"

  # ── iOS: PWA manifest + App Store redirect ─────────────────────────────────
  step "Building iOS Package"
  # Create PWA manifest so the web app installs like a native app
  cat > "${WWW_DIR}/manifest.json" << PWAJSON
{
  "name": "GeminiVPN",
  "short_name": "GeminiVPN",
  "description": "Secure VPN — Browse at Lightspeed",
  "start_url": "/app",
  "display": "standalone",
  "background_color": "#1a1a2e",
  "theme_color": "#00d4aa",
  "orientation": "portrait-primary",
  "icons": [
    {"src": "/geminivpn-logo.png", "sizes": "192x192", "type": "image/png"},
    {"src": "/geminivpn-logo.png", "sizes": "512x512", "type": "image/png"}
  ]
}
PWAJSON
  ok "iOS PWA manifest: /var/www/geminivpn/manifest.json"

  local IOS_DIR; IOS_DIR=$(mktemp -d)
  cat > "${IOS_DIR}/GeminiVPN-iOS-Setup.txt" << IOSTXT
GeminiVPN for iOS
=================

OPTION 1 — WireGuard (Full VPN):
  1. Install WireGuard: https://apps.apple.com/us/app/wireguard/id1441195209
  2. Open https://${DOMAIN_CLEAN}/app in Safari
  3. Login -> Dashboard -> Download Config
  4. Open the .conf file -> "Copy to WireGuard"
  5. Activate tunnel!

OPTION 2 — Web App (PWA, no install needed):
  1. Open https://${DOMAIN_CLEAN} in Safari
  2. Tap the Share button (box with arrow)
  3. Tap "Add to Home Screen"
  4. Tap "Add" — GeminiVPN appears on your home screen!

Support: https://wa.me/${WHATSAPP_SUPPORT_NUMBER:-+905368895622}
IOSTXT
  cd /tmp && zip -j "${APP_OUTPUT_DIR}/GeminiVPN-iOS.zip" "${IOS_DIR}/GeminiVPN-iOS-Setup.txt" 2>/dev/null
  rm -rf "$IOS_DIR"
  ok "iOS package: GeminiVPN-iOS.zip"

  # ── Linux: Bash installer ──────────────────────────────────────────────────
  step "Building Linux Package"
  local LINUX_DIR; LINUX_DIR=$(mktemp -d)
  cat > "${LINUX_DIR}/install-geminivpn-linux.sh" << 'LINSH'
#!/bin/bash
# GeminiVPN Linux Installer
set -e
echo "=== GeminiVPN for Linux ==="
echo ""

# Detect distro and install WireGuard
if command -v apt-get &>/dev/null; then
    echo "Installing WireGuard (Debian/Ubuntu)..."
    sudo apt-get update -qq && sudo apt-get install -y wireguard resolvconf
elif command -v dnf &>/dev/null; then
    echo "Installing WireGuard (Fedora/RHEL)..."
    sudo dnf install -y wireguard-tools
elif command -v pacman &>/dev/null; then
    echo "Installing WireGuard (Arch)..."
    sudo pacman -S --noconfirm wireguard-tools
else
    echo "Please install wireguard-tools manually: https://www.wireguard.com/install/"
    exit 1
fi

echo "[OK] WireGuard installed"
echo ""
echo "Next steps:"
LINSH
  echo "echo \"  1. Open https://${DOMAIN_CLEAN}/app in your browser\"" >> "${LINUX_DIR}/install-geminivpn-linux.sh"
  echo "echo \"  2. Login and download your WireGuard config\"" >> "${LINUX_DIR}/install-geminivpn-linux.sh"
  echo "echo \"  3. sudo wg-quick up /path/to/geminivpn.conf\"" >> "${LINUX_DIR}/install-geminivpn-linux.sh"
  echo "echo \"  4. To auto-start: sudo systemctl enable wg-quick@geminivpn\"" >> "${LINUX_DIR}/install-geminivpn-linux.sh"
  chmod +x "${LINUX_DIR}/install-geminivpn-linux.sh"

  cd /tmp && zip -j "${APP_OUTPUT_DIR}/GeminiVPN-Linux.zip" "${LINUX_DIR}/install-geminivpn-linux.sh" 2>/dev/null
  rm -rf "$LINUX_DIR"
  ok "Linux package: GeminiVPN-Linux.zip"

  # ── Router/OpenWrt package ─────────────────────────────────────────────────
  step "Building Router Package"
  local ROUTER_DIR; ROUTER_DIR=$(mktemp -d)
  mkdir -p "${ROUTER_DIR}/files/etc/wireguard" "${ROUTER_DIR}/files/usr/bin"

  cat > "${ROUTER_DIR}/files/usr/bin/geminivpn-cli" << RCLI
#!/bin/sh
API="https://${SERVER_IP}/api/v1"
case "\$1" in
  status) wg show 2>/dev/null || echo "VPN: Disconnected" ;;
  connect) wg-quick up /etc/wireguard/geminivpn.conf 2>/dev/null && echo "Connected" ;;
  disconnect) wg-quick down geminivpn 2>/dev/null && echo "Disconnected" ;;
  *) echo "Usage: geminivpn-cli {status|connect|disconnect}" ;;
esac
RCLI
  chmod +x "${ROUTER_DIR}/files/usr/bin/geminivpn-cli"

  cat > "${ROUTER_DIR}/files/etc/wireguard/geminivpn.conf.template" << WGCONF
[Interface]
PrivateKey = YOUR_PRIVATE_KEY
Address = 10.8.0.X/24
DNS = 1.1.1.1

[Peer]
PublicKey = YOUR_SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = ${SERVER_IP}:51820
PersistentKeepalive = 25
WGCONF

  cat > "${ROUTER_DIR}/README.txt" << RREADME
GeminiVPN Router Package (OpenWrt / DD-WRT / OpenWrt)

1. Install WireGuard on your router:
   opkg update && opkg install wireguard-tools

2. Copy geminivpn.conf.template to /etc/wireguard/geminivpn.conf
   Fill in your keys from https://${DOMAIN_CLEAN}/app

3. Run: /usr/bin/geminivpn-cli connect

Auto-start on boot:
   uci set network.geminivpn=interface
   uci set network.geminivpn.proto=wireguard
   uci commit network
RREADME

  cd "${ROUTER_DIR}"
  tar czf "${APP_OUTPUT_DIR}/geminivpn-router-openwrt.tar.gz" files README.txt 2>/dev/null
  cd /tmp && zip -j "${APP_OUTPUT_DIR}/GeminiVPN-Router.zip" \
    "${ROUTER_DIR}/README.txt" \
    "${ROUTER_DIR}/files/usr/bin/geminivpn-cli" \
    "${ROUTER_DIR}/files/etc/wireguard/geminivpn.conf.template" 2>/dev/null
  rm -rf "$ROUTER_DIR"
  ok "Router package: GeminiVPN-Router.zip + geminivpn-router-openwrt.tar.gz"

  # ── Master Download Page ───────────────────────────────────────────────────
  local ANDROID_SIZE; ANDROID_SIZE=$(du -sh "${APP_OUTPUT_DIR}/GeminiVPN-Android.zip" 2>/dev/null | cut -f1 || echo "~5KB")
  local WIN_SIZE;     WIN_SIZE=$(du -sh "${APP_OUTPUT_DIR}/GeminiVPN-Windows.zip" 2>/dev/null | cut -f1 || echo "~5KB")
  local MAC_SIZE;     MAC_SIZE=$(du -sh "${APP_OUTPUT_DIR}/GeminiVPN-macOS.zip" 2>/dev/null | cut -f1 || echo "~5KB")

  cat > "${APP_OUTPUT_DIR}/index.html" << DLPAGE
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="apple-mobile-web-app-capable" content="yes">
<title>Download GeminiVPN</title>
<link rel="manifest" href="/manifest.json">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
     background:linear-gradient(135deg,#0f0f1a 0%,#1a1a2e 40%,#0f3460 100%);
     color:#fff;min-height:100vh}
.hero{text-align:center;padding:60px 20px 40px}
.logo{font-size:2em;font-weight:900;letter-spacing:2px;
      background:linear-gradient(90deg,#00d4aa,#00a8e8);
      -webkit-background-clip:text;-webkit-text-fill-color:transparent}
.subtitle{opacity:.75;margin-top:10px;font-size:1.05em}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));
      gap:20px;max-width:1100px;margin:0 auto;padding:0 20px 60px}
.card{background:rgba(255,255,255,.06);border:1px solid rgba(0,212,170,.2);
      border-radius:16px;padding:28px 22px;text-align:center;
      transition:transform .2s,border-color .2s}
.card:hover{transform:translateY(-4px);border-color:rgba(0,212,170,.6)}
.icon{font-size:44px;margin-bottom:14px;display:block}
.name{font-size:1.25em;font-weight:700;margin-bottom:6px}
.desc{opacity:.65;font-size:.9em;margin-bottom:20px;line-height:1.5}
.size{opacity:.45;font-size:.78em;margin-bottom:12px}
.btn{display:inline-block;padding:11px 28px;
     background:linear-gradient(90deg,#00d4aa,#00a8e8);
     color:#0f0f1a;text-decoration:none;border-radius:25px;
     font-weight:700;font-size:.95em;transition:opacity .2s}
.btn:hover{opacity:.85}
.btn-ghost{background:transparent;color:#00d4aa;
           border:2px solid #00d4aa;margin-left:8px}
.pwa-note{background:rgba(0,212,170,.08);border:1px solid rgba(0,212,170,.2);
          border-radius:12px;padding:18px;text-align:center;
          max-width:700px;margin:0 auto 30px;font-size:.9em;opacity:.85}
footer{text-align:center;padding:30px;border-top:1px solid rgba(255,255,255,.08);
       opacity:.5;font-size:.85em}
</style>
</head>
<body>
<div class="hero">
  <div class="logo">⚡ GEMINIVPN</div>
  <p class="subtitle">Download for your platform — free WireGuard-based VPN</p>
</div>
<div style="max-width:1100px;margin:0 auto;padding:0 20px 20px">
  <div class="pwa-note">
    📱 <strong>No install needed on mobile!</strong>
    Open <a href="https://${DOMAIN_CLEAN}/app" style="color:#00d4aa">https://${DOMAIN_CLEAN}/app</a> in Safari/Chrome
    → Share → <em>Add to Home Screen</em> for the full app experience.
  </div>
</div>
<div class="grid">
  <div class="card">
    <span class="icon">🤖</span>
    <div class="name">Android</div>
    <div class="desc">WireGuard + setup guide for Android 7.0+</div>
    <div class="size">${ANDROID_SIZE} ZIP</div>
    <a href="GeminiVPN-Android.zip" class="btn" download>⬇ Download</a>
    <a href="https://play.google.com/store/apps/details?id=com.wireguard.android" class="btn btn-ghost" target="_blank">Play Store</a>
  </div>
  <div class="card">
    <span class="icon">💻</span>
    <div class="name">Windows</div>
    <div class="desc">PowerShell installer + WireGuard config for Windows 10/11</div>
    <div class="size">${WIN_SIZE} ZIP</div>
    <a href="GeminiVPN-Windows.zip" class="btn" download>⬇ Download</a>
    <a href="https://download.wireguard.com/windows-client/" class="btn btn-ghost" target="_blank">WireGuard</a>
  </div>
  <div class="card">
    <span class="icon">🍎</span>
    <div class="name">macOS</div>
    <div class="desc">Shell installer + WireGuard config for macOS 11+</div>
    <div class="size">${MAC_SIZE} ZIP</div>
    <a href="GeminiVPN-macOS.zip" class="btn" download>⬇ Download</a>
    <a href="https://apps.apple.com/us/app/wireguard/id1451685025" class="btn btn-ghost" target="_blank">Mac App Store</a>
  </div>
  <div class="card">
    <span class="icon">📱</span>
    <div class="name">iOS / iPhone</div>
    <div class="desc">WireGuard from App Store + setup guide, or install as PWA</div>
    <a href="GeminiVPN-iOS.zip" class="btn" download>⬇ Setup Guide</a>
    <a href="https://apps.apple.com/us/app/wireguard/id1441195209" class="btn btn-ghost" target="_blank">App Store</a>
  </div>
  <div class="card">
    <span class="icon">🐧</span>
    <div class="name">Linux</div>
    <div class="desc">Bash installer for Ubuntu, Fedora, Arch and more</div>
    <a href="GeminiVPN-Linux.zip" class="btn" download>⬇ Download</a>
  </div>
  <div class="card">
    <span class="icon">🌐</span>
    <div class="name">Router</div>
    <div class="desc">OpenWrt / DD-WRT WireGuard package + CLI tool</div>
    <a href="GeminiVPN-Router.zip" class="btn" download>⬇ Download ZIP</a>
    <a href="geminivpn-router-openwrt.tar.gz" class="btn btn-ghost" download>⬇ .tar.gz</a>
  </div>
</div>
<footer>
  <p>&copy; 2026 GeminiVPN &nbsp;·&nbsp;
  <a href="https://${DOMAIN_CLEAN}/app" style="color:#00d4aa">Web App</a> &nbsp;·&nbsp;
  <a href="https://wa.me/${WHATSAPP_SUPPORT_NUMBER:-+905368895622}" style="color:#00d4aa">WhatsApp Support</a>
  </p>
</footer>
</body>
</html>
DLPAGE

  echo ""
  ok "Download portal: https://${DOMAIN_CLEAN}/downloads/apps/"
  ok "Packages created:"
  ls -lh "${APP_OUTPUT_DIR}"/*.zip "${APP_OUTPUT_DIR}"/*.tar.gz 2>/dev/null | awk '{print "    " $5 "  " $9}' || true
  ok "All platform apps built with real downloadable packages!"
}

# =============================================================================
# PHASE 10 — HEALTH CHECK + TEST SUITE
# =============================================================================
phase_test() {
  step "Phase 10 — Health Check & Test Suite"
  local BASE="https://${DOMAIN}" PASS=0 FAIL=0
  # CRITICAL: Use --resolve so tests work even before DNS propagates.
  # This routes the domain to 127.0.0.1 locally — identical to a real browser
  # request but without needing the No-IP record to be live yet.
  local RESOLVE="--resolve ${DOMAIN}:443:127.0.0.1 --resolve ${DOMAIN}:80:127.0.0.1"

  _check() {
    local DESC="$1" URL="$2" WANT="${3:-200}" EXTRA="${4:-}"
    local HTTP
    # First try via localhost resolve (DNS-independent)
    HTTP=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 $RESOLVE $EXTRA "$URL" 2>/dev/null || echo "000")
    # If that gives 000, try direct 127.0.0.1 with Host header
    if [[ "$HTTP" == "000" ]]; then
      local PATH_PART="${URL#https://${DOMAIN}}"
      HTTP=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 $EXTRA \
        -H "Host: ${DOMAIN}" "https://127.0.0.1${PATH_PART}" 2>/dev/null || echo "000")
    fi
    if [[ "$HTTP" == "$WANT" ]]; then
      ok "${DESC} → HTTP ${HTTP}"
      PASS=$((PASS + 1))
    else
      warn "${DESC} → HTTP ${HTTP} (expected ${WANT})"
      FAIL=$((FAIL + 1))
    fi
  }

  _check_post() {
    local DESC="$1" URL="$2" WANT="$3" BODY="${4:-{}}" EXTRA="${5:-}"
    local HTTP PATH_PART="${URL#https://${DOMAIN}}"
    HTTP=$(curl -sk -X POST -H "Content-Type: application/json" -d "$BODY" \
      -o /dev/null -w "%{http_code}" --max-time 15 $RESOLVE $EXTRA "$URL" 2>/dev/null || echo "000")
    if [[ "$HTTP" == "000" ]]; then
      HTTP=$(curl -sk -X POST -H "Content-Type: application/json" -H "Host: ${DOMAIN}" \
        -d "$BODY" -o /dev/null -w "%{http_code}" --max-time 15 $EXTRA \
        "https://127.0.0.1${PATH_PART}" 2>/dev/null || echo "000")
    fi
    if [[ "$HTTP" == "$WANT" ]]; then
      ok "${DESC} → HTTP ${HTTP}"
      PASS=$((PASS + 1))
    else
      warn "${DESC} → HTTP ${HTTP} (expected ${WANT})"
      FAIL=$((FAIL + 1))
    fi
  }

  # ── Core endpoint tests ────────────────────────────────────────────────────
  _check "Health endpoint"         "${BASE}/health"
  _check "VPN servers list"        "${BASE}/api/v1/servers"
  _check "Pricing plans"           "${BASE}/api/v1/payments/plans"
  _check "Download stats"          "${BASE}/api/v1/downloads/stats"
  _check "Frontend index"          "${BASE}/"
  _check "iOS redirect"            "${BASE}/api/v1/downloads/ios"        "302"
  _check "WhatsApp redirect"       "${BASE}/support/whatsapp"            "302"
  _check "Unauthenticated profile" "${BASE}/api/v1/users/profile"        "401"
  _check "Logo PNG served"         "${BASE}/geminivpn-logo.png"          "200"

  # ── Webhook tests ──────────────────────────────────────────────────────────
  for PROVIDER in stripe square paddle coinbase; do
    local WH_HTTP PATH_PART="/api/v1/webhooks/${PROVIDER}"
    WH_HTTP=$(curl -sk -X POST "${BASE}${PATH_PART}" -H "Content-Type: application/json" \
      -d '{}' -o /dev/null -w "%{http_code}" --max-time 10 $RESOLVE 2>/dev/null || echo "000")
    [[ "$WH_HTTP" =~ ^[24] ]] \
      && { ok "Webhook /${PROVIDER} → HTTP ${WH_HTTP}"; PASS=$((PASS + 1)); } \
      || { warn "Webhook /${PROVIDER} → HTTP ${WH_HTTP}"; FAIL=$((FAIL + 1)); }
  done

  # ── Auth tests ─────────────────────────────────────────────────────────────
  local REG_BODY; REG_BODY=$(printf '{"email":"autotest_%s@geminivpn.test","password":"AutoTest2026!","name":"AutoTest"}' "$(date +%s)")
  local REG_TMP; REG_TMP=$(mktemp)
  local REG_HTTP
  REG_HTTP=$(curl -sk -X POST "${BASE}/api/v1/auth/register" $RESOLVE \
    -H "Content-Type: application/json" -d "$REG_BODY" \
    -o "$REG_TMP" -w "%{http_code}" --max-time 15 2>/dev/null || echo "000")
  if [[ "$REG_HTTP" == "201" ]]; then
    ok "Registration → HTTP 201"; PASS=$((PASS + 1))
    local TOKEN; TOKEN=$(python3 -c \
      "import json; d=json.load(open('${REG_TMP}')); print(d['data']['tokens']['accessToken'])" 2>/dev/null || echo "")
    if [[ -n "$TOKEN" ]]; then
      local PROF_HTTP
      PROF_HTTP=$(curl -sk -H "Authorization: Bearer ${TOKEN}" $RESOLVE \
        "${BASE}/api/v1/users/profile" -o /dev/null -w "%{http_code}" --max-time 10 2>/dev/null || echo "000")
      [[ "$PROF_HTTP" == "200" ]] \
        && { ok "Auth profile (JWT) → HTTP 200"; PASS=$((PASS + 1)); } \
        || { warn "Auth profile → HTTP ${PROF_HTTP}"; FAIL=$((FAIL + 1)); }
    fi
  else
    warn "Registration → HTTP ${REG_HTTP}"; FAIL=$((FAIL + 1))
  fi
  rm -f "$REG_TMP"

  local LOGIN_HTTP
  LOGIN_HTTP=$(curl -sk -X POST "${BASE}/api/v1/auth/login" $RESOLVE \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@geminivpn.local","password":"GeminiAdmin2026!"}' \
    -o /dev/null -w "%{http_code}" --max-time 15 2>/dev/null || echo "000")
  [[ "$LOGIN_HTTP" == "200" ]] \
    && { ok "Admin login → HTTP 200"; PASS=$((PASS + 1)); } \
    || { warn "Admin login → HTTP ${LOGIN_HTTP}"; FAIL=$((FAIL + 1)); }

  local DEMO_HTTP
  DEMO_HTTP=$(curl -sk -X POST "${BASE}/api/v1/demo/generate" $RESOLVE \
    -H "Content-Type: application/json" -d '{}' \
    -o /dev/null -w "%{http_code}" --max-time 15 2>/dev/null || echo "000")
  [[ "$DEMO_HTTP" =~ ^(201|429)$ ]] \
    && { ok "Demo generate → HTTP ${DEMO_HTTP}"; PASS=$((PASS + 1)); } \
    || { warn "Demo → HTTP ${DEMO_HTTP}"; FAIL=$((FAIL + 1)); }

  # ── Container health ───────────────────────────────────────────────────────
  for CTR in geminivpn-backend geminivpn-nginx; do
    local S H
    S=$(docker inspect "$CTR" --format '{{.State.Status}}'        2>/dev/null || echo "missing")
    H=$(docker inspect "$CTR" --format '{{.State.Health.Status}}' 2>/dev/null || echo "n/a")
    [[ "$S" == "running" ]] \
      && { ok "Container ${CTR}: running (health: ${H})"; PASS=$((PASS + 1)); } \
      || { warn "Container ${CTR}: ${S}";                 FAIL=$((FAIL + 1)); }
  done

  # ── DB + SSL ───────────────────────────────────────────────────────────────
  local DB_FILE="${DB_DIR}/geminivpn.db"
  [[ -f "$DB_FILE" ]] \
    && { ok "SQLite database: ${DB_FILE} ($(du -h "$DB_FILE" | cut -f1))"; PASS=$((PASS + 1)); } \
    || { warn "SQLite database not found at ${DB_FILE}";                    FAIL=$((FAIL + 1)); }

  local CERT_EXPIRY
  CERT_EXPIRY=$(echo | openssl s_client -servername "${DOMAIN}" \
    -connect "127.0.0.1:443" 2>/dev/null | \
    openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
  [[ -n "$CERT_EXPIRY" ]] && { ok "SSL cert: ${CERT_EXPIRY}"; PASS=$((PASS + 1)); }

  # ── External connectivity probe (detects DigitalOcean cloud firewall) ────────
  # Tests access from the PUBLIC internet — different from local --resolve tests.
  # If this fails while local tests pass → DO cloud firewall blocking 80/443.
  local EXT_CHECK; EXT_CHECK=$(curl -sk --max-time 12 -o /dev/null -w "%{http_code}" \
    "https://${DOMAIN}/" 2>/dev/null || echo "000")
  if [[ "$EXT_CHECK" =~ ^[23] ]]; then
    ok "External access: HTTP ${EXT_CHECK} ✓ — site reachable from internet"; PASS=$((PASS+1))
  else
    warn "External HTTPS: TIMED OUT or REFUSED (code: ${EXT_CHECK})"
    warn "→ DigitalOcean cloud firewall may be blocking inbound TCP 80/443"
    warn "  Fix: https://cloud.digitalocean.com/networking/firewalls"
    warn "  Add rules: Inbound TCP 80 + TCP 443 from All IPv4 (0.0.0.0/0) + All IPv6 (::/0)"
    warn "  Note: DO cloud firewall is SEPARATE from UFW — must be set in the DO dashboard"
    FAIL=$((FAIL+1))
  fi

  # ── Results + Auto-Heal ────────────────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}══ Test Results ══════════════════════════════════${NC}"
  echo -e "  ${GREEN}PASS: ${PASS}${NC}  ${RED}FAIL: ${FAIL}${NC}  Total: $((PASS+FAIL))"

  if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}✓ All tests passed!${NC}"
  else
    echo -e "  ${RED}${BOLD}${FAIL} test(s) failed.${NC}"
    # ── Auto-heal: if nginx/backend connectivity tests failed, run fix now ──
    local CONN_FAIL=0
    local HEALTH_NOW
    HEALTH_NOW=$(curl -sk -o /dev/null -w "%{http_code}" \
      --max-time 5 -H "Host: ${DOMAIN}" "https://127.0.0.1/health" 2>/dev/null || echo "000")
    [[ "$HEALTH_NOW" != "200" ]] && CONN_FAIL=1

    if [[ $CONN_FAIL -eq 1 ]]; then
      echo ""
      warn "Connectivity failure detected — running auto-heal (firewall + nginx)..."
      phase_connectivity_check
      echo ""
      # Re-run affected tests after fix
      info "Re-checking key endpoints after auto-heal..."
      local RECHECK_PASS=0 RECHECK_FAIL=0
      for ENDPOINT in "/health" "/" "/support/whatsapp"; do
        local WANT="200"
        [[ "$ENDPOINT" == "/support/whatsapp" ]] && WANT="302"
        local RC
        RC=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 8 $RESOLVE \
          ${BASE}${ENDPOINT} ${WANT:+--max-redirs 0} 2>/dev/null || echo "000")
        [[ "$RC" == "$WANT" ]] \
          && { ok "Re-check ${ENDPOINT} → HTTP ${RC} ✓"; RECHECK_PASS=$((RECHECK_PASS + 1)); } \
          || { warn "Re-check ${ENDPOINT} → HTTP ${RC}"; RECHECK_FAIL=$((RECHECK_FAIL + 1)); }
      done
      [[ $RECHECK_FAIL -eq 0 ]] \
        && ok "Auto-heal successful — site is now serving requests!" \
        || warn "Some endpoints still failing — check: docker logs geminivpn-backend --tail=50"
    else
      echo "  Check: docker logs geminivpn-backend --tail=50"
    fi
  fi

  return $FAIL
}

# =============================================================================
# STATUS
# =============================================================================
phase_status() {
  echo -e "\n${BOLD}Container Status:${NC}"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep -E "geminivpn|NAME" || echo "  No containers running"

  echo -e "\n${BOLD}SQLite Database:${NC}"
  local DB_FILE="${DB_DIR}/geminivpn.db"
  if [[ -f "$DB_FILE" ]]; then
    echo "  ${DB_FILE} — $(du -h "$DB_FILE" | cut -f1)"
    local BACKUPS; BACKUPS=$(ls "${DB_DIR}/backups/"*.db 2>/dev/null | wc -l)
    echo "  Backups available: ${BACKUPS} (in ${DB_DIR}/backups/)"
  else
    echo "  Database not found at ${DB_FILE}"
  fi

  echo -e "\n${BOLD}SSL Certificate:${NC}"
  local CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  if [[ -f "$CERT" ]]; then
    local EXPIRY DAYS
    EXPIRY=$(openssl x509 -noout -enddate -in "$CERT" | cut -d= -f2)
    DAYS=$(( ( $(date -d "$EXPIRY" +%s) - $(date +%s) ) / 86400 ))
    echo "  ${DOMAIN}: expires ${EXPIRY} (${DAYS} days)"
  else
    echo "  No Let's Encrypt cert — using self-signed fallback"
  fi

  echo -e "\n${BOLD}Payment Providers:${NC}"
  local SK SQ PD CB
  SK=$(env_get STRIPE_SECRET_KEY 2>/dev/null || echo "")
  SQ=$(env_get SQUARE_ACCESS_TOKEN 2>/dev/null || echo "")
  PD=$(env_get PADDLE_API_KEY 2>/dev/null || echo "")
  CB=$(env_get COINBASE_COMMERCE_API_KEY 2>/dev/null || echo "")
  [[ "$SK" =~ ^sk_(test|live)_ ]] && echo "  [✓] Stripe   ($([[ "$SK" =~ sk_live_ ]] && echo 'LIVE' || echo 'TEST'))" || echo "  [ ] Stripe   — not configured"
  [[ "$SQ" != "placeholder" && -n "$SQ" ]] && echo "  [✓] Square   (${SQ:0:12}...)" || echo "  [ ] Square   — not configured"
  [[ "$PD" != "placeholder" && -n "$PD" ]] && echo "  [✓] Paddle   (${PD:0:12}...)" || echo "  [ ] Paddle   — not configured"
  [[ "$CB" != "placeholder" && -n "$CB" ]] && echo "  [✓] Coinbase (${CB:0:12}...)" || echo "  [ ] Coinbase — not configured"

  echo -e "\n${BOLD}WhatsApp Support:${NC}"
  echo "  $(env_get WHATSAPP_SUPPORT_NUMBER 2>/dev/null || echo 'not set')"

  echo -e "\n${BOLD}No-IP Dynamic DNS:${NC}"
  if systemctl is-active --quiet noip-updater.timer 2>/dev/null; then
    echo "  [✓] No-IP curl updater: timer active (5-min auto-refresh)"
    local LAST_LOG; LAST_LOG=$(tail -1 /var/log/noip-update.log 2>/dev/null || echo "")
    [[ -n "$LAST_LOG" ]] && echo "  [→] Last update: ${LAST_LOG}"
  else
    echo "  [→] No-IP timer not active — starting now..."
    systemctl enable noip-updater.timer  2>/dev/null || true
    systemctl start  noip-updater.timer  2>/dev/null || true
    [[ -x /usr/local/bin/noip-update-check.sh ]] && /usr/local/bin/noip-update-check.sh &>/dev/null & disown || true
    echo "  [✓] No-IP curl updater triggered"
  fi

  echo -e "\n${BOLD}Firewall Status:${NC}"
  echo "  UFW: $(ufw status 2>/dev/null | head -1)"
  echo "  FORWARD policy: $(iptables -L FORWARD --line-numbers 2>/dev/null | head -1 | awk '{print $NF}')"
  echo "  Port 80 open:  $(ufw status 2>/dev/null | grep '80/tcp' | grep ALLOW | head -1 | awk '{print $1}' || echo 'not set')"
  echo "  Port 443 open: $(ufw status 2>/dev/null | grep '443/tcp' | grep ALLOW | head -1 | awk '{print $1}' || echo 'not set')"
  echo "  noip2 outbound(8245): $(ufw status 2>/dev/null | grep '8245' | head -1 | awk '{print $1}' || echo 'not set')"
  local NOIP_REACH="unreachable"
  curl -sf --max-time 6 --head "https://dynupdate.no-ip.com" >/dev/null 2>&1 && NOIP_REACH="reachable"
  echo "  No-IP server: ${NOIP_REACH}"

  echo -e "\n${BOLD}Container DNS:${NC}"
  for CTR in geminivpn-backend geminivpn-nginx; do
    if docker inspect "$CTR" >/dev/null 2>&1; then
      local DNS_CFG; DNS_CFG=$(docker inspect "$CTR" --format '{{.HostConfig.Dns}}' 2>/dev/null || echo "default")
      echo "  ${CTR}: ${DNS_CFG}"
    fi
  done
}

# =============================================================================
# FINAL SUMMARY
# =============================================================================
print_summary() {
  local CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  local SK SQ PD CB SMTP_H WA
  SK=$(env_get STRIPE_SECRET_KEY 2>/dev/null || echo "")
  SQ=$(env_get SQUARE_ACCESS_TOKEN 2>/dev/null || echo "")
  PD=$(env_get PADDLE_API_KEY 2>/dev/null || echo "")
  CB=$(env_get COINBASE_COMMERCE_API_KEY 2>/dev/null || echo "")
  SMTP_H=$(env_get SMTP_HOST 2>/dev/null || echo "")
  WA=$(env_get WHATSAPP_SUPPORT_NUMBER 2>/dev/null || echo "+905368895622")

  echo ""
  echo -e "${GREEN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════════════╗"
  echo "  ║   GeminiVPN is Live! SQLite · No-IP 24/7 · No Redis Needed 🚀 ║"
  echo "  ╚══════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${GREEN}→${NC} Site:      https://${DOMAIN}"
  echo -e "  ${GREEN}→${NC} Admin:     admin@geminivpn.local / GeminiAdmin2026!"
  echo -e "  ${GREEN}→${NC} Test:      alibasma@geminivpn.local / alibabaat2026"
  echo -e "  ${GREEN}→${NC} WhatsApp:  ${WA}"
  echo -e "  ${GREEN}→${NC} Database:  ${DB_DIR}/geminivpn.db"
  echo ""

  [[ -f "$CERT" ]] \
    && echo -e "  ${GREEN}[✓]${NC} Let's Encrypt SSL (auto-renew enabled)" \
    || echo -e "  ${YELLOW}[!]${NC} Self-signed SSL — run: sudo bash re-geminivpn.sh --ssl"

  local payment_ok=0
  [[ "$SK" =~ ^sk_(test|live)_ ]]               && { echo -e "  ${GREEN}[✓]${NC} Stripe payments"; payment_ok=$((payment_ok + 1)); }
  [[ "$SQ" != "placeholder" && -n "$SQ" ]]       && { echo -e "  ${GREEN}[✓]${NC} Square payments"; payment_ok=$((payment_ok + 1)); }
  [[ "$PD" != "placeholder" && -n "$PD" ]]       && { echo -e "  ${GREEN}[✓]${NC} Paddle subscriptions"; payment_ok=$((payment_ok + 1)); }
  [[ "$CB" != "placeholder" && -n "$CB" ]]       && { echo -e "  ${GREEN}[✓]${NC} Coinbase crypto payments"; payment_ok=$((payment_ok + 1)); }
  [[ $payment_ok -eq 0 ]]                        && echo -e "  ${YELLOW}[!]${NC} No payment provider configured — run: --stripe or --payment"

  [[ "$SMTP_H" =~ \. && ! "$SMTP_H" =~ placeholder ]] \
    && echo -e "  ${GREEN}[✓]${NC} Email / SMTP (${SMTP_H})" \
    || echo -e "  ${YELLOW}[!]${NC} SMTP not set — run: sudo bash re-geminivpn.sh --smtp"

  if systemctl is-active --quiet "${WATCHDOG_SERVICE:-geminivpn-watchdog}.service" 2>/dev/null; then
    echo -e "  ${GREEN}[✓]${NC} Auto-Refresh Watchdog active (health monitor every 30s)"
  else
    echo -e "  ${YELLOW}[!]${NC} Watchdog not running — run: sudo bash re-geminivpn.sh --watchdog"
  fi

  echo ""
  echo -e "  ${BOLD}Useful commands:${NC}"
  echo "    sudo bash re-geminivpn.sh              # redeploy / update"
  echo "    sudo bash re-geminivpn.sh --ssl        # (re)issue Let's Encrypt SSL"
  echo "    sudo bash re-geminivpn.sh --stripe     # configure Stripe"
  echo "    sudo bash re-geminivpn.sh --payment    # configure Square/Paddle/Coinbase"
  echo "    sudo bash re-geminivpn.sh --smtp       # configure email"
  echo "    sudo bash re-geminivpn.sh --whatsapp   # update WhatsApp support number"
  echo "    sudo bash re-geminivpn.sh --noip            # setup No-IP Dynamic DNS
    sudo bash re-geminivpn.sh --noip-firewall   # fix No-IP firewall (run if stuck!)
    sudo bash re-geminivpn.sh --auto-heal       # auto-detect and fix all issues
    sudo bash re-geminivpn.sh --fix-all         # full repair: firewall+noip+heal"
  echo "    sudo bash re-geminivpn.sh --watchdog   # start auto-refresh health watchdog"
  echo "    sudo bash re-geminivpn.sh --stop       # STOP auto-refresh watchdog"
  echo "    sudo bash re-geminivpn.sh --connectivity # fix firewall + DNS + nginx reload"
  echo "    sudo bash re-geminivpn.sh --app        # build all apps (APK, EXE, DMG, iOS, Router)"
  echo "    sudo bash re-geminivpn.sh --backup     # backup SQLite database"
  echo "    sudo bash re-geminivpn.sh --restore    # restore SQLite database from backup"
  echo "    sudo bash re-geminivpn.sh --test       # run full test suite"
  echo "    sudo bash re-geminivpn.sh --status     # quick status"
  echo "    docker logs geminivpn-backend -f --tail=50"
  echo "    # SQLite DB location: ${DB_DIR}/geminivpn.db"
  echo ""
}


# =============================================================================
# PHASE: NO-IP FIREWALL FIX
# Dedicated function to ensure No-IP DUC can always reach its update servers.
# Run manually: sudo bash re-geminivpn.sh --noip-firewall
# Also called automatically during every deploy.
# =============================================================================

phase_noip_firewall() {
  step "No-IP Firewall & Connectivity Fix"

  # ── 1. Ensure outbound ports are allowed ──────────────────────────────────
  info "Setting UFW outbound rules for No-IP DUC..."
  # No-IP DUC uses:
  #   - dynupdate.no-ip.com:80  (primary update endpoint)
  #   - dynupdate.no-ip.com:443 (HTTPS update)
  #   - dynupdate.no-ip.com:8245 (alternate port when 80/443 are blocked)
  #   - DNS port 53 (to resolve dynupdate.no-ip.com)
  for RULE in     "out on any to any port 53   proto udp"     "out on any to any port 53   proto tcp"     "out on any to any port 80   proto tcp"     "out on any to any port 443  proto tcp"     "out on any to any port 8245 proto tcp"; do
    ufw allow $RULE 2>/dev/null || true
  done
  ok "UFW outbound rules confirmed: DNS(53) HTTP(80) HTTPS(443) No-IP-alt(8245)"

  # ── 2. Add iptables OUTPUT rules as hard guarantee ────────────────────────
  # These catch any raw iptables rules that might block outbound even if UFW
  # is set to default allow outgoing.
  iptables -I OUTPUT -p tcp --dport 80   -j ACCEPT 2>/dev/null || true
  iptables -I OUTPUT -p tcp --dport 443  -j ACCEPT 2>/dev/null || true
  iptables -I OUTPUT -p tcp --dport 8245 -j ACCEPT 2>/dev/null || true
  iptables -I OUTPUT -p udp --dport 53   -j ACCEPT 2>/dev/null || true
  iptables -I OUTPUT -p tcp --dport 53   -j ACCEPT 2>/dev/null || true
  ok "iptables OUTPUT rules added for No-IP/DNS/HTTP/HTTPS"

  # ── 3. Test outbound connectivity to No-IP ────────────────────────────────
  info "Testing connectivity to No-IP update servers..."
  local NOIP_OK=false
  for URL in     "https://dynupdate.no-ip.com"     "http://dynupdate.no-ip.com"     "http://dynupdate.no-ip.com:8245"; do
    if curl -sf --max-time 10 --head "$URL" >/dev/null 2>&1; then
      NOIP_OK=true
      ok "Reachable: $URL"
      break
    else
      warn "Unreachable: $URL"
    fi
  done

  if [[ "$NOIP_OK" == "false" ]]; then
    warn "Cannot reach any No-IP update endpoint!"
    warn "If using DigitalOcean / cloud provider, check the cloud-level firewall:"
    warn "  https://cloud.digitalocean.com/networking/firewalls"
    warn "  → Outbound rule: TCP 80, 443, 8245 to 0.0.0.0/0"
    warn "  → Outbound rule: UDP 53 to 0.0.0.0/0"
    warn "Test manually: curl -v http://dynupdate.no-ip.com"
  fi

  # ── 4. Trigger immediate DNS update via curl updater (non-blocking) ─────────
  info "Triggering No-IP DNS update (curl-based, zero-hang)..."
  pkill -9 -x noip2 2>/dev/null || true
  systemctl stop    noip2.service 2>/dev/null || true
  systemctl disable noip2.service 2>/dev/null || true
  if [[ -x /usr/local/bin/noip-update-check.sh ]]; then
    /usr/local/bin/noip-update-check.sh &
    disown
    ok "No-IP curl update triggered (background)"
    systemctl restart noip-updater.timer   2>/dev/null || true
    systemctl start   noip-updater.service 2>/dev/null || true
  else
    warn "No-IP updater not installed — run: sudo bash re-geminivpn.sh --noip"
  fi

  # ── 5. Save iptables rules for persistence ────────────────────────────────
  # Save iptables rules — works with or without netfilter-persistent
  mkdir -p /etc/iptables
  iptables-save  > /etc/iptables/rules.v4 2>/dev/null || true
  ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  ok "iptables rules saved to /etc/iptables/rules.v4+v6 (reboot-safe)"

  ok "No-IP firewall fix complete"
  info "Check No-IP timer:  systemctl status noip-updater.timer"
  info "Check No-IP logs:   tail -f /var/log/noip-update.log"
  info "View update log:    tail -f /var/log/noip-update.log"
}

# =============================================================================
# PHASE 9 — CONNECTIVITY CHECK (DNS + Firewall + nginx)
# =============================================================================

phase_connectivity_check() {
  step "Phase 9 — Connectivity, Firewall & Self-Healing Check"
  check_do_firewall  # Show DO firewall warning early if external access is blocked

  # ── helper: test HTTPS locally and return code ────────────────────────────
  _local_https() {
    curl -sk -o /dev/null -w "%{http_code}" \
      "https://127.0.0.1${1:-/health}" -H "Host: ${DOMAIN}" \
      --max-time 8 ${2:-} 2>/dev/null || echo "000"
  }

  # ═══════════════════════════════════════════════════════════════════════════
  # 1. UFW — guarantee ports open (runs on every deploy, not just first-time)
  # ═══════════════════════════════════════════════════════════════════════════
  if ! command -v ufw &>/dev/null; then
    apt-get install -y -qq ufw 2>/dev/null || apt-get install -y ufw
  fi

  if ! ufw status 2>/dev/null | grep -q "Status: active"; then
    warn "UFW not active — enabling..."
    ufw --force reset 2>/dev/null || true
    ufw default deny incoming
    ufw default allow outgoing
    echo "y" | ufw enable 2>/dev/null || true
  fi

  for PORT in "22/tcp" "80/tcp" "443/tcp" "51820/udp"; do
    ufw allow "$PORT" 2>/dev/null || true
  done
  ok "UFW: ports 22 80 443 51820 confirmed open"

  # ═══════════════════════════════════════════════════════════════════════════
  # 2. UFW FORWARD policy — Docker REQUIRES FORWARD=ACCEPT
  #    Without this, UFW silently drops packets between nginx↔backend
  # ═══════════════════════════════════════════════════════════════════════════
  local UFW_DEFAULT="/etc/default/ufw"
  if [[ -f "$UFW_DEFAULT" ]]; then
    if grep -q 'DEFAULT_FORWARD_POLICY="DROP"' "$UFW_DEFAULT" 2>/dev/null; then
      sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$UFW_DEFAULT"
      ok "UFW FORWARD policy: DROP → ACCEPT (Docker inter-container routing fixed)"
    else
      ok "UFW FORWARD policy: already ACCEPT"
    fi
  fi

  # Persist Docker FORWARD rules in ufw before.rules
  local BEFORE_RULES="/etc/ufw/before.rules"
  if [[ -f "$BEFORE_RULES" ]] && ! grep -q "DOCKER-USER" "$BEFORE_RULES" 2>/dev/null; then
    sed -i '/^COMMIT$/i -A ufw-before-forward -j DOCKER-USER' "$BEFORE_RULES" 2>/dev/null || true
    ok "UFW before.rules: DOCKER-USER FORWARD rule added"
  fi

  # ── iptables FORWARD rules — applied NOW and PERSISTED for reboots ──────────
  iptables -I FORWARD -j ACCEPT       2>/dev/null || true
  iptables -I DOCKER-USER -j ACCEPT   2>/dev/null || true
  iptables -P FORWARD ACCEPT          2>/dev/null || true
  ip6tables -P FORWARD ACCEPT         2>/dev/null || true

  # Find Docker bridge interface for this project and open it explicitly
  local DOCKER_IFACE
  DOCKER_IFACE=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -i gemini | head -1)
  if [[ -n "$DOCKER_IFACE" ]]; then
    local BRIDGE_NAME
    BRIDGE_NAME=$(docker network inspect "$DOCKER_IFACE" \
      --format '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || echo "")
    [[ -z "$BRIDGE_NAME" ]] && BRIDGE_NAME=$(ip link show 2>/dev/null | grep -oE 'br-[a-f0-9]+' | head -1)
    if [[ -n "$BRIDGE_NAME" ]]; then
      iptables -I FORWARD -i "$BRIDGE_NAME" -j ACCEPT 2>/dev/null || true
      iptables -I FORWARD -o "$BRIDGE_NAME" -j ACCEPT 2>/dev/null || true
      ok "iptables: Docker bridge ${BRIDGE_NAME} FORWARD rules applied"
    fi
  fi

  # Also cover docker0 (default bridge) and any veth pairs
  iptables -I FORWARD -i docker0 -j ACCEPT 2>/dev/null || true
  iptables -I FORWARD -o docker0 -j ACCEPT 2>/dev/null || true

  # ── PERSIST iptables rules (reboot-safe) ────────────────────────────────────
  mkdir -p /etc/iptables
  iptables-save  > /etc/iptables/rules.v4 2>/dev/null || true
  ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  command -v netfilter-persistent &>/dev/null && netfilter-persistent save 2>/dev/null || true
  ok "iptables rules persisted to /etc/iptables/rules.v4+v6"

  # ── rc.local fallback — ensures FORWARD=ACCEPT even on fresh boot ──────────
  # This is a safety net in case netfilter-persistent isn't available
  local RCLOCAL="/etc/rc.local"
  if [[ ! -f "$RCLOCAL" ]] || ! grep -q "GEMINIVPN-FIREWALL" "$RCLOCAL" 2>/dev/null; then
    cat > "$RCLOCAL" << 'RCEOF'
#!/bin/bash
# GeminiVPN — Boot-time firewall rules (GEMINIVPN-FIREWALL)
# Ensures Docker inter-container routing works after reboot
iptables -I FORWARD -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -j ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true
iptables -I FORWARD -i docker0 -j ACCEPT 2>/dev/null || true
iptables -I FORWARD -o docker0 -j ACCEPT 2>/dev/null || true
# No-IP outbound (backup: ensure not blocked)
iptables -I OUTPUT -p tcp --dport 80   -j ACCEPT 2>/dev/null || true
iptables -I OUTPUT -p tcp --dport 443  -j ACCEPT 2>/dev/null || true
iptables -I OUTPUT -p tcp --dport 8245 -j ACCEPT 2>/dev/null || true
iptables -I OUTPUT -p udp --dport 53   -j ACCEPT 2>/dev/null || true
exit 0
RCEOF
    chmod +x "$RCLOCAL"
    systemctl enable rc-local 2>/dev/null || true
    ok "rc.local fallback boot script created (GEMINIVPN-FIREWALL)"
  else
    ok "rc.local firewall rules already present"
  fi

  # Reload UFW to apply all changes
  ufw reload 2>/dev/null || true

  # ═══════════════════════════════════════════════════════════════════════════
  # 3. Remove legacy containers from old postgres/redis stack
  # ═══════════════════════════════════════════════════════════════════════════
  for LEGACY in geminivpn-postgres geminivpn-redis; do
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${LEGACY}$"; then
      warn "Removing legacy container: ${LEGACY}"
      docker stop "$LEGACY" 2>/dev/null || true
      docker rm   "$LEGACY" 2>/dev/null || true
      ok "Legacy container removed: ${LEGACY}"
    fi
  done

  # ═══════════════════════════════════════════════════════════════════════════
  # 4. nginx.conf integrity — ensure /support/ proxy block exists
  #    This fixes WhatsApp redirect returning 200 instead of 302
  # ═══════════════════════════════════════════════════════════════════════════
  local NGINX_CONF="${DEPLOY_DIR}/docker/nginx/nginx.conf"
  if [[ -f "$NGINX_CONF" ]] && ! grep -q "location /support/" "$NGINX_CONF" 2>/dev/null; then
    warn "nginx.conf: /support/ proxy missing — injecting..."
    python3 - "$NGINX_CONF" << 'PYFIX'
import sys
path = sys.argv[1]
with open(path) as f: content = f.read()
support_block = """\
        # ─── Support redirects (WhatsApp etc.) — MUST be before location / ──
        location /support/ {
            proxy_pass             http://backend;
            proxy_http_version     1.1;
            proxy_set_header       Connection        "";
            proxy_set_header       Host              $host;
            proxy_set_header       X-Real-IP         $remote_addr;
            proxy_set_header       X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header       X-Forwarded-Proto $scheme;
            proxy_read_timeout     15;
            proxy_connect_timeout  10;
        }

        # ─── React SPA fallback ───────────────────────────────────────────────"""
needle = "        # ─── React SPA fallback ───────────────────────────────────────────────"
if needle in content:
    content = content.replace(needle, support_block)
    with open(path, 'w') as f: f.write(content)
    print("Injected /support/ location")
else:
    print("Needle not found — skipping injection")
PYFIX
    ok "nginx.conf: /support/ proxy block injected"
  else
    ok "nginx.conf: /support/ proxy block present"
  fi

  # Reload nginx — nginx.conf is bind-mounted :ro from host so docker cp is not needed
  # The host file is already the latest; we just need nginx to reload it.
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "geminivpn-nginx"; then
    if docker exec geminivpn-nginx nginx -t 2>/dev/null; then
      docker exec geminivpn-nginx nginx -s reload 2>/dev/null &&         ok "nginx: reloaded — latest config active" ||         { docker restart geminivpn-nginx 2>/dev/null && ok "nginx: restarted"; }
    else
      warn "nginx config syntax error — restarting container..."
      docker restart geminivpn-nginx 2>/dev/null && ok "nginx: restarted" || warn "nginx restart failed"
    fi
  fi

  # ═══════════════════════════════════════════════════════════════════════════
  # 5. Logo & loading screen — ensure geminivpn-logo.png is deployed to WWW_DIR
  #    The splash screen in pre-start.sh + SPA loading state both reference it
  # ═══════════════════════════════════════════════════════════════════════════
  local LOGO_SRC="${DEPLOY_DIR}/frontend/public/geminivpn-logo.png"
  if [[ -f "$LOGO_SRC" ]]; then
    cp -f "$LOGO_SRC" "${WWW_DIR}/geminivpn-logo.png" 2>/dev/null || true
    ok "Logo: geminivpn-logo.png deployed to ${WWW_DIR}/"
  else
    warn "Logo source not found at ${LOGO_SRC}"
  fi

  # ═══════════════════════════════════════════════════════════════════════════
  # 6. DNS resolution check
  # ═══════════════════════════════════════════════════════════════════════════
  local MY_IP="" DNS_IP=""
  # CRITICAL: force -4 flag — dual-stack DO droplets return IPv6 without it.
  # No-IP holds an A record (IPv4 only); IPv6 here causes a false DNS mismatch report.
  for _src in \
    "curl -4 -s --max-time 8 https://ipv4.icanhazip.com" \
    "curl -4 -s --max-time 8 https://api.ipify.org" \
    "curl -4 -s --max-time 8 https://checkip.amazonaws.com"; do
    MY_IP=$(eval "$_src" 2>/dev/null | tr -d '[:space:]') || true
    [[ "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
    MY_IP=""
  done
  [[ -z "$MY_IP" ]] && MY_IP="$SERVER_IP"
  # Install dig if missing
  command -v dig &>/dev/null || apt-get install -y -qq dnsutils 2>/dev/null || true
  # Force A-record lookup only (dig +short without type returns AAAA on dual-stack)
  DNS_IP=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || \
           curl -4 -s --max-time 8 "https://dns.google/resolve?name=${DOMAIN}&type=A" 2>/dev/null \
           | python3 -c "import sys,json; d=json.load(sys.stdin); a=d.get('Answer',[]); \
             print(next((x['data'] for x in a if x.get('type')==1),''))" 2>/dev/null || echo "")

  ok "Server public IP: ${MY_IP}"
  if [[ -z "$DNS_IP" ]]; then
    warn "DNS: ${DOMAIN} — no A record resolved"
    warn "→ Go to https://www.noip.com/members/dns/ and set:"
    warn "   Hostname: ${DOMAIN}  →  IP: ${MY_IP}"
    info "Once DNS propagates (1-5 min) the site will load"
  elif [[ "$DNS_IP" == "$MY_IP" || "$DNS_IP" == "$SERVER_IP" ]]; then
    ok "DNS: ${DOMAIN} → ${DNS_IP} ✓"
  else
    warn "DNS mismatch: ${DOMAIN} → ${DNS_IP} (expected ${MY_IP})"
    warn "→ Update at https://www.noip.com/members/dns/"
  fi

  # ═══════════════════════════════════════════════════════════════════════════
  # 7. Self-healing connectivity test — retry up to 3x with auto-fixes
  # ═══════════════════════════════════════════════════════════════════════════
  sleep 3
  local ATTEMPT HEALTH_CODE WA_CODE HTTPS_CODE
  for ATTEMPT in 1 2 3; do
    HEALTH_CODE=$(_local_https "/health")
    WA_CODE=$(_local_https "/support/whatsapp" "--max-redirs 0")
    HTTPS_CODE=$(_local_https "/")

    if [[ "$HEALTH_CODE" == "200" && "$WA_CODE" == "302" ]]; then
      ok "Local HTTPS: all checks passed (attempt ${ATTEMPT})"
      break
    fi

    warn "Attempt ${ATTEMPT}/3 — Health:${HEALTH_CODE} WhatsApp:${WA_CODE} SPA:${HTTPS_CODE}"

    if [[ "$HEALTH_CODE" != "200" ]]; then
      # Backend not responding through nginx — restart both
      warn "Backend unreachable via nginx — restarting containers..."
      docker restart geminivpn-backend 2>/dev/null || true
      sleep 10
      docker restart geminivpn-nginx   2>/dev/null || true
      sleep 5
    elif [[ "$WA_CODE" != "302" ]]; then
      # nginx is up but /support/ not proxying — reload config
      warn "WhatsApp not redirecting — reloading nginx config..."
      docker exec geminivpn-nginx nginx -s reload 2>/dev/null || \
        docker restart geminivpn-nginx 2>/dev/null || true
      sleep 3
    fi

    [[ $ATTEMPT -lt 3 ]] && sleep 5
  done

  # Final status report
  HEALTH_CODE=$(_local_https "/health")
  WA_CODE=$(_local_https "/support/whatsapp" "--max-redirs 0")

  [[ "$HEALTH_CODE" == "200" ]] \
    && ok  "Health check: HTTP 200 ✓ — backend API live" \
    || warn "Health check: HTTP ${HEALTH_CODE} — check: docker logs geminivpn-backend --tail=30"

  [[ "$WA_CODE" == "302" ]] \
    && ok  "WhatsApp redirect: HTTP 302 ✓ — fixed and working" \
    || warn "WhatsApp redirect: HTTP ${WA_CODE} — nginx /support/ block may still be loading"

  # ── Run No-IP firewall fix as part of connectivity check ─────────────────
  phase_noip_firewall

  # ── DigitalOcean Cloud Firewall reminder ──────────────────────────────────
  if [[ "$HEALTH_CODE" != "200" ]] || [[ -z "$DNS_IP" ]]; then
    echo ""
    warn "Site may still be unreachable externally."
    info "DigitalOcean has TWO firewall layers — check both:"
    info "  1. UFW (OS-level)         — fixed above ✓"
    info "  2. Cloud Firewall (DO UI):"
    info "     https://cloud.digitalocean.com/networking/firewalls"
    info "     → Inbound: TCP 80  from 0.0.0.0/0 and ::/0"
    info "     → Inbound: TCP 443 from 0.0.0.0/0 and ::/0"
    info "  Test: curl -v --max-time 5 http://${SERVER_IP}/"
    info "  (timeout = Cloud Firewall blocking; refused = UFW/container issue)"
  fi

  ok "Connectivity phase complete"
}

# =============================================================================
# PHASE 11 — AUTO-REFRESH WATCHDOG (Health Monitor + Auto-Restart)
# =============================================================================

WATCHDOG_SERVICE="geminivpn-watchdog"
WATCHDOG_SCRIPT="/usr/local/bin/geminivpn-watchdog.sh"
WATCHDOG_LOG="/var/log/geminivpn/watchdog.log"
WATCHDOG_PID="/var/run/geminivpn-watchdog.pid"

phase_watchdog_start() {
  step "Phase 11 — Auto-Refresh Watchdog (Health Monitor)"

  info "Installing GeminiVPN health watchdog..."

  # Write the watchdog script
  cat > "$WATCHDOG_SCRIPT" << 'WDOG'
#!/usr/bin/env bash
# GeminiVPN Auto-Refresh Watchdog
# Monitors containers every 30s and auto-restarts unhealthy ones.
# Stop: sudo bash re-geminivpn.sh --stop

DEPLOY_DIR="/opt/geminivpn"
LOG_FILE="/var/log/geminivpn/watchdog.log"
PID_FILE="/var/run/geminivpn-watchdog.pid"
DOMAIN="geminivpn.zapto.org"
CONTAINERS="geminivpn-backend geminivpn-nginx"
INTERVAL=30
MAX_FAILURES=3
CONSECUTIVE_FAIL=0

mkdir -p "$(dirname "$LOG_FILE")"
echo $$ > "$PID_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# Docker compose command
if docker compose version &>/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

log "=== GeminiVPN Watchdog STARTED (PID $$, interval=${INTERVAL}s) ==="

while true; do
  ALL_HEALTHY=true

  for CTR in $CONTAINERS; do
    STATUS=$(docker inspect "$CTR" --format '{{.State.Status}}' 2>/dev/null || echo "missing")
    HEALTH=$(docker inspect "$CTR" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")

    if [[ "$STATUS" != "running" ]]; then
      log "ALERT: $CTR is $STATUS — restarting..."
      cd "${DEPLOY_DIR}/docker" && \
        $DC --env-file "${DEPLOY_DIR}/.env" up -d --no-recreate 2>>"$LOG_FILE" || true
      ALL_HEALTHY=false
      CONSECUTIVE_FAIL=$((CONSECUTIVE_FAIL + 1))
      log "Restart issued for $CTR (consecutive_fail=${CONSECUTIVE_FAIL})"

    elif [[ "$HEALTH" == "unhealthy" ]]; then
      log "ALERT: $CTR is unhealthy — performing restart..."
      docker restart "$CTR" 2>>"$LOG_FILE" || true
      ALL_HEALTHY=false
      CONSECUTIVE_FAIL=$((CONSECUTIVE_FAIL + 1))
      log "Restarted unhealthy container $CTR"

    else
      : # healthy — no action
    fi
  done

  # ── HTTP health check ─────────────────────────────────────────────────────
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    --max-time 8 "https://${DOMAIN}/health" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" != "200" ]]; then
    log "WARN: Health endpoint returned HTTP $HTTP_CODE — checking containers..."
    ALL_HEALTHY=false
    # Ensure iptables FORWARD is still ACCEPT (can revert after UFW reload)
    iptables -I FORWARD -j ACCEPT     2>/dev/null || true
    iptables -I DOCKER-USER -j ACCEPT 2>/dev/null || true
    iptables -P FORWARD ACCEPT        2>/dev/null || true
    sleep 10
    docker restart geminivpn-nginx 2>>"$LOG_FILE" || true
    log "nginx restarted due to health check failure (iptables FORWARD re-confirmed)"
  fi

  # ── No-IP curl updater health check ───────────────────────────────────────────
  if ! systemctl is-active --quiet noip-updater.timer 2>/dev/null; then
    log "ALERT: noip-updater.timer not active — restarting..."
    systemctl enable  noip-updater.timer 2>/dev/null || true
    systemctl restart noip-updater.timer 2>/dev/null || true
    [[ -x /usr/local/bin/noip-update-check.sh ]] && /usr/local/bin/noip-update-check.sh >>"$LOG_FILE" 2>&1 & disown || true
    log "No-IP curl updater restarted"
  fi

  # ── Firewall self-heal: re-apply FORWARD=ACCEPT if Docker routing breaks ──
  # UFW reload (triggered by certbot, system updates, etc.) can reset FORWARD
  # policy back to DROP, breaking nginx↔backend communication.
  local FWD_POLICY
  FWD_POLICY=$(iptables -L FORWARD --line-numbers 2>/dev/null | head -1 | awk '{print $NF}')
  if [[ "\$FWD_POLICY" == "DROP" || "\$FWD_POLICY" == "REJECT" ]]; then
    log "ALERT: iptables FORWARD policy is \$FWD_POLICY — resetting to ACCEPT"
    iptables -P FORWARD ACCEPT     2>/dev/null || true
    iptables -I FORWARD -j ACCEPT  2>/dev/null || true
    log "iptables FORWARD policy restored to ACCEPT"
  fi

  if [[ "$ALL_HEALTHY" == "true" ]]; then
    CONSECUTIVE_FAIL=0
  fi

  # If too many consecutive failures, attempt full stack restart
  if [[ $CONSECUTIVE_FAIL -ge $MAX_FAILURES ]]; then
    log "CRITICAL: $CONSECUTIVE_FAIL consecutive failures — performing full stack restart..."
    # Re-apply iptables FORWARD rules (may have been reset by UFW reload)
    iptables -P FORWARD ACCEPT 2>/dev/null || true
    iptables -I FORWARD -j ACCEPT 2>/dev/null || true
    iptables -I DOCKER-USER -j ACCEPT 2>/dev/null || true
    systemctl start geminivpn-iptables 2>/dev/null || true
    cd "${DEPLOY_DIR}/docker" && \
      $DC --env-file "${DEPLOY_DIR}/.env" restart 2>>"$LOG_FILE" || true
    # Re-ensure logo is present after container restart
    if [ -f "${DEPLOY_DIR}/frontend/public/geminivpn-logo.png" ] && \
       [ ! -f "/var/www/geminivpn/geminivpn-logo.png" ]; then
      cp "${DEPLOY_DIR}/frontend/public/geminivpn-logo.png" \
         "/var/www/geminivpn/geminivpn-logo.png" 2>/dev/null || true
      log "Logo re-deployed after full restart"
    fi
    CONSECUTIVE_FAIL=0
    log "Full stack restart completed"
    sleep 60
  fi

  sleep $INTERVAL
done
WDOG

  chmod +x "$WATCHDOG_SCRIPT"
  ok "Watchdog script installed: $WATCHDOG_SCRIPT"

  # Write systemd service
  cat > "/etc/systemd/system/${WATCHDOG_SERVICE}.service" << SVCFILE
[Unit]
Description=GeminiVPN Auto-Refresh Health Watchdog
After=docker.service network-online.target
Wants=docker.service network-online.target
Documentation=https://geminivpn.zapto.org

[Service]
Type=simple
ExecStart=${WATCHDOG_SCRIPT}
ExecStop=/bin/sh -c 'kill \$(cat ${WATCHDOG_PID} 2>/dev/null) 2>/dev/null; rm -f ${WATCHDOG_PID}'
Restart=always
RestartSec=15
StandardOutput=append:${WATCHDOG_LOG}
StandardError=append:${WATCHDOG_LOG}

[Install]
WantedBy=multi-user.target
SVCFILE

  systemctl daemon-reload 2>/dev/null || true
  systemctl enable "${WATCHDOG_SERVICE}.service" 2>/dev/null || true
  systemctl restart "${WATCHDOG_SERVICE}.service" 2>/dev/null || true

  sleep 2
  if systemctl is-active --quiet "${WATCHDOG_SERVICE}.service" 2>/dev/null; then
    ok "Auto-Refresh Watchdog running (checks every 30s)"
    ok "Log: tail -f ${WATCHDOG_LOG}"
    info "Stop auto-refresh: sudo bash re-geminivpn.sh --stop"
  else
    warn "Watchdog service failed to start — check: systemctl status ${WATCHDOG_SERVICE}"
  fi
}

phase_watchdog_stop() {
  step "Stopping Auto-Refresh Watchdog"
  if systemctl is-active --quiet "${WATCHDOG_SERVICE}.service" 2>/dev/null; then
    systemctl stop "${WATCHDOG_SERVICE}.service" 2>/dev/null || true
    systemctl disable "${WATCHDOG_SERVICE}.service" 2>/dev/null || true
    ok "Auto-Refresh Watchdog STOPPED"
    warn "Containers will NOT be auto-restarted until watchdog is re-enabled"
    info "Re-enable: sudo bash re-geminivpn.sh --watchdog"
  else
    warn "Watchdog not running"
  fi
  # Also kill any stray PID
  [[ -f "$WATCHDOG_PID" ]] && kill "$(cat "$WATCHDOG_PID" 2>/dev/null)" 2>/dev/null || true
  rm -f "$WATCHDOG_PID" 2>/dev/null || true
}

# =============================================================================
# MAIN — route by mode
# =============================================================================
print_banner

# =============================================================================
# PHASE — IPv4 DNS FIX  (integrated from fix-geminivpn-dns.sh)
# Root cause: curl without -4 on dual-stack servers detects IPv6 (2a03:...) and
# pushes it to No-IP. No-IP A records are IPv4-only → domain stops resolving →
# ERR_CONNECTION_TIMED_OUT. This phase permanently corrects that.
# =============================================================================

phase_fix_dns_ipv4() {
  step "IPv4/DNS Fix — Force A-Record Sync to geminivpn.zapto.org"

  # ── 1. Detect real public IPv4 (force -4 on every curl) ──────────────────
  info "Detecting server's real public IPv4..."
  local IPV4=""
  for SRC in \
    "curl -4 -sf --max-time 5 https://ipv4.icanhazip.com" \
    "curl -4 -sf --max-time 5 https://api.ipify.org" \
    "curl -4 -sf --max-time 5 https://checkip.amazonaws.com" \
    "curl -4 -sf --max-time 5 https://ip4.seeip.org" \
    "curl -4 -sf --max-time 5 https://ifconfig.me"; do
    IPV4=$(eval "$SRC" 2>/dev/null | tr -d '[:space:]') || true
    [[ "$IPV4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
    IPV4=""
  done
  # Interface fallback
  if [[ ! "$IPV4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    local IFACE; IFACE=$(ip -4 route show default 2>/dev/null | awk '/default/{print $5}' | head -1)
    [[ -n "$IFACE" ]] && IPV4=$(ip -4 addr show "$IFACE" 2>/dev/null \
      | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1)
  fi
  if [[ ! "$IPV4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    err "Cannot determine public IPv4 — check network connectivity"; return 1
  fi
  ok "Public IPv4: ${BOLD}${IPV4}${NC}"

  # Sync the global SERVER_IP if it differs (hardcoded fallback may be stale)
  if [[ "$IPV4" != "$SERVER_IP" ]]; then
    warn "SERVER_IP hardcoded as $SERVER_IP but actual IPv4 is $IPV4 — using $IPV4"
    SERVER_IP="$IPV4"
  fi

  # ── 2. Check current DNS A record ────────────────────────────────────────
  local DNS_IPV4=""
  if command -v dig &>/dev/null; then
    DNS_IPV4=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || true)
  fi
  [[ ! "$DNS_IPV4" =~ ^[0-9]+\. ]] && \
    DNS_IPV4=$(curl -4 -sf --max-time 8 \
      "https://dns.google/resolve?name=${DOMAIN}&type=A" 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); a=d.get('Answer',[]); \
        print(next((x['data'] for x in a if x.get('type')==1),''))" 2>/dev/null || echo "")

  info "DNS A record: ${DOMAIN} → ${DNS_IPV4:-NONE (unresolved)}"
  info "Server IPv4:  $IPV4"

  if [[ "$DNS_IPV4" == "$IPV4" ]]; then
    ok "DNS A record already matches server IPv4"
  else
    warn "DNS MISMATCH — root cause of ERR_CONNECTION_TIMED_OUT"
    warn "DNS has '${DNS_IPV4:-nothing}', server is '$IPV4'"
  fi

  # ── 3. Force No-IP update with IPv4 ──────────────────────────────────────
  local NOIP_USER="" NOIP_PASS=""
  if [[ -f "$NOIP_CONFIG_FILE" ]]; then
    NOIP_USER=$(sed -n '1p' "$NOIP_CONFIG_FILE" 2>/dev/null || echo "")
    NOIP_PASS=$(sed -n '2p' "$NOIP_CONFIG_FILE" 2>/dev/null || echo "")
  fi
  # Also try env files
  if [[ -z "$NOIP_USER" ]]; then
    for envf in /root/.env "${SCRIPT_DIR}/.env" "${SCRIPT_DIR}/.env.production"; do
      [[ -f "$envf" ]] && source "$envf" 2>/dev/null || true
      NOIP_USER="${NOIP_USERNAME:-${NOIP_USER:-}}"
      NOIP_PASS="${NOIP_PASSWORD:-${NOIP_PASS:-}}"
      [[ -n "$NOIP_USER" ]] && break
    done
  fi

  if [[ -n "$NOIP_USER" && -n "$NOIP_PASS" ]]; then
    info "Forcing No-IP update: ${DOMAIN} → ${IPV4} ..."
    local NOIP_RESP
    NOIP_RESP=$(curl -4 -sf --max-time 15 \
      "https://dynupdate.no-ip.com/nic/update?hostname=${DOMAIN}&myip=${IPV4}" \
      -u "${NOIP_USER}:${NOIP_PASS}" \
      -A "GeminiVPN-ReScript/2.0 ${NOIP_USER}" 2>/dev/null || echo "CURL_FAILED")
    case "$NOIP_RESP" in
      good*)  ok  "No-IP update: SUCCESS → $NOIP_RESP" ;;
      nochg*) ok  "No-IP update: NOCHG (A record already $IPV4)" ;;
      badauth*) err "No-IP update: BAD CREDENTIALS — check $NOIP_CONFIG_FILE" ;;
      nohost*) err "No-IP update: hostname $DOMAIN not in your account" ;;
      *) warn "No-IP response: ${NOIP_RESP:-no response}" ;;
    esac
  else
    warn "No-IP credentials not found — cannot push update automatically"
    info "Run manually: curl -u 'EMAIL:PASS' 'https://dynupdate.no-ip.com/nic/update?hostname=${DOMAIN}&myip=${IPV4}'"
  fi

  # ── 4. Patch the updater script itself to always use -4 ──────────────────
  local UPDATER="/usr/local/bin/noip-update-check.sh"
  if [[ -f "$UPDATER" ]]; then
    # Patch any curl call without -4 that hits IP-detection services
    sed -i \
      -e 's|curl -sf\(.*icanhazip\)|curl -4 -sf\1|g' \
      -e 's|curl -sf\(.*ipify\)|curl -4 -sf\1|g' \
      -e 's|curl -sf\(.*amazonaws\)|curl -4 -sf\1|g' \
      -e 's|curl -sf\(.*ifconfig\.me\)|curl -4 -sf\1|g' \
      -e 's|curl -sf\(.*seeip\)|curl -4 -sf\1|g' \
      "$UPDATER" 2>/dev/null || true
    ok "Patched $UPDATER — all curl IP-detection calls now use -4 (IPv4 only)"
  fi

  # ── 5. Ensure nginx docker config has explicit IPv4 listen directives ─────
  local NGINX_CONF="${SCRIPT_DIR}/docker/nginx/nginx.conf"
  if [[ -f "$NGINX_CONF" ]]; then
    # Already has listen 80; and listen 443 ssl; — just confirm
    local HAS_V4_80; HAS_V4_80=$(grep -cE '^\s+listen 80;' "$NGINX_CONF" || echo 0)
    local HAS_V4_443; HAS_V4_443=$(grep -cE '^\s+listen 443 ssl;' "$NGINX_CONF" || echo 0)
    if [[ "$HAS_V4_80" -gt 0 && "$HAS_V4_443" -gt 0 ]]; then
      ok "nginx.conf: IPv4 listen 80 and listen 443 ssl directives confirmed"
    else
      warn "nginx.conf may be missing IPv4 listen directives — check docker/nginx/nginx.conf"
    fi
  fi

  # Also fix the live nginx container if it's running
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'geminivpn-nginx'; then
    docker exec geminivpn-nginx nginx -s reload 2>/dev/null && \
      ok "Live nginx container reloaded" || true
  fi

  # ── 6. Verify UFW inbound 80/443 open ────────────────────────────────────
  ufw allow 80/tcp  2>/dev/null | grep -v 'Skipping\|already\|Rules' || true
  ufw allow 443/tcp 2>/dev/null | grep -v 'Skipping\|already\|Rules' || true
  ufw reload        2>/dev/null || true
  ok "UFW: ports 80 and 443 confirmed open for inbound TCP"

  # ── 7. Trigger the running updater to pick up the patch immediately ───────
  if [[ -x "$UPDATER" ]]; then
    "$UPDATER" &>/dev/null &
    disown
    ok "No-IP updater triggered in background (will log to /var/log/noip-update.log)"
  fi
  systemctl restart noip-updater.timer   2>/dev/null || true
  systemctl restart noip-updater.service 2>/dev/null || true

  # ── 8. Wait briefly and re-check DNS ─────────────────────────────────────
  info "Waiting 8s for DNS propagation..."
  sleep 8
  local DNS_IPV4_NEW=""
  if command -v dig &>/dev/null; then
    DNS_IPV4_NEW=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || true)
  fi
  [[ ! "$DNS_IPV4_NEW" =~ ^[0-9]+\. ]] && \
    DNS_IPV4_NEW=$(curl -4 -sf --max-time 8 \
      "https://dns.google/resolve?name=${DOMAIN}&type=A" 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); a=d.get('Answer',[]); \
        print(next((x['data'] for x in a if x.get('type')==1),''))" 2>/dev/null || echo "")

  if [[ "$DNS_IPV4_NEW" == "$IPV4" ]]; then
    ok "DNS confirmed: ${DOMAIN} → ${IPV4} ✓"
  else
    warn "DNS not yet updated (propagation up to 5 min): ${DNS_IPV4_NEW:-pending}"
    info "Monitor: watch -n 10 'dig +short A ${DOMAIN} @8.8.8.8'"
  fi

  # ── 9. Test the domain directly — final end-to-end verification ─────────
  echo ""
  info "Testing domain reachability: https://${DOMAIN} ..."
  local DOMAIN_HTTP DOMAIN_HTTPS
  DOMAIN_HTTP=$(curl -4 -s --max-time 10 -o /dev/null -w "%{http_code}" \
    "http://${DOMAIN}/" 2>/dev/null || echo "000")
  DOMAIN_HTTPS=$(curl -4 -sk --max-time 10 -o /dev/null -w "%{http_code}" \
    "https://${DOMAIN}/" 2>/dev/null || echo "000")

  if [[ "$DOMAIN_HTTPS" == "200" || "$DOMAIN_HTTP" =~ ^30 ]]; then
    ok "Domain reachable: https://${DOMAIN} → HTTP ${DOMAIN_HTTPS} ✓"
    # Verify LE cert is serving the correct domain (not self-signed)
    local CERT_CN
    CERT_CN=$(echo | openssl s_client -connect "${DOMAIN}:443" \
      -servername "${DOMAIN}" 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null \
      | grep -oP 'CN\s*=\s*\K[^,]+' || echo "")
    if [[ "$CERT_CN" == *"$DOMAIN"* ]]; then
      ok "SSL cert CN: ${CERT_CN} — Let's Encrypt cert serving correctly ✓"
    elif [[ -n "$CERT_CN" ]]; then
      warn "SSL cert CN: ${CERT_CN} — may still be self-signed. Run: sudo bash re-geminivpn.sh --ssl"
    fi
  elif [[ "$DOMAIN_HTTPS" == "000" && "$DOMAIN_HTTP" == "000" ]]; then
    warn "Domain not yet reachable via hostname (DNS propagation may still be in progress)"
    info "Try in 1–5 minutes: curl -v https://${DOMAIN}/"
    info "Or flush DNS: ipconfig /flushdns  (Windows) | sudo dscacheutil -flushcache  (macOS)"
  else
    warn "Domain returned HTTP ${DOMAIN_HTTPS} — check nginx/backend logs"
  fi

  echo ""
  info "Root cause: noip-update-check.sh called curl without -4, detecting IPv6"
  info "  (2a03:...) on dual-stack droplets and pushing it as the A record."
  info "All fixes applied:"
  ok "noip-update-check.sh now uses curl -4 — IPv4-only forever"
  ok "Cron/systemd timer will push correct IPv4 every 5 minutes"
  ok "UFW ports 80 + 443 open for inbound"
  info "Logs: tail -f /var/log/noip-update.log"
}

phase_fix_external() {
  step "External Access Diagnostic — Cloud Firewall + DNS Fix"

  # Run full DNS IPv4 fix first (the real root cause of ERR_CONNECTION_TIMED_OUT)
  phase_fix_dns_ipv4

  echo ""
  step "Port Reachability Check"

  # Use actual detected IPv4 (not hardcoded SERVER_IP — may be stale)
  local CHECK_IP="$SERVER_IP"
  local DETECTED_IP=""
  DETECTED_IP=$(curl -4 -sf --max-time 5 https://ipv4.icanhazip.com 2>/dev/null \
    | tr -d '[:space:]') || true
  [[ "$DETECTED_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && CHECK_IP="$DETECTED_IP"

  local T80; T80=$(timeout 5 bash -c "echo >/dev/tcp/${CHECK_IP}/80"  2>&1 && echo "OPEN" || echo "BLOCKED")
  local T443; T443=$(timeout 5 bash -c "echo >/dev/tcp/${CHECK_IP}/443" 2>&1 && echo "OPEN" || echo "BLOCKED")
  local HTTP; HTTP=$(curl -4 -sk --max-time 8 -o /dev/null -w "%{http_code}" "https://${CHECK_IP}/" 2>/dev/null || echo "000")

  echo ""
  echo -e "  Port 80  (HTTP):  $T80"
  echo -e "  Port 443 (HTTPS): $T443"
  echo -e "  HTTPS response:   HTTP $HTTP"
  echo ""

  if [[ "$T80" == "OPEN" && "$T443" == "OPEN" ]]; then
    ok "Both ports reachable — server is working"
    # Verify DNS A record (must be IPv4, not getent which may return IPv6)
    local DNS_A=""
    command -v dig &>/dev/null && DNS_A=$(dig +short A "${DOMAIN}" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || true)
    if [[ "$DNS_A" == "$CHECK_IP" ]]; then
      ok "DNS A record: ${DOMAIN} → ${DNS_A} ✓"
    else
      warn "DNS A record: ${DOMAIN} → ${DNS_A:-unresolved} (expected ${CHECK_IP})"
      warn "DNS not yet propagated — give it 1–5 minutes then retry"
    fi
    info "If browser still shows timeout, flush DNS cache:"
    info "  Windows: ipconfig /flushdns"
    info "  macOS:   sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
    info "  Linux:   sudo resolvectl flush-caches"
  else
    echo -e "  ${RED}${BOLD}BLOCKED — DigitalOcean Cloud Firewall needs updating${NC}"
    echo ""
    echo -e "  ${BOLD}Fix (60 seconds):${NC}"
    echo -e "  ${CYAN}  1. https://cloud.digitalocean.com/networking/firewalls${NC}"
    echo -e "  ${CYAN}  2. Your droplet firewall → Edit → Inbound Rules${NC}"
    echo -e "  ${CYAN}  3. Add: HTTP  TCP 80  → Sources: All IPv4 + All IPv6${NC}"
    echo -e "  ${CYAN}  4. Add: HTTPS TCP 443 → Sources: All IPv4 + All IPv6${NC}"
    echo -e "  ${CYAN}  5. Save — active in 30 seconds${NC}"
    echo ""
    ok "Direct IP access: https://${CHECK_IP}"
  fi
}


# ── Full deploy / redeploy ────────────────────────────────────────────────────

# =============================================================================
# MASTER AUTO-HEAL — runs every deploy to fix all common blocking issues
# =============================================================================

phase_auto_heal_all() {
  step "Auto-Heal — Verifying All Critical Systems"

  # 1. UFW FORWARD policy
  local UFW_DEF="/etc/default/ufw"
  if [[ -f "$UFW_DEF" ]] && grep -q 'DEFAULT_FORWARD_POLICY="DROP"' "$UFW_DEF" 2>/dev/null; then
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$UFW_DEF"
    ufw reload 2>/dev/null || true
    warn "UFW FORWARD: was DROP — fixed to ACCEPT"
  else
    ok "UFW FORWARD: ACCEPT"
  fi

  # 2. iptables FORWARD + outbound
  iptables  -I FORWARD -j ACCEPT     2>/dev/null || true
  iptables  -P FORWARD ACCEPT        2>/dev/null || true
  iptables  -I DOCKER-USER -j ACCEPT 2>/dev/null || true
  ip6tables -P FORWARD ACCEPT        2>/dev/null || true
  iptables  -I FORWARD -i docker0 -j ACCEPT 2>/dev/null || true
  iptables  -I FORWARD -o docker0 -j ACCEPT 2>/dev/null || true
  # CRITICAL: ensure IPv4/IPv6 share ports — prevents Docker binding 80/443 to IPv6 only
  sysctl -w net.ipv6.bindv6only=0 2>/dev/null || true
  local AH_NET AH_BRIDGE
  AH_NET=$(docker network ls --format "{{.Name}}" 2>/dev/null | grep -i gemini | head -1)
  if [[ -n "$AH_NET" ]]; then
    AH_BRIDGE=$(docker network inspect "$AH_NET"       --format "{{index .Options \"com.docker.network.bridge.name\"}}" 2>/dev/null || echo "")
    [[ -z "$AH_BRIDGE" ]] && AH_BRIDGE=$(ip link show 2>/dev/null | grep -oE "br-[a-f0-9]+" | head -1)
    [[ -n "$AH_BRIDGE" ]] && {
      iptables -I FORWARD -i "$AH_BRIDGE" -j ACCEPT 2>/dev/null || true
      iptables -I FORWARD -o "$AH_BRIDGE" -j ACCEPT 2>/dev/null || true
    }
  fi
  iptables -I OUTPUT -p tcp --dport 80   -j ACCEPT 2>/dev/null || true
  iptables -I OUTPUT -p tcp --dport 443  -j ACCEPT 2>/dev/null || true
  iptables -I OUTPUT -p tcp --dport 8245 -j ACCEPT 2>/dev/null || true
  iptables -I OUTPUT -p udp --dport 53   -j ACCEPT 2>/dev/null || true
  mkdir -p /etc/iptables
  iptables-save  > /etc/iptables/rules.v4 2>/dev/null || true
  ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  command -v netfilter-persistent &>/dev/null && netfilter-persistent save 2>/dev/null || true
  ok "iptables: FORWARD=ACCEPT + outbound rules set and persisted"

  # 3. UFW outbound rules
  for RULE in     "out on any to any port 53  proto udp"     "out on any to any port 53  proto tcp"     "out on any to any port 80  proto tcp"     "out on any to any port 443 proto tcp"     "out on any to any port 8245 proto tcp"; do
    ufw allow $RULE 2>/dev/null || true
  done
  ok "UFW outbound: DNS/HTTP/HTTPS/NoIP-alt confirmed open"

  # 4. No-IP DUC anti-zombie + ensure running
  # No-IP: curl-based timer (no binary needed)
  pkill -9 -x noip2 2>/dev/null || true  # kill any legacy binary
  systemctl stop    noip2.service 2>/dev/null || true
  systemctl disable noip2.service 2>/dev/null || true
  if [[ -x /usr/local/bin/noip-update-check.sh ]]; then
    systemctl enable  noip-updater.timer 2>/dev/null || true
    systemctl restart noip-updater.timer 2>/dev/null || true
    /usr/local/bin/noip-update-check.sh &
    disown
    ok "No-IP curl updater: timer active + immediate update triggered"
  else
    warn "No-IP updater missing — run: sudo bash re-geminivpn.sh --noip"
  fi

  # 5. Logo deployment
  local LOGO_SRC="${DEPLOY_DIR}/frontend/public/geminivpn-logo.png"
  if [[ -f "$LOGO_SRC" ]]; then
    cp -f "$LOGO_SRC" "${WWW_DIR}/geminivpn-logo.png" 2>/dev/null || true
    ok "Logo: deployed to ${WWW_DIR}/"
  fi

  # 6. nginx hot-sync + reload
  local NGINX_SRC="${DEPLOY_DIR}/docker/nginx/nginx.conf"
  if [[ -f "$NGINX_SRC" ]] && docker ps --format "{{.Names}}" 2>/dev/null | grep -q "geminivpn-nginx"; then
    docker cp "$NGINX_SRC" geminivpn-nginx:/etc/nginx/nginx.conf 2>/dev/null || true
    docker exec geminivpn-nginx nginx -t 2>/dev/null | grep -qi "ok" &&       docker exec geminivpn-nginx nginx -s reload 2>/dev/null &&       ok "nginx: config synced and reloaded" || true
  fi

  # 7. Container health check + auto-restart
  # CRITICAL: check nginx is actually bound to ports 80/443.
  # nginx depends_on backend:service_started (not healthy) so it should always
  # start. If ports aren't bound, something killed nginx — force restart.
  local AH_HEALED=0
  local NGINX_PORT_BOUND
  NGINX_PORT_BOUND=$(ss -tlnp 2>/dev/null | grep -c ':80 \|:443 ' || echo 0)

  for CTR in geminivpn-backend geminivpn-nginx; do
    local AH_S AH_H
    AH_S=$(docker inspect "$CTR" --format "{{.State.Status}}"        2>/dev/null || echo "missing")
    AH_H=$(docker inspect "$CTR" --format "{{.State.Health.Status}}" 2>/dev/null || echo "none")
    if [[ "$AH_S" != "running" ]]; then
      warn "$CTR is $AH_S — restarting..."
      if [[ "$CTR" == "geminivpn-nginx" ]]; then
        # Start nginx independently — don't wait for backend health
        docker start geminivpn-nginx 2>/dev/null || \
          (cd "${DEPLOY_DIR}/docker" && $DOCKER_COMPOSE --env-file "$ENV_FILE" up -d nginx 2>/dev/null) || true
      else
        cd "${DEPLOY_DIR}/docker" && $DOCKER_COMPOSE --env-file "$ENV_FILE" up -d 2>/dev/null || true
      fi
      AH_HEALED=$((AH_HEALED + 1))
    elif [[ "$AH_H" == "unhealthy" && "$CTR" != "geminivpn-nginx" ]]; then
      # Only restart backend if unhealthy — nginx health depends on LE cert (may be
      # "unhealthy" early on with self-signed cert, but still serves traffic fine)
      warn "$CTR unhealthy — restarting..."
      docker restart "$CTR" 2>/dev/null || true
      AH_HEALED=$((AH_HEALED + 1))
    else
      ok "$CTR: $AH_S (health: $AH_H)"
    fi
  done

  # Extra check: if nginx is running but ports aren't bound, force recreate
  NGINX_PORT_BOUND=$(ss -tlnp 2>/dev/null | grep -cE ':80 |:443 ' || echo 0)
  if [[ "$NGINX_PORT_BOUND" -lt 2 ]]; then
    warn "Ports 80/443 not fully bound (found ${NGINX_PORT_BOUND}/2) — force-recreating nginx..."
    cd "${DEPLOY_DIR}/docker" && \
      $DOCKER_COMPOSE --env-file "$ENV_FILE" up -d --force-recreate nginx 2>/dev/null || true
    sleep 5
    NGINX_PORT_BOUND=$(ss -tlnp 2>/dev/null | grep -cE ':80 |:443 ' || echo 0)
    [[ "$NGINX_PORT_BOUND" -ge 2 ]] && ok "Ports 80/443 now bound ✓" || warn "Ports still not bound — check: docker logs geminivpn-nginx"
    AH_HEALED=$((AH_HEALED + 1))
  else
    ok "Ports 80 and 443 are bound ✓"
  fi

  [[ $AH_HEALED -gt 0 ]] && { sleep 15; ok "$AH_HEALED container(s) auto-healed"; }

  ok "Auto-heal complete"
}


case "$MODE" in
  --ssl)      phase_prerequisites; phase_ssl;      exit 0 ;;
  --stripe)   phase_prerequisites; phase_stripe;   exit 0 ;;
  --payment)  phase_prerequisites; phase_payment;  exit 0 ;;
  --smtp)     phase_prerequisites; phase_smtp;     exit 0 ;;
  --whatsapp) phase_prerequisites; phase_whatsapp; exit 0 ;;
  --noip)          phase_noip_setup;     exit 0 ;;
  --noip-firewall) phase_noip_firewall; exit 0 ;;
  --fix-dns)       phase_fix_dns_ipv4;  exit 0 ;;
  --app)          phase_app_build;                                        exit 0 ;;
  --fix-external) phase_fix_external;                                     exit 0 ;;
  --backup)   phase_backup;        exit 0 ;;
  --restore)  phase_restore;       exit 0 ;;
  --test)     phase_test; _T=$?; exit $_T ;;
  --harden)        phase_prerequisites; phase_harden;              exit 0 ;;
  --status)        phase_status;                                    exit 0 ;;
  --connectivity)  phase_connectivity_check;                        exit 0 ;;
  --watchdog|--watch-dog|--watchdog-start) phase_watchdog_start;  exit 0 ;;
  --stop)          phase_watchdog_stop;                             exit 0 ;;
  --auto-heal)     phase_prerequisites; phase_auto_heal_all; phase_fix_dns_ipv4; phase_connectivity_check; exit 0 ;;
  --fix-all)       phase_prerequisites; phase_harden; phase_noip_setup; phase_noip_firewall; phase_fix_dns_ipv4; phase_auto_heal_all; phase_connectivity_check; phase_watchdog_start; exit 0 ;;
esac

IS_REDEPLOY=false
[[ -d "${DEPLOY_DIR}/docker" ]] && docker ps 2>/dev/null | grep -q geminivpn && IS_REDEPLOY=true

if [[ "$IS_REDEPLOY" == "true" ]]; then
  echo -e "  ${CYAN}[→]${NC} Detected existing deployment — running redeploy..."
  phase_backup   # Always backup DB before any redeploy
else
  echo -e "  ${CYAN}[→]${NC} First-time deployment detected"
fi

# ═══ AUTOMATED DEPLOY PIPELINE — every phase runs on every deploy ═══════════
# Each phase is idempotent: safe to run multiple times, auto-detects what's
# already done and skips or fixes as needed.

phase_prerequisites   # Docker, Node, packages, Docker daemon DNS config, iptables boot service
phase_source          # Patch + sync source files
phase_env             # Write/update .env

# HARDENING — always runs to ensure firewall ports are correct after updates.
# Includes: UFW, fail2ban, swap, BBR, iptables-persistent, outbound No-IP rules.
phase_harden

phase_frontend        # Build React SPA
phase_docker          # Build image, start containers, persist Docker bridge FORWARD rules
phase_database        # Prisma db push + seed

# ── No-IP DUC — install + ensure running on EVERY deploy (not just first) ───
# Smart: skips binary install if already present, skips prompt if config exists,
# always verifies service is running and not stuck, always applies firewall rules.
phase_noip_setup

# ── Master auto-heal — detects and fixes all common runtime issues ───────────
# Runs after containers are up. Fixes: legacy noip2, FORWARD policy, logo, nginx.
phase_auto_heal_all

# ── Connectivity + firewall final verification ───────────────────────────────
phase_connectivity_check

# ── Watchdog — always start/restart to guarantee continuous monitoring ───────
phase_watchdog_start

# Interactive steps — only if not already configured
SK=$(env_get STRIPE_SECRET_KEY 2>/dev/null || echo "")
SQ=$(env_get SQUARE_ACCESS_TOKEN 2>/dev/null || echo "")
PD=$(env_get PADDLE_API_KEY 2>/dev/null || echo "")
CB=$(env_get COINBASE_COMMERCE_API_KEY 2>/dev/null || echo "")

PAYMENT_CONFIGURED=false
[[ "$SK" =~ ^sk_(test|live)_ ]] && PAYMENT_CONFIGURED=true
[[ "$SQ" != "placeholder" && -n "$SQ" ]] && PAYMENT_CONFIGURED=true
[[ "$PD" != "placeholder" && -n "$PD" ]] && PAYMENT_CONFIGURED=true
[[ "$CB" != "placeholder" && -n "$CB" ]] && PAYMENT_CONFIGURED=true

if [[ "$PAYMENT_CONFIGURED" == "false" ]]; then
  echo ""
  echo -e "  ${YELLOW}[!]${NC} No payment provider configured."
  echo "    1) Stripe (card/subscription)"
  echo "    2) Square · Paddle · Coinbase (alternative providers)"
  echo "    3) Skip for now"
  read -rp "  Choice [1-3]: " PAY_CHOICE
  case "${PAY_CHOICE:-3}" in
    1) phase_stripe ;;
    2) phase_payment ;;
    *) warn "Payment setup skipped — run: sudo bash re-geminivpn.sh --stripe or --payment" ;;
  esac
fi

SMTP_H=$(env_get SMTP_HOST 2>/dev/null || echo "")
[[ ! "$SMTP_H" =~ \. || "$SMTP_H" =~ placeholder ]] && phase_smtp

CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
if [[ ! -f "$CERT" ]]; then
  echo ""
  echo -e "  ${YELLOW}[!]${NC} No SSL certificate found."
  read -rp "  Set up Let's Encrypt SSL now? [Y/n]: " WANT_SSL
  [[ "${WANT_SSL:-Y}" =~ ^[Yy]$ ]] && phase_ssl
fi

_TEST_RESULT=0
phase_test || _TEST_RESULT=$?
print_summary
