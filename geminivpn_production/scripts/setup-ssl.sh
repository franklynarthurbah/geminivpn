#!/bin/bash
# =============================================================================
# GeminiVPN SSL Certificate Setup Script
# Configures SSL certificates using Let's Encrypt or custom certificates
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DOMAIN=""
EMAIL=""
USE_LETSENCRYPT=true
CUSTOM_CERT_PATH=""
CUSTOM_KEY_PATH=""
STAGING=false

# =============================================================================
# Helper Functions
# =============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   GeminiVPN SSL Setup                        ║"
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
    -d, --domain         Domain name (required)
    -e, --email          Email for Let's Encrypt notifications (required for LE)
    --custom-cert        Path to custom certificate file
    --custom-key         Path to custom private key file
    --staging            Use Let's Encrypt staging environment
    --help               Show this help message

Examples:
    # Let's Encrypt (production)
    $0 --domain geminivpn.com --email admin@geminivpn.com
    
    # Let's Encrypt (staging)
    $0 --domain geminivpn.com --email admin@geminivpn.com --staging
    
    # Custom certificates
    $0 --domain geminivpn.com --custom-cert /path/to/cert.pem --custom-key /path/to/key.pem
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        --custom-cert)
            CUSTOM_CERT_PATH="$2"
            USE_LETSENCRYPT=false
            shift 2
            ;;
        --custom-key)
            CUSTOM_KEY_PATH="$2"
            USE_LETSENCRYPT=false
            shift 2
            ;;
        --staging)
            STAGING=true
            shift
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

if [[ -z "$DOMAIN" ]]; then
    print_error "Domain is required"
    usage
    exit 1
fi

if [[ "$USE_LETSENCRYPT" == true && -z "$EMAIL" ]]; then
    print_error "Email is required for Let's Encrypt"
    usage
    exit 1
fi

if [[ "$USE_LETSENCRYPT" == false ]]; then
    if [[ -z "$CUSTOM_CERT_PATH" || -z "$CUSTOM_KEY_PATH" ]]; then
        print_error "Both --custom-cert and --custom-key are required for custom certificates"
        usage
        exit 1
    fi
    
    if [[ ! -f "$CUSTOM_CERT_PATH" ]]; then
        print_error "Certificate file not found: $CUSTOM_CERT_PATH"
        exit 1
    fi
    
    if [[ ! -f "$CUSTOM_KEY_PATH" ]]; then
        print_error "Private key file not found: $CUSTOM_KEY_PATH"
        exit 1
    fi
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

print_info "Domain: $DOMAIN"
print_info "Using Let's Encrypt: $USE_LETSENCRYPT"

# =============================================================================
# Install Certbot (for Let's Encrypt)
# =============================================================================

install_certbot() {
    print_info "Installing Certbot..."
    
    if command -v certbot &> /dev/null; then
        print_success "Certbot already installed"
        return
    fi
    
    # Detect OS and install accordingly
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        
        case $ID in
            ubuntu|debian)
                apt-get update
                apt-get install -y certbot python3-certbot-nginx
                ;;
            centos|rhel|fedora)
                if command -v dnf &> /dev/null; then
                    dnf install -y certbot python3-certbot-nginx
                else
                    yum install -y certbot python3-certbot-nginx
                fi
                ;;
            alpine)
                apk add certbot certbot-nginx
                ;;
            *)
                print_error "Unsupported OS: $ID"
                exit 1
                ;;
        esac
    fi
    
    print_success "Certbot installed"
}

# =============================================================================
# Let's Encrypt Certificate
# =============================================================================

setup_letsencrypt() {
    print_info "Setting up Let's Encrypt certificate..."
    
    install_certbot
    
    # Create certificate directory
    mkdir -p /etc/letsencrypt/live/$DOMAIN
    
    # Prepare certbot arguments
    local certbot_args=""
    
    if [[ "$STAGING" == true ]]; then
        certbot_args="--staging"
        print_warning "Using Let's Encrypt staging environment"
    fi
    
    # Obtain certificate
    certbot certonly \
        --standalone \
        --agree-tos \
        --non-interactive \
        --email "$EMAIL" \
        -d "$DOMAIN" \
        $certbot_args
    
    if [[ $? -eq 0 ]]; then
        print_success "Certificate obtained successfully"
        
        # Set up auto-renewal
        setup_renewal
    else
        print_error "Failed to obtain certificate"
        exit 1
    fi
}

# =============================================================================
# Custom Certificate
# =============================================================================

