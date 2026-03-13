import sys
content = """#!/bin/sh
# GeminiVPN nginx pre-start — fixed version
set -e
DOMAIN="geminivpn.zapto.org"
LE_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
LE_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
SS_DIR="/etc/nginx/ssl"

if [ -f "$LE_CERT" ] && [ -f "$LE_KEY" ]; then
    echo "[nginx-entrypoint] LE cert found."
else
    echo "[nginx-entrypoint] Generating self-signed cert..."
    mkdir -p "$SS_DIR" "/etc/letsencrypt/live/${DOMAIN}"
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \\
        -keyout "${SS_DIR}/self-signed.key" \\
        -out    "${SS_DIR}/self-signed.crt" \\
        -subj "/C=US/ST=State/L=City/O=GeminiVPN/CN=${DOMAIN}" 2>/dev/null
    ln -sf "${SS_DIR}/self-signed.crt" "$LE_CERT"
    ln -sf "${SS_DIR}/self-signed.key" "$LE_KEY"
    echo "[nginx-entrypoint] Self-signed cert ready."
fi

mkdir -p /var/www/geminivpn /var/www/certbot

if [ ! -f "/var/www/geminivpn/index.html" ]; then
    printf '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>GeminiVPN</title><style>body{background:#04080F;color:#fff;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;flex-direction:column;text-align:center;margin:0}h1{color:#00EFFF;font-size:2rem;margin:1rem 0}</style></head><body><h1>GeminiVPN</h1><p style="color:rgba(255,255,255,.6)">Initializing...</p></body></html>' > /var/www/geminivpn/index.html
fi

echo "[nginx-entrypoint] Testing nginx config..."
nginx -t 2>&1 || { echo "FATAL: nginx -t failed"; exit 1; }
echo "[nginx-entrypoint] Starting nginx..."
exec /docker-entrypoint.sh nginx -g "daemon off;"
"""
dest = sys.argv[1] if len(sys.argv) > 1 else '/tmp/pre-start.sh'
with open(dest, 'w') as f:
    f.write(content)
print("pre-start.sh written to", dest)
