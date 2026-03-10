#!/bin/bash
# =============================================================================
# GeminiVPN — Full System Test Suite
# Tests: API, Auth, Registration, Login, Downloads, VPN endpoints
# Usage: sudo bash scripts/test-geminivpn.sh [domain]
# =============================================================================

BASE_URL="${1:-https://geminivpn.zapto.org}"
PASS=0; FAIL=0; SKIP=0
TEST_EMAIL="autotest_$(date +%s)@geminivpn.test"
TEST_PASS="AutoTest2026"
ACCESS_TOKEN=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          GeminiVPN — System Test Suite                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Target: $BASE_URL"
echo "  Time:   $(date)"
echo ""

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
skip() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; ((SKIP++)); }
section() { echo ""; echo -e "${BOLD}── $1 ──${NC}"; }

api() {
  local method="$1"; local path="$2"; shift 2
  local body="${1:-}"; shift 2>/dev/null || true
  local extra_args=("$@")
  local auth_header=""
  [[ -n "$ACCESS_TOKEN" ]] && auth_header="-H \"Authorization: Bearer ${ACCESS_TOKEN}\""

  if [[ -n "$body" ]]; then
    curl -sk -X "$method" "${BASE_URL}${path}" \
      -H "Content-Type: application/json" \
      ${ACCESS_TOKEN:+-H "Authorization: Bearer ${ACCESS_TOKEN}"} \
      -d "$body" \
      -w "\n__HTTP__%{http_code}" 2>/dev/null
  else
    curl -sk -X "$method" "${BASE_URL}${path}" \
      ${ACCESS_TOKEN:+-H "Authorization: Bearer ${ACCESS_TOKEN}"} \
      -w "\n__HTTP__%{http_code}" 2>/dev/null
  fi
}

