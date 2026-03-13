#!/usr/bin/env bash
# ============================================================
#  GeminiVPN — Linux Installer (WireGuard)
#  Supports: Ubuntu 20+, Debian 11+, Fedora 36+, Arch Linux
#  Usage: bash GeminiVPN-linux-install.sh
# ============================================================
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${CYAN}[→]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════╗${NC}"
echo -e "${BOLD}║   GeminiVPN — Linux Installer    ║${NC}"
echo -e "${BOLD}║   Powered by WireGuard®          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════╝${NC}"
echo ""

# Detect distro
if   command -v apt-get &>/dev/null; then PKG="apt-get install -y wireguard wireguard-tools resolvconf"
elif command -v dnf     &>/dev/null; then PKG="dnf install -y wireguard-tools"
elif command -v pacman  &>/dev/null; then PKG="pacman -S --noconfirm wireguard-tools"
elif command -v zypper  &>/dev/null; then PKG="zypper install -y wireguard-tools"
else err "Unsupported distro. Install wireguard-tools manually."; fi

info "Installing WireGuard…"
[[ $EUID -ne 0 ]] && SUDO="sudo" || SUDO=""
$SUDO $PKG 2>/dev/null || { info "Trying alternative install…"; $SUDO apt-get install -y wireguard 2>/dev/null || err "Install failed"; }
ok "WireGuard installed: $(wg --version 2>/dev/null)"

# Prompt for config
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Log in at https://geminivpn.zapto.org"
echo "  2. Go to Dashboard → Devices → Add Device"
echo "  3. Download your personal WireGuard config (.conf)"
echo "  4. Run: sudo wg-quick up /path/to/your-config.conf"
echo ""
echo "  Or import the config via nmcli:"
echo "  sudo nmcli connection import type wireguard file /path/to/config.conf"
echo ""

read -rp "Do you have a GeminiVPN config file ready? [y/N]: " HAVE_CONF
if [[ "${HAVE_CONF,,}" == "y" ]]; then
  read -rp "Path to config file: " CONF_PATH
  if [[ -f "$CONF_PATH" ]]; then
    CONF_NAME=$(basename "$CONF_PATH" .conf)
    $SUDO cp "$CONF_PATH" "/etc/wireguard/${CONF_NAME}.conf"
    $SUDO chmod 600 "/etc/wireguard/${CONF_NAME}.conf"
    $SUDO wg-quick up "$CONF_NAME"
    ok "VPN connected! Test: curl ifconfig.io"
    $SUDO systemctl enable "wg-quick@${CONF_NAME}" 2>/dev/null && ok "Auto-start on boot enabled"
  else
    err "Config file not found: $CONF_PATH"
  fi
else
  echo ""
  ok "WireGuard is installed and ready."
  echo "  → Visit https://geminivpn.zapto.org to get your config file."
  echo "  → Then run: sudo wg-quick up /path/to/config.conf"
fi
echo ""
