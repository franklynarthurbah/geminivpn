#!/usr/bin/env bash
# =============================================================================
# GeminiVPN — Account Manager
# Manage users, generate accounts, set limits, view status
# Usage: sudo bash scripts/account-manager.sh [command] [options]
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠  $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "${CYAN}→ $1${NC}"; }

# ── Load environment ──────────────────────────────────────────────────────────
ENV_FILE="/opt/geminivpn/.env"
[[ -f "$ENV_FILE" ]] || ENV_FILE="$(dirname "$0")/../.env"
[[ -f "$ENV_FILE" ]] || fail "No .env file found. Run deploy-production.sh first."
source "$ENV_FILE"

DB_URL="${DATABASE_URL:-postgresql://geminivpn:geminivpn_db_pass@localhost:5432/geminivpn}"
CONTAINER="geminivpn-postgres"

# ── Helper: run SQL ───────────────────────────────────────────────────────────
run_sql() {
  local sql="$1"
  docker exec -i "$CONTAINER" psql -U "${DB_USER:-geminivpn}" -d "${DB_NAME:-geminivpn}" \
    -t -c "$sql" 2>/dev/null | sed 's/^ *//;s/ *$//' | grep -v '^$' || true
}

run_sql_pretty() {
  local sql="$1"
  docker exec -i "$CONTAINER" psql -U "${DB_USER:-geminivpn}" -d "${DB_NAME:-geminivpn}" \
    -c "$sql" 2>/dev/null || true
}

# ── Helper: hash password via Node ───────────────────────────────────────────
hash_password() {
  local pass="$1"
  docker exec geminivpn-backend node -e "
    const bcrypt = require('bcryptjs');
    bcrypt.hash('${pass}', 12).then(h => process.stdout.write(h));
  " 2>/dev/null || \
  node -e "const b=require('bcryptjs');b.hash('${pass}',12).then(h=>process.stdout.write(h));" 2>/dev/null || \
  python3 -c "import subprocess,sys; print('hash_unavailable')"
}

# =============================================================================
# COMMANDS
# =============================================================================

cmd_help() {
  echo -e "${BOLD}${CYAN}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║            GeminiVPN — Account Manager                     ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo "Usage: sudo bash account-manager.sh <command> [options]"
  echo ""
  echo -e "${BOLD}Commands:${NC}"
  echo "  list               List all users"
  echo "  create             Create a new user account (interactive)"
  echo "  create-batch N     Create N test accounts at once"
  echo "  set-active EMAIL   Activate user subscription (no expiry)"
  echo "  set-trial EMAIL D  Set trial period (D = days)"
  echo "  set-expired EMAIL  Mark account as expired"
  echo "  reset-pass EMAIL   Reset user password (interactive)"
  echo "  delete EMAIL       Deactivate (soft-delete) user"
  echo "  info EMAIL         Show detailed user info"
  echo "  stats              Show platform statistics"
  echo "  demo-list          List all demo accounts"
  echo "  demo-cleanup       Delete expired demo accounts"
  echo "  admin-create       Create an admin test account"
  echo ""
  echo -e "${BOLD}Examples:${NC}"
  echo "  sudo bash account-manager.sh create"
  echo "  sudo bash account-manager.sh set-active user@example.com"
  echo "  sudo bash account-manager.sh set-trial user@example.com 30"
  echo "  sudo bash account-manager.sh create-batch 10"
}

