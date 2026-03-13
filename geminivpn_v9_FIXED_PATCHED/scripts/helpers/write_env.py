import sys, subprocess

def gen(n): return subprocess.check_output(['openssl','rand','-base64',str(n)]).decode().strip()
def hex(n): return subprocess.check_output(['openssl','rand','-hex',str(n)]).decode().strip()

dest = sys.argv[1] if len(sys.argv) > 1 else '/opt/geminivpn/.env'
content = f"""NODE_ENV=production
PORT=5000
HOST=0.0.0.0
DB_USER=geminivpn
DB_PASSWORD={hex(20)}
DB_NAME=geminivpn
DATABASE_URL=postgresql://geminivpn:{hex(20)}@postgres:5432/geminivpn
REDIS_PASSWORD={hex(16)}
REDIS_URL=redis://:{hex(16)}@redis:6379
JWT_ACCESS_SECRET={gen(48)}
JWT_REFRESH_SECRET={gen(48)}
JWT_ACCESS_EXPIRY=15m
JWT_REFRESH_EXPIRY=7d
STRIPE_SECRET_KEY=sk_placeholder
STRIPE_PUBLISHABLE_KEY=pk_placeholder
STRIPE_WEBHOOK_SECRET=whsec_placeholder
STRIPE_MONTHLY_PRICE_ID=price_placeholder
STRIPE_YEARLY_PRICE_ID=price_placeholder
STRIPE_TWO_YEAR_PRICE_ID=price_placeholder
SMTP_HOST=smtp.placeholder.com
SMTP_PORT=587
SMTP_USER=noreply@example.com
SMTP_PASS=placeholder
WIREGUARD_ENABLED=false
WIREGUARD_SERVER_PRIVATE_KEY=placeholder
WIREGUARD_SUBNET=10.8.0.0/24
WIREGUARD_PORT=51820
SERVER_PUBLIC_IP=167.172.96.225
FRONTEND_URL=https://geminivpn.zapto.org
WHATSAPP_SUPPORT_NUMBER=+905368895622
ENABLE_SELF_HEALING=false
DOWNLOADS_DIR=/app/downloads
IOS_APP_STORE_URL=https://apps.apple.com/app/geminivpn
BCRYPT_ROUNDS=12
TRIAL_DURATION_DAYS=3
DEMO_DURATION_MINUTES=60
"""
with open(dest, 'w') as f:
    f.write(content)
print(f".env written to {dest}")