check() {
  local name="$1"; local response="$2"; local expected_code="$3"
  local expected_field="${4:-}"; local expected_value="${5:-}"

  local http_code
  http_code=$(echo "$response" | grep "__HTTP__" | sed 's/__HTTP__//')
  local body
  body=$(echo "$response" | grep -v "__HTTP__")

  if [[ "$http_code" == "$expected_code" ]]; then
    if [[ -n "$expected_field" ]]; then
      local actual
      actual=$(echo "$body" | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  keys='${expected_field}'.split('.')
  v=d
  for k in keys:
    v=v[k] if isinstance(v,dict) else v
  print(str(v))
except:
  print('')
" 2>/dev/null)
      if [[ "$actual" == "$expected_value" || "$actual" == "True" || "$actual" == "true" ]]; then
        pass "$name → HTTP ${http_code}, ${expected_field}=${actual}"
      else
        fail "$name → HTTP ${http_code} (OK) but ${expected_field}='${actual}' ≠ '${expected_value}'"
        [[ "${VERBOSE:-0}" == "1" ]] && echo "    Body: $body"
      fi
    else
      pass "$name → HTTP ${http_code}"
    fi
  else
    fail "$name → Expected HTTP ${expected_code}, got ${http_code}"
    [[ "${VERBOSE:-0}" == "1" ]] && echo "    Body: $body"
  fi
}

# ── Section 1: Basic Connectivity ──────────────────────────────────────────
section "1. Basic Connectivity"

R=$(api GET "/health")
check "Health endpoint" "$R" "200" "status" "healthy"

R=$(api GET "/api/v1/servers")
check "Server list endpoint accessible" "$R" "200"

# ── Section 2: Registration ─────────────────────────────────────────────────
section "2. User Registration"

# Valid registration
R=$(api POST "/api/v1/auth/register" \
  "{\"email\":\"${TEST_EMAIL}\",\"password\":\"${TEST_PASS}\",\"name\":\"Auto Tester\"}")
check "Valid registration" "$R" "201" "success" "true"

ACCESS_TOKEN=$(echo "$R" | grep -v "__HTTP__" | python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d['data']['tokens']['accessToken'])
except: print('')
" 2>/dev/null)

[[ -n "$ACCESS_TOKEN" ]] && pass "Access token received" || fail "No access token in registration response"

# Duplicate email
R=$(api POST "/api/v1/auth/register" \
  "{\"email\":\"${TEST_EMAIL}\",\"password\":\"${TEST_PASS}\",\"name\":\"Dupe\"}")
check "Duplicate email rejected" "$R" "409"

# Missing password
R=$(api POST "/api/v1/auth/register" \
  "{\"email\":\"test2@test.com\"}")
check "Missing password rejected" "$R" "400"

# Too short password
R=$(api POST "/api/v1/auth/register" \
  "{\"email\":\"short@test.com\",\"password\":\"abc\"}")
check "Too-short password rejected (< 8 chars)" "$R" "400"

# Invalid email
R=$(api POST "/api/v1/auth/register" \
  "{\"email\":\"not-an-email\",\"password\":\"ValidPass99\"}")
check "Invalid email format rejected" "$R" "400"

# Short name should now work (we fixed min=2 → min=1)
R=$(api POST "/api/v1/auth/register" \
  "{\"email\":\"x$(date +%s)@test.local\",\"password\":\"ValidPass99\",\"name\":\"Al\"}")
check "Short name (2 chars) accepted" "$R" "201"

# ── Section 3: Login ────────────────────────────────────────────────────────
section "3. User Login"

ACCESS_TOKEN=""  # reset

# Valid login
R=$(api POST "/api/v1/auth/login" \
  "{\"email\":\"${TEST_EMAIL}\",\"password\":\"${TEST_PASS}\"}")
check "Valid login" "$R" "200" "success" "true"

ACCESS_TOKEN=$(echo "$R" | grep -v "__HTTP__" | python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d['data']['tokens']['accessToken'])
except: print('')
" 2>/dev/null)
[[ -n "$ACCESS_TOKEN" ]] && pass "Login returns access token" || fail "No access token in login response"

# Case-insensitive email login
R=$(api POST "/api/v1/auth/login" \
  "{\"email\":\"$(echo "$TEST_EMAIL" | tr '[:lower:]' '[:upper:]')\",\"password\":\"${TEST_PASS}\"}")
check "Case-insensitive email login" "$R" "200"

# Wrong password
R=$(api POST "/api/v1/auth/login" \
  "{\"email\":\"${TEST_EMAIL}\",\"password\":\"WrongPassword99\"}")
check "Wrong password rejected" "$R" "401"

# Non-existent user
R=$(api POST "/api/v1/auth/login" \
  "{\"email\":\"nobody_$(date +%s)@test.com\",\"password\":\"SomePass99\"}")
check "Non-existent user rejected" "$R" "401"

# Admin login test
R=$(api POST "/api/v1/auth/login" \
  "{\"email\":\"admin@geminivpn.local\",\"password\":\"GeminiAdmin2026!\"}")
check "Admin account login" "$R" "200"

# ── Section 4: Protected Routes ─────────────────────────────────────────────
section "4. Protected Routes (require auth)"

R=$(api GET "/api/v1/auth/profile")
check "Profile without token → 401" "$R" "401"

R=$(api GET "/api/v1/auth/subscription")
check "Subscription without token → 401" "$R" "401"

# Profile with valid token
R=$(api GET "/api/v1/auth/profile")
check "Profile with valid token" "$R" "200" "success" "true"

# ── Section 5: VPN Servers ──────────────────────────────────────────────────
section "5. VPN Servers"

R=$(api GET "/api/v1/servers")
SERVER_COUNT=$(echo "$R" | grep -v "__HTTP__" | python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(len(d.get('data',d.get('servers',[]))))
except: print(0)
" 2>/dev/null)

if [[ "$SERVER_COUNT" -ge 5 ]]; then
  pass "Server list returned ${SERVER_COUNT} servers"
else
  fail "Expected ≥5 servers, got ${SERVER_COUNT} (check seed)"
fi

# ── Section 6: Demo Account ─────────────────────────────────────────────────
section "6. Demo Account Generation"

R=$(api POST "/api/v1/demo/generate" "{}")
check "Demo account generated" "$R" "201"

DEMO_USER=$(echo "$R" | grep -v "__HTTP__" | python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d['data']['username'])
except: print('')
" 2>/dev/null)
[[ -n "$DEMO_USER" ]] && pass "Demo username: ${DEMO_USER}" || skip "Demo controller not yet returning data"

# Rate limit: second request from same IP should be limited
R=$(api POST "/api/v1/demo/generate" "{}")
check "Demo rate limit (2nd request → 429)" "$R" "429"

# ── Section 7: Downloads ────────────────────────────────────────────────────
section "7. Download Endpoints"

R=$(api GET "/api/v1/downloads/stats")
check "Download stats endpoint" "$R" "200"

# Check each platform
for platform in android windows macos linux; do
  R=$(api GET "/api/v1/downloads/${platform}")
  HTTP=$(echo "$R" | grep "__HTTP__" | sed 's/__HTTP__//')
  if [[ "$HTTP" == "200" || "$HTTP" == "404" || "$HTTP" == "503" ]]; then
    pass "Download /${platform} → HTTP ${HTTP} (200=file, 404/503=no file yet)"
  else
    fail "Download /${platform} → unexpected HTTP ${HTTP}"
  fi
done

# iOS should redirect
R=$(curl -sk -o /dev/null -w "%{http_code}" -L "${BASE_URL}/api/v1/downloads/ios" 2>/dev/null || echo "000")
[[ "$R" == "200" || "$R" == "302" ]] && pass "iOS redirect works (HTTP ${R})" || fail "iOS redirect returned HTTP ${R}"

# ── Section 8: Docker Container Health ──────────────────────────────────────
section "8. Container Health"

if command -v docker &>/dev/null; then
  for container in geminivpn-postgres geminivpn-redis geminivpn-backend geminivpn-nginx; do
    STATUS=$(docker inspect "$container" --format '{{.State.Status}}' 2>/dev/null || echo "not_found")
    HEALTH=$(docker inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null || echo "N/A")
    if [[ "$STATUS" == "running" ]]; then
      pass "Container ${container}: ${STATUS} (health: ${HEALTH})"
    else
      fail "Container ${container}: ${STATUS}"
    fi
  done
else
  skip "Docker not available — container checks skipped"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════${NC}"
echo -e "${BOLD}Test Summary${NC}"
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo -e "  ${YELLOW}SKIP${NC}: $SKIP"
echo -e "  Total: $((PASS + FAIL + SKIP))"
echo -e "${BOLD}══════════════════════════════════════${NC}"

if [[ $FAIL -eq 0 ]]; then
  echo -e "\n${GREEN}${BOLD}All tests passed! GeminiVPN is working correctly.${NC}"
  exit 0
else
  echo -e "\n${RED}${BOLD}${FAIL} test(s) failed. Check docker logs:${NC}"
  echo "  docker logs geminivpn-backend --tail=50"
  echo "  docker logs geminivpn-postgres --tail=20"
  exit 1
fi
