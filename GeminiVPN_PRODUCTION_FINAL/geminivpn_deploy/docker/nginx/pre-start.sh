#!/bin/sh
# =============================================================================
# GeminiVPN nginx pre-start entrypoint
# Ensures nginx ALWAYS starts, even before Let's Encrypt cert exists.
#
# On first deploy, LE cert doesn't exist yet → nginx would crash → visitors
# see nothing. This script generates a self-signed cert as a fallback so nginx
# starts immediately. Once you run setup-ssl.sh, nginx auto-reloads with the
# real cert.
# =============================================================================
set -e

DOMAIN="geminivpn.zapto.org"
LE_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
LE_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
SS_DIR="/etc/nginx/ssl"
SS_CERT="${SS_DIR}/self-signed.crt"
SS_KEY="${SS_DIR}/self-signed.key"

echo "[nginx-entrypoint] Checking SSL certificate..."

if [ -f "$LE_CERT" ] && [ -f "$LE_KEY" ]; then
    echo "[nginx-entrypoint] Let's Encrypt cert found — nginx will use real cert."
else
    echo "[nginx-entrypoint] LE cert not found at: $LE_CERT"
    echo "[nginx-entrypoint] Generating self-signed fallback cert..."

    mkdir -p "$SS_DIR"
    mkdir -p "/etc/letsencrypt/live/${DOMAIN}"

    # Generate self-signed cert (valid 10 years — only used until LE cert is obtained)
    openssl req -x509 -nodes -days 3650 \
        -newkey rsa:2048 \
        -keyout "$SS_KEY" \
        -out   "$SS_CERT" \
        -subj  "/C=US/ST=State/L=City/O=GeminiVPN/CN=${DOMAIN}" \
        -addext "subjectAltName=DNS:${DOMAIN}" \
        2>/dev/null

    # Symlink into the LE path so nginx.conf picks them up unchanged
    ln -sf "$SS_CERT" "$LE_CERT"
    ln -sf "$SS_KEY"  "$LE_KEY"

    echo "[nginx-entrypoint] Self-signed cert ready. Visitors will see a browser warning"
    echo "[nginx-entrypoint] until you run: sudo bash scripts/setup-ssl.sh"
fi

# Ensure required directories exist (nginx won't start if /var/www/geminivpn is empty)
mkdir -p /var/www/geminivpn
mkdir -p /var/www/certbot

# If frontend hasn't been deployed yet, serve a friendly maintenance page
if [ ! -f "/var/www/geminivpn/index.html" ]; then
    echo "[nginx-entrypoint] Frontend not deployed — serving maintenance page"
    cat > /var/www/geminivpn/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>GeminiVPN — Setting Up</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{min-height:100vh;background:#04080F;color:#fff;font-family:system-ui,sans-serif;
       display:flex;align-items:center;justify-content:center;flex-direction:column;text-align:center;padding:40px}
  .logo{font-size:56px;margin-bottom:20px}
  h1{font-size:28px;font-weight:700;letter-spacing:2px;margin-bottom:10px;color:#00EFFF}
  p{color:rgba(255,255,255,.6);font-size:15px;max-width:400px;line-height:1.7}
  .pulse{display:inline-block;width:10px;height:10px;border-radius:50%;
         background:#00EFFF;margin-bottom:24px;animation:pulse 1.5s infinite}
  @keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.4;transform:scale(.8)}}
  small{margin-top:30px;font-size:11px;color:rgba(255,255,255,.25);font-family:monospace}
</style>
</head>
<body>
  <div class="logo">🛡</div>
  <div class="pulse"></div>
  <h1>GeminiVPN</h1>
  <p>Server is initializing. Run the frontend build step to deploy the site.</p>
  <small>cd frontend && npm install --legacy-peer-deps && npm run build && cp -r dist/. /var/www/geminivpn/</small>
</body>
</html>
HTMLEOF
fi

echo "[nginx-entrypoint] Starting nginx..."

# Hand off to the real nginx entrypoint (processes nginx.conf templates, then starts nginx)
exec /docker-entrypoint.sh nginx -g "daemon off;"