cmd_list() {
  echo -e "\n${BOLD}=== GeminiVPN Users ===${NC}\n"
  run_sql_pretty "
    SELECT 
      substring(email, 1, 35) AS email,
      substring(name, 1, 20) AS name,
      \"subscriptionStatus\" AS status,
      CASE WHEN \"trialEndsAt\" IS NOT NULL 
           THEN to_char(\"trialEndsAt\", 'YYYY-MM-DD') 
           ELSE '' END AS trial_ends,
      CASE WHEN \"subscriptionEndsAt\" IS NOT NULL 
           THEN to_char(\"subscriptionEndsAt\", 'YYYY-MM-DD') 
           ELSE '' END AS sub_ends,
      \"isActive\" AS active,
      \"isTestUser\" AS test,
      to_char(\"createdAt\", 'YYYY-MM-DD') AS created
    FROM \"User\"
    ORDER BY \"createdAt\" DESC
    LIMIT 50;
  "
  echo ""
  local count
  count=$(run_sql "SELECT COUNT(*) FROM \"User\";")
  echo "Total users: $count"
}

cmd_create() {
  echo -e "\n${BOLD}=== Create New User ===${NC}\n"
  
  read -rp "Email: " email
  [[ -z "$email" ]] && fail "Email is required"
  
  read -rp "Name (optional): " name
  name="${name:-GeminiVPN User}"
  
  read -rsp "Password (min 8 chars): " password
  echo ""
  [[ ${#password} -lt 8 ]] && fail "Password must be at least 8 characters"
  
  echo "Subscription status:"
  echo "  1) TRIAL (3 days)"
  echo "  2) ACTIVE (never expires)"
  echo "  3) ACTIVE (custom expiry)"
  read -rp "Choice [1]: " choice
  choice="${choice:-1}"
  
  local status trial_ends sub_ends
  case "$choice" in
    1)
      status="TRIAL"
      trial_date=$(date -d "+3 days" '+%Y-%m-%d' 2>/dev/null || date -v+3d '+%Y-%m-%d')
      trial_ends="'${trial_date}'"
      sub_ends="NULL"
      ;;
    2)
      status="ACTIVE"
      trial_ends="NULL"
      sub_ends="'2099-12-31'"
      ;;
    3)
      read -rp "Subscription end date (YYYY-MM-DD): " sub_date
      status="ACTIVE"
      trial_ends="NULL"
      sub_ends="'${sub_date}'"
      ;;
    *)
      status="TRIAL"
      trial_date=$(date -d "+3 days" '+%Y-%m-%d' 2>/dev/null || date -v+3d '+%Y-%m-%d')
      trial_ends="'${trial_date}'"
      sub_ends="NULL"
      ;;
  esac

  info "Hashing password..."
  local hashed
  hashed=$(hash_password "$password")
  [[ "$hashed" == "hash_unavailable" ]] && fail "Could not hash password. Make sure Docker backend is running."

  local email_lower
  email_lower=$(echo "$email" | tr '[:upper:]' '[:lower:]')
  local user_id
  user_id=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")

  run_sql "
    INSERT INTO \"User\" (
      id, email, password, name, 
      \"subscriptionStatus\", \"trialEndsAt\", \"subscriptionEndsAt\",
      \"isActive\", \"isTestUser\", \"emailVerified\",
      \"createdAt\", \"updatedAt\"
    ) VALUES (
      '${user_id}', '${email_lower}', '${hashed}', '${name}',
      '${status}', ${trial_ends}, ${sub_ends},
      true, false, true,
      NOW(), NOW()
    ) ON CONFLICT (email) DO NOTHING;
  " > /dev/null

  local inserted
  inserted=$(run_sql "SELECT COUNT(*) FROM \"User\" WHERE email='${email_lower}';")
  if [[ "$inserted" -gt 0 ]]; then
    ok "User created successfully!"
    echo -e "\n  Email:    ${email_lower}"
    echo "  Password: (as entered)"
    echo "  Status:   ${status}"
    [[ -n "${sub_ends//NULL/}" ]] && echo "  Expires:  ${sub_ends//\'/}"
  else
    warn "User already exists with that email."
  fi
}

cmd_create_batch() {
  local count="${1:-5}"
  echo -e "\n${BOLD}=== Creating ${count} Test Accounts ===${NC}\n"
  
  local created=0
  for i in $(seq 1 "$count"); do
    local suffix
    suffix=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
    local email="testuser_${suffix}@geminivpn.test"
    local password="TestPass${suffix}"
    local name="Test User ${i}"
    
    local hashed
    hashed=$(hash_password "$password") || continue
    [[ "$hashed" == "hash_unavailable" ]] && fail "Docker backend not running"

    local user_id
    user_id=$(python3 -c "import uuid; print(uuid.uuid4())")
    local trial_date
    trial_date=$(date -d "+3 days" '+%Y-%m-%d' 2>/dev/null || date -v+3d '+%Y-%m-%d')

    run_sql "
      INSERT INTO \"User\" (
        id, email, password, name,
        \"subscriptionStatus\", \"trialEndsAt\",
        \"isActive\", \"isTestUser\", \"emailVerified\",
        \"createdAt\", \"updatedAt\"
      ) VALUES (
        '${user_id}', '${email}', '${hashed}', '${name}',
        'TRIAL', '${trial_date}',
        true, true, true,
        NOW(), NOW()
      );
    " > /dev/null 2>&1 && {
      echo "  ✓ ${email} / ${password}"
      ((created++))
    } || warn "  Failed to create ${email}"
  done

  echo ""
  ok "Created ${created}/${count} test accounts"
  echo ""
  echo "Log them in at: https://geminivpn.zapto.org"
}