setup_custom_cert() {
    print_info "Setting up custom certificate..."
    
    # Create certificate directory
    mkdir -p /etc/geminivpn/ssl
    
    # Copy certificates
    cp "$CUSTOM_CERT_PATH" /etc/geminivpn/ssl/cert.pem
    cp "$CUSTOM_KEY_PATH" /etc/geminivpn/ssl/key.pem
    
    # Set permissions
    chmod 644 /etc/geminivpn/ssl/cert.pem
    chmod 600 /etc/geminivpn/ssl/key.pem
    
    print_success "Custom certificate installed"
}

# =============================================================================
# Auto-Renewal Setup
# =============================================================================

setup_renewal() {
    print_info "Setting up certificate auto-renewal..."
    
    # Create renewal hook script
    cat > /etc/letsencrypt/renewal-hooks/deploy/geminivpn-reload.sh << 'EOF'
#!/bin/bash
# Reload services after certificate renewal

echo "Certificate renewed, reloading services..."

# Reload nginx if running
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
    echo "Nginx reloaded"
fi

# Reload backend containers if using Docker
if command -v docker-compose &> /dev/null; then
    cd /opt/geminivpn && docker-compose exec -T backend kill -HUP 1
    echo "Backend containers reloaded"
fi

echo "Services reloaded successfully"
EOF
    
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/geminivpn-reload.sh
    
    # Add cron job for renewal
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/geminivpn-reload.sh") | crontab -
        print_success "Auto-renewal cron job added"
    else
        print_warning "Auto-renewal cron job already exists"
    fi
    
    # Test renewal
    print_info "Testing certificate renewal..."
    certbot renew --dry-run
    
    if [[ $? -eq 0 ]]; then
        print_success "Renewal test passed"
    else
        print_warning "Renewal test failed, please check configuration"
    fi
}

# =============================================================================
# Nginx Configuration
# =============================================================================

setup_nginx() {
    print_info "Setting up Nginx configuration..."
    
    # Create nginx config directory
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    
    # Determine certificate paths
    if [[ "$USE_LETSENCRYPT" == true ]]; then
        CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    else
        CERT_PATH="/etc/geminivpn/ssl/cert.pem"
        KEY_PATH="/etc/geminivpn/ssl/key.pem"
    fi
    
    # Create nginx configuration
    cat > /etc/nginx/sites-available/geminivpn << EOF
# GeminiVPN Nginx Configuration

upstream backend {
    server 127.0.0.1:5000;
    keepalive 32;
}

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;
    
    # SSL Certificates
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    
    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always;
    
    # Logging
    access_log /var/log/nginx/geminivpn-access.log;
    error_log /var/log/nginx/geminivpn-error.log;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;
    
    # API routes
    location /api/ {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
    
    # WebSocket support
    location /ws/ {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }
    
    # Static files (if serving frontend from same server)
    location / {
        root /var/www/geminivpn/frontend;
        try_files \$uri \$uri/ /index.html;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://backend/health;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        access_log off;
    }
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/geminivpn /etc/nginx/sites-enabled/geminivpn
    
    # Test nginx configuration
    nginx -t
    
    if [[ $? -eq 0 ]]; then
        print_success "Nginx configuration valid"
        
        # Reload nginx
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx
            print_success "Nginx reloaded"
        else
            systemctl start nginx
            systemctl enable nginx
            print_success "Nginx started"
        fi
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

if [[ "$USE_LETSENCRYPT" == true ]]; then
    setup_letsencrypt
else
    setup_custom_cert
fi

setup_nginx

# =============================================================================
# Summary
# =============================================================================

echo ""
print_success "SSL setup completed!"
echo ""
echo -e "${BLUE}Certificate Information:${NC}"

if [[ "$USE_LETSENCRYPT" == true ]]; then
    echo "  Type: Let's Encrypt"
    echo "  Certificate: /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    echo "  Private Key: /etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo "  Auto-renewal: Enabled"
else
    echo "  Type: Custom"
    echo "  Certificate: /etc/geminivpn/ssl/cert.pem"
    echo "  Private Key: /etc/geminivpn/ssl/key.pem"
fi

echo ""
echo -e "${BLUE}Nginx Configuration:${NC}"
echo "  Config: /etc/nginx/sites-available/geminivpn"
echo "  Access Log: /var/log/nginx/geminivpn-access.log"
echo "  Error Log: /var/log/nginx/geminivpn-error.log"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Verify HTTPS is working: curl -I https://$DOMAIN"
echo "  2. Check certificate: openssl s_client -connect $DOMAIN:443"
echo "  3. Deploy the application with docker-compose"
echo ""
