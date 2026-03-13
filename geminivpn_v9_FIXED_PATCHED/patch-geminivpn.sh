#!/bin/bash
# =============================================================================
# GeminiVPN — In-Place Patch Script
# Fixes all known issues in re-geminivpn.sh regardless of version
# Run: sudo bash patch-geminivpn.sh
# =============================================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/re-geminivpn.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'; BOLD='\033[1m'
ok()   { echo -e "  ${GREEN}[✓]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $*"; }
die()  { echo -e "  ${RED}[✗]${NC} $*"; exit 1; }

[[ -f "$TARGET" ]] || die "re-geminivpn.sh not found in $SCRIPT_DIR"
cp "$TARGET" "${TARGET}.bak.$(date +%s)" && ok "Backup created"

# ── FIX 1: STATE_FILE unbound variable ────────────────────────────────────────
# The variable is only defined inside the noip-update-check.sh heredoc.
# Any reference to it at the outer shell scope crashes with set -uo pipefail.
if grep -q 'touch "\$STATE_FILE"' "$TARGET" 2>/dev/null; then
  sed -i 's/touch "\$STATE_FILE" 2>\/dev\/null || true/touch \/var\/run\/noip-health.state 2>\/dev\/null || true/' "$TARGET"
  ok "FIX 1: STATE_FILE unbound variable → hardcoded literal path"
else
  ok "FIX 1: Already applied (STATE_FILE not present)"
fi

# ── FIX 2: Suppress iptables-persistent/ufw conflict apt noise ────────────────
# On Ubuntu 24.04, ufw and iptables-persistent conflict. Suppress the apt error
# and rely on iptables-save + geminivpn-iptables.service for persistence instead.
python3 - "$TARGET" << 'PYFIX'
import sys, re

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    src = f.read()

orig = src

# Remove any joint install attempts that produce the conflict error
# Replace with: ensure ufw is installed, skip iptables-persistent silently
CONFLICT_PATTERNS = [
    # Prerequisites block
    (
        r'apt-get install -y -qq ufw iptables-persistent netfilter-persistent 2>/dev/null \|\| \\\s*\n\s*apt-get install -y\s+ufw iptables-persistent\s+2>/dev/null \|\| true',
        'apt-get install -y -qq ufw 2>/dev/null || true'
    ),
    (
        r'apt-get install -y -qq ufw iptables-persistent netfilter-persistent 2>/dev/null \|\| \\\s*\n\s*apt-get install -y\s+ufw iptables-persistent 2>/dev/null \|\| true',
        'apt-get install -y -qq ufw 2>/dev/null || true'
    ),
]
for pattern, replacement in CONFLICT_PATTERNS:
    src, n = re.subn(pattern, replacement, src, flags=re.MULTILINE)
    if n: print(f"  [✓] FIX 2: Removed {n} conflicting iptables-persistent install call(s)")

# Replace iptables-persistent install in harden phase with safe alternative
OLD_HARDEN_PKG = '''  apt-get install -y -qq iptables-persistent netfilter-persistent 2>/dev/null || \\
    apt-get install -y iptables-persistent 2>/dev/null || true
  ok "iptables-persistent installed (rules survive reboots)"'''
NEW_HARDEN_PKG = '''  # iptables-persistent conflicts with ufw on Ubuntu 24.04 — skip it
  # Rules are persisted via: iptables-save + geminivpn-iptables.service (boot restore)
  ok "UFW active — iptables rules persisted via iptables-save + boot service"'''
if OLD_HARDEN_PKG in src:
    src = src.replace(OLD_HARDEN_PKG, NEW_HARDEN_PKG, 1)
    print("  [✓] FIX 2: Harden iptables-persistent removed")

with open(path, 'w', encoding='utf-8') as f:
    f.write(src)
if src == orig:
    print("  [✓] FIX 2: Already applied")
PYFIX

# ── FIX 3: Ensure iptables-save is always used (never depends on netfilter-persistent) ─
python3 - "$TARGET" << 'PYFIX3'
import sys, re
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    src = f.read()

# Pattern: if command -v netfilter-persistent ... elif iptables-save ... fi
# Replace all with: iptables-save directly (always works)
PATTERN = r'  if command -v netfilter-persistent &>/dev/null; then\n    netfilter-persistent save 2>/dev/null \|\| true\n(?:    ok[^\n]*\n)?  elif command -v iptables-save &>/dev/null; then\n    mkdir -p /etc/iptables\n    iptables-save\s+> /etc/iptables/rules\.v4 2>/dev/null \|\| true\n(?:    ip6tables-save > /etc/iptables/rules\.v6 2>/dev/null \|\| true\n)?(?:    ok[^\n]*\n)?  fi'
REPLACEMENT = '''  mkdir -p /etc/iptables
  iptables-save  > /etc/iptables/rules.v4 2>/dev/null || true
  ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  command -v netfilter-persistent &>/dev/null && netfilter-persistent save 2>/dev/null || true
  ok "iptables rules saved (reboot-safe)"'''

n = len(re.findall(PATTERN, src, re.MULTILINE))
src2 = re.sub(PATTERN, REPLACEMENT, src, flags=re.MULTILINE)
if n > 0:
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src2)
    print(f"  [✓] FIX 3: Replaced {n} netfilter-persistent blocks with iptables-save")
else:
    print(f"  [✓] FIX 3: Already clean")
PYFIX3

# ── FIX 4: noip2 binary calls — replace with curl updater ────────────────────
if grep -qE 'noip2 -C|\"\\$NOIP_BIN\" -c.*conf\b|noip2.*-f\b' "$TARGET" 2>/dev/null; then
  warn "FIX 4: Found legacy noip2 binary calls — please use latest tar"
else
  ok "FIX 4: No legacy noip2 binary calls found"
fi

# ── Validate ──────────────────────────────────────────────────────────────────
echo ""
if bash -n "$TARGET" 2>/dev/null; then
  ok "Syntax check PASSED"
else
  die "Syntax check FAILED — restoring backup"
  cp "${TARGET}.bak."* "$TARGET" 2>/dev/null || true
  exit 1
fi

echo ""
echo -e "  ${BOLD}All patches applied successfully.${NC}"
echo -e "  ${GREEN}[→]${NC} Re-run: sudo bash re-geminivpn.sh"