cmd_set_active() {
  local email="${1:-}"
  [[ -z "$email" ]] && { read -rp "Email: " email; }
  email=$(echo "$email" | tr '[:upper:]' '[:lower:]')

  run_sql "
    UPDATE \"User\" SET 
      \"subscriptionStatus\" = 'ACTIVE',
      \"subscriptionEndsAt\" = '2099-12-31',
      \"trialEndsAt\" = NULL,
      \"isActive\" = true,
      \"updatedAt\" = NOW()
    WHERE email ILIKE '${email}';
  " > /dev/null

  local rows
  rows=$(run_sql "SELECT COUNT(*) FROM \"User\" WHERE email ILIKE '${email}';")
  [[ "$rows" -gt 0 ]] && ok "Account ${email} set to ACTIVE (never expires)" || warn "No user found with email: ${email}"
}

cmd_set_trial() {
  local email="${1:-}"
  local days="${2:-3}"
  [[ -z "$email" ]] && { read -rp "Email: " email; }
  email=$(echo "$email" | tr '[:upper:]' '[:lower:]')

  local trial_date
  trial_date=$(date -d "+${days} days" '+%Y-%m-%d' 2>/dev/null || date -v+${days}d '+%Y-%m-%d')

  run_sql "
    UPDATE \"User\" SET
      \"subscriptionStatus\" = 'TRIAL',
      \"trialEndsAt\" = '${trial_date}',
      \"subscriptionEndsAt\" = NULL,
      \"isActive\" = true,
      \"updatedAt\" = NOW()
    WHERE email ILIKE '${email}';
  " > /dev/null

  ok "Account ${email} set to TRIAL — expires ${trial_date}"
}

cmd_set_expired() {
  local email="${1:-}"
  [[ -z "$email" ]] && { read -rp "Email: " email; }
  email=$(echo "$email" | tr '[:upper:]' '[:lower:]')

  run_sql "
    UPDATE \"User\" SET
      \"subscriptionStatus\" = 'EXPIRED',
      \"updatedAt\" = NOW()
    WHERE email ILIKE '${email}';
  " > /dev/null

  ok "Account ${email} set to EXPIRED"
}

