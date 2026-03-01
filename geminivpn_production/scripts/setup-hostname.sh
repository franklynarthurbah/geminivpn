#!/bin/bash
# =============================================================================
# GeminiVPN Hostname Setup Script
# Configures server hostname and DNS for VPN deployment
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
HOSTNAME=""
DOMAIN="geminivpn.com"
IP_ADDRESS=""

# =============================================================================
# Helper Functions
# =============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 GeminiVPN Hostname Setup                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h, --hostname     Server hostname (e.g., us-ny-server-01)
    -d, --domain       Domain name (default: geminivpn.com)
    -i, --ip           Public IP address (auto-detected if not provided)
    --help             Show this help message

Examples:
    $0 --hostname us-ny-server-01
    $0 --hostname eu-de-server-01 --domain myvpn.com --ip 1.2.3.4
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -i|--ip)
            IP_ADDRESS="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# =============================================================================
# Validation
# =============================================================================

print_banner

if [[ -z "$HOSTNAME" ]]; then
    print_error "Hostname is required"
    usage
    exit 1
fi

# Auto-detect IP if not provided
if [[ -z "$IP_ADDRESS" ]]; then
    print_info "Auto-detecting public IP address..."
    IP_ADDRESS=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
    
    if [[ -z "$IP_ADDRESS" ]]; then
        print_error "Could not auto-detect IP address. Please provide it with --ip"
        exit 1
    fi
    
    print_success "Detected IP: $IP_ADDRESS"
fi

FULL_HOSTNAME="${HOSTNAME}.${DOMAIN}"

print_info "Configuring hostname: $FULL_HOSTNAME"
print_info "IP Address: $IP_ADDRESS"

# =============================================================================
# System Configuration
# =============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Set system hostname
print_info "Setting system hostname..."
hostnamectl set-hostname "$FULL_HOSTNAME"
print_success "Hostname set to: $(hostname)"

# Update /etc/hosts
print_info "Updating /etc/hosts..."
if ! grep -q "$FULL_HOSTNAME" /etc/hosts; then
    echo "$IP_ADDRESS $FULL_HOSTNAME $HOSTNAME" >> /etc/hosts
    print_success "Added to /etc/hosts"
else
    print_warning "Entry already exists in /etc/hosts"
fi

# Update /etc/hostname
echo "$FULL_HOSTNAME" > /etc/hostname
print_success "Updated /etc/hostname"

# =============================================================================
# DNS Configuration Check
# =============================================================================

print_info "Checking DNS resolution..."
if command -v dig &> /dev/null; then
    RESOLVED_IP=$(dig +short "$FULL_HOSTNAME" || echo "")
    if [[ "$RESOLVED_IP" == "$IP_ADDRESS" ]]; then
        print_success "DNS correctly resolves to $IP_ADDRESS"
    else
        print_warning "DNS does not resolve correctly"
        print_info "Please create an A record: $FULL_HOSTNAME -> $IP_ADDRESS"
    fi
else
    print_warning "dig not installed, skipping DNS check"
fi

# =============================================================================
# Firewall Configuration
# =============================================================================

print_info "Configuring firewall..."

# Check if UFW is installed
if command -v ufw &> /dev/null; then
    print_info "Configuring UFW..."
    
    # Allow SSH
    ufw allow 22/tcp
    
    # Allow HTTP/HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow WireGuard
    ufw allow 51820/udp
    
    # Allow backend API
    ufw allow 5000/tcp
    
    print_success "UFW rules configured"
    
    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        print_info "Enabling UFW..."
        echo "y" | ufw enable
        print_success "UFW enabled"
    fi
    
    ufw status verbose
fi

# Check if iptables is available
if command -v iptables &> /dev/null; then
    print_info "Configuring iptables..."
    
    # Allow established connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    
    # Allow SSH
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # Allow HTTP/HTTPS
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    
    # Allow WireGuard
    iptables -A INPUT -p udp --dport 51820 -j ACCEPT
    
    # Allow backend API
    iptables -A INPUT -p tcp --dport 5000 -j ACCEPT
    
    # Default drop
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    print_success "iptables rules configured"
fi

# =============================================================================
# Kernel Parameters
# =============================================================================

print_info "Configuring kernel parameters..."

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

# Apply sysctl settings
sysctl -p

print_success "Kernel parameters configured"

# =============================================================================
# Summary
# =============================================================================

echo ""
print_success "Hostname setup completed!"
echo ""
echo -e "${BLUE}Configuration Summary:${NC}"
echo "  Hostname: $FULL_HOSTNAME"
echo "  IP Address: $IP_ADDRESS"
echo "  Domain: $DOMAIN"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Create DNS A record: $FULL_HOSTNAME -> $IP_ADDRESS"
echo "  2. Run setup-ssl.sh to configure SSL certificates"
echo "  3. Deploy the application with docker-compose"
echo ""
