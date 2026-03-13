#!/bin/sh
# GeminiVPN nginx pre-start — ensures nginx starts even without LE cert
# Fixed: removed -addext (requires OpenSSL 1.1.1+), using -subj only
set -e

DOMAIN="geminivpn.zapto.org"
LE_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
LE_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
SS_DIR="/etc/nginx/ssl"

echo "[nginx-entrypoint] Checking SSL certificate..."

if [ -f "$LE_CERT" ] && [ -f "$LE_KEY" ]; then
    echo "[nginx-entrypoint] Let's Encrypt cert found."
else
    echo "[nginx-entrypoint] Generating self-signed fallback cert..."
    mkdir -p "$SS_DIR"
    mkdir -p "/etc/letsencrypt/live/${DOMAIN}"

    # Generate self-signed cert without -addext (compatible with all OpenSSL versions)
    openssl req -x509 -nodes -days 3650 \
        -newkey rsa:2048 \
        -keyout "${SS_DIR}/self-signed.key" \
        -out    "${SS_DIR}/self-signed.crt" \
        -subj   "/C=US/ST=State/L=City/O=GeminiVPN/CN=${DOMAIN}" \
        2>/dev/null || {
            echo "[nginx-entrypoint] ERROR: openssl failed"
            exit 1
        }

    ln -sf "${SS_DIR}/self-signed.crt" "$LE_CERT"
    ln -sf "${SS_DIR}/self-signed.key" "$LE_KEY"
    echo "[nginx-entrypoint] Self-signed cert ready."
fi

mkdir -p /var/www/geminivpn /var/www/certbot

# Deploy branded loading screen — only if real SPA not yet present.
# Shows animated logo + spinner while backend starts. Frontend build overwrites this.
if [ ! -f "/var/www/geminivpn/index.html" ] || \
   grep -q "Initializing\.\.\." /var/www/geminivpn/index.html 2>/dev/null; then
    cat > /var/www/geminivpn/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>GeminiVPN — Loading</title>
  <link rel="icon" type="image/png" href="/geminivpn-logo.png" />
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    html,body{height:100%;background:#070A12;color:#fff;font-family:system-ui,-apple-system,sans-serif;overflow:hidden}
    body{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:24px}
    .logo-wrap{position:relative;width:96px;height:96px}
    .logo-wrap img{width:96px;height:96px;object-fit:contain;border-radius:16px}
    .logo-wrap::after{content:'';position:absolute;inset:-6px;border-radius:22px;
      border:2px solid transparent;
      background:linear-gradient(#070A12,#070A12) padding-box,
                 linear-gradient(90deg,#00F0FF,#7B61FF,#00F0FF) border-box;
      animation:spin 2s linear infinite}
    @keyframes spin{to{transform:rotate(360deg)}}
    .brand{font-size:1.5rem;font-weight:700;letter-spacing:.18em}
    .brand span{color:#00F0FF}
    .tagline{font-size:.75rem;letter-spacing:.2em;color:rgba(255,255,255,.4);text-transform:uppercase}
    .dots{display:flex;gap:6px;margin-top:8px}
    .dots span{width:6px;height:6px;border-radius:50%;background:#00F0FF;animation:blink 1.4s ease-in-out infinite}
    .dots span:nth-child(2){animation-delay:.2s}
    .dots span:nth-child(3){animation-delay:.4s}
    @keyframes blink{0%,80%,100%{opacity:.2}40%{opacity:1}}
  </style>
</head>
<body>
  <div class="logo-wrap">
    <img src="/geminivpn-logo.png" alt="GeminiVPN" onerror="this.style.display='none'" />
  </div>
  <div class="brand">GEMINI<span>VPN</span></div>
  <div class="tagline">Browse at Lightspeed</div>
  <div class="dots"><span></span><span></span><span></span></div>
</body>
</html>
HTML
fi

echo "[nginx-entrypoint] Starting nginx..."

# Ensure logo is reachable — copy from mounted host volume if not already present.
# Covers the window between nginx starting and the frontend build being deployed.
if [ ! -f "/var/www/geminivpn/geminivpn-logo.png" ]; then
    # Try to find logo in common locations
    for LOGO_SRC in \
        "/opt/geminivpn/frontend/public/geminivpn-logo.png" \
        "/var/www/geminivpn-src/public/geminivpn-logo.png"; do
        if [ -f "$LOGO_SRC" ]; then
            cp "$LOGO_SRC" "/var/www/geminivpn/geminivpn-logo.png" 2>/dev/null && \
                echo "[nginx-entrypoint] Logo copied from ${LOGO_SRC}" || true
            break
        fi
    done
fi

exec /docker-entrypoint.sh nginx -g "daemon off;"