cmd_reset_pass() {
  local email="${1:-}"
  [[ -z "$email" ]] && { read -rp "Email: " email; }
  email=$(echo "$email" | tr '[:upper:]' '[:lower:]')

  read -rsp "New password (min 8 chars): " password
  echo ""
  [[ ${#password} -lt 8 ]] && fail "Password must be at least 8 characters"

  local hashed
  hashed=$(hash_password "$password")
  [[ "$hashed" == "hash_unavailable" ]] && fail "Docker backend not running"

  run_sql "
    UPDATE \"User\" SET
      password = '${hashed}',
      \"updatedAt\" = NOW()
    WHERE email ILIKE '${email}';
  " > /dev/null

  ok "Password reset for ${email}"
}

cmd_delete() {
  local email="${1:-}"
  [[ -z "$email" ]] && { read -rp "Email: " email; }
  email=$(echo "$email" | tr '[:upper:]' '[:lower:]')

  read -rp "Deactivate ${email}? This will prevent login. [y/N]: " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { info "Cancelled."; return; }

  run_sql "
    UPDATE \"User\" SET
      \"isActive\" = false,
      \"updatedAt\" = NOW()
    WHERE email ILIKE '${email}';
  " > /dev/null

  ok "Account ${email} deactivated"
}

cmd_info() {
  local email="${1:-}"
  [[ -z "$email" ]] && { read -rp "Email: " email; }
  email=$(echo "$email" | tr '[:upper:]' '[:lower:]')

  echo -e "\n${BOLD}=== User Info: ${email} ===${NC}\n"
  run_sql_pretty "
    SELECT 
      id, email, name,
      \"subscriptionStatus\",
      \"trialEndsAt\",
      \"subscriptionEndsAt\",
      \"isActive\",
      \"isTestUser\",
      \"emailVerified\",
      \"lastLoginAt\",
      \"createdAt\"
    FROM \"User\"
    WHERE email ILIKE '${email}';
  "

  echo -e "\n${BOLD}VPN Clients:${NC}"
  run_sql_pretty "
    SELECT name, \"assignedIp\", \"isConnected\", \"lastConnectedAt\", \"createdAt\"
    FROM \"VPNClient\"
    WHERE \"userId\" = (SELECT id FROM \"User\" WHERE email ILIKE '${email}');
  "

  echo -e "\n${BOLD}Recent Sessions:${NC}"
  run_sql_pretty "
    SELECT \"ipAddress\", \"userAgent\", \"isValid\", \"lastUsedAt\", \"expiresAt\"
    FROM \"Session\"
    WHERE \"userId\" = (SELECT id FROM \"User\" WHERE email ILIKE '${email}')
    ORDER BY \"createdAt\" DESC LIMIT 5;
  "
}

cmd_stats() {
  echo -e "\n${BOLD}=== GeminiVPN Platform Statistics ===${NC}\n"

  echo -e "${BOLD}User Counts by Status:${NC}"
  run_sql_pretty "
    SELECT \"subscriptionStatus\" AS status, COUNT(*) AS count
    FROM \"User\"
    GROUP BY \"subscriptionStatus\"
    ORDER BY count DESC;
  "

  echo -e "\n${BOLD}Registrations (last 7 days):${NC}"
  run_sql_pretty "
    SELECT to_char(\"createdAt\"::date, 'YYYY-MM-DD') AS date, COUNT(*) AS new_users
    FROM \"User\"
    WHERE \"createdAt\" > NOW() - INTERVAL '7 days'
    GROUP BY date ORDER BY date DESC;
  "

  echo -e "\n${BOLD}Active VPN Connections:${NC}"
  run_sql_pretty "
    SELECT COUNT(*) AS connected_clients FROM \"VPNClient\" WHERE \"isConnected\" = true;
  "

  echo -e "\n${BOLD}Download Stats:${NC}"
  run_sql_pretty "
    SELECT platform, COUNT(*) AS downloads
    FROM \"DownloadLog\"
    GROUP BY platform ORDER BY downloads DESC;
  "

  echo -e "\n${BOLD}Demo Accounts:${NC}"
  run_sql_pretty "
    SELECT 
      COUNT(*) FILTER (WHERE \"expiresAt\" > NOW()) AS active_demos,
      COUNT(*) FILTER (WHERE \"expiresAt\" <= NOW()) AS expired_demos,
      COUNT(*) FILTER (WHERE \"convertedToPaid\" = true) AS converted
    FROM \"DemoAccount\";
  " 2>/dev/null || echo "  (DemoAccount table not yet populated)"
}

cmd_demo_list() {
  echo -e "\n${BOLD}=== Demo Accounts ===${NC}\n"
  run_sql_pretty "
    SELECT 
      d.username,
      u.email,
      d.\"creatorIp\",
      d.\"expiresAt\",
      d.\"convertedToPaid\",
      CASE WHEN d.\"expiresAt\" > NOW() THEN 'ACTIVE' ELSE 'EXPIRED' END AS status
    FROM \"DemoAccount\" d
    JOIN \"User\" u ON d.\"userId\" = u.id
    ORDER BY d.\"createdAt\" DESC
    LIMIT 50;
  " 2>/dev/null || warn "No demo accounts found or table doesn't exist yet."
}

cmd_demo_cleanup() {
  info "Cleaning up expired demo accounts..."
  local cleaned
  cleaned=$(run_sql "
    WITH deleted AS (
      DELETE FROM \"User\"
      WHERE id IN (
        SELECT \"userId\" FROM \"DemoAccount\"
        WHERE \"expiresAt\" < NOW()
          AND \"convertedToPaid\" = false
          AND \"isDeleted\" = false
      )
      RETURNING id
    ) SELECT COUNT(*) FROM deleted;
  " 2>/dev/null || echo "0")
  ok "Cleaned up ${cleaned} expired demo accounts"
}

cmd_admin_create() {
  echo -e "\n${BOLD}=== Create Admin Test Account ===${NC}\n"
  info "Creating admin account: admin@geminivpn.local / GeminiAdmin2026!"

  local hashed
  hashed=$(hash_password "GeminiAdmin2026!")
  [[ "$hashed" == "hash_unavailable" ]] && fail "Docker backend not running"

  local user_id
  user_id=$(python3 -c "import uuid; print(uuid.uuid4())")

  run_sql "
    INSERT INTO \"User\" (
      id, email, password, name,
      \"subscriptionStatus\", \"subscriptionEndsAt\",
      \"isActive\", \"isTestUser\", \"emailVerified\",
      \"createdAt\", \"updatedAt\"
    ) VALUES (
      '${user_id}',
      'admin@geminivpn.local',
      '${hashed}',
      'GeminiVPN Admin',
      'ACTIVE', '2099-12-31',
      true, true, true,
      NOW(), NOW()
    )
    ON CONFLICT (email) DO UPDATE SET
      password = EXCLUDED.password,
      \"subscriptionStatus\" = 'ACTIVE',
      \"subscriptionEndsAt\" = '2099-12-31',
      \"isActive\" = true,
      \"updatedAt\" = NOW();
  " > /dev/null

  ok "Admin account ready!"
  echo ""
  echo "  Email:    admin@geminivpn.local"
  echo "  Password: GeminiAdmin2026!"
  echo "  Status:   ACTIVE (never expires)"
  echo ""
  warn "Change this password after first login!"
}

# =============================================================================
# Main
# =============================================================================

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
  list)           cmd_list ;;
  create)         cmd_create ;;
  create-batch)   cmd_create_batch "${1:-5}" ;;
  set-active)     cmd_set_active "${1:-}" ;;
  set-trial)      cmd_set_trial "${1:-}" "${2:-3}" ;;
  set-expired)    cmd_set_expired "${1:-}" ;;
  reset-pass)     cmd_reset_pass "${1:-}" ;;
  delete)         cmd_delete "${1:-}" ;;
  info)           cmd_info "${1:-}" ;;
  stats)          cmd_stats ;;
  demo-list)      cmd_demo_list ;;
  demo-cleanup)   cmd_demo_cleanup ;;
  admin-create)   cmd_admin_create ;;
  help|--help|-h) cmd_help ;;
  *)              warn "Unknown command: $COMMAND"; cmd_help ;;
esac
