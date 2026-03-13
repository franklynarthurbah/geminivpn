import re, subprocess, sys

def gen(n):
    return subprocess.check_output(['openssl','rand','-base64',str(n)]).decode().strip()

def gen_hex(n):
    return subprocess.check_output(['openssl','rand','-hex',str(n)]).decode().strip()

env_file = sys.argv[1] if len(sys.argv) > 1 else '/opt/geminivpn/.env'
with open(env_file) as f:
    c = f.read()

# Replace placeholders
for pat, gen_fn in [
    (r'^(JWT_ACCESS_SECRET)=.*(CHANGE_ME|placeholder|change_me|GENJWT).*$', lambda m: f'{m.group(1)}={gen(48)}'),
    (r'^(JWT_REFRESH_SECRET)=.*(CHANGE_ME|placeholder|change_me|GENJWT).*$', lambda m: f'{m.group(1)}={gen(48)}'),
    (r'^(DB_PASSWORD)=.*(CHANGE_ME|GENPASS|geminivpn_db_pass|change_me).*$', lambda m: f'{m.group(1)}={gen_hex(20)}'),
    (r'^(REDIS_PASSWORD)=.*(CHANGE_ME|GENREDIS|geminivpn_redis_pass|change_me).*$', lambda m: f'{m.group(1)}={gen_hex(16)}'),
]:
    c = re.sub(pat, gen_fn, c, flags=re.MULTILINE|re.IGNORECASE)

# Force-set critical vars
forced = {
    'WHATSAPP_SUPPORT_NUMBER': '+905368895622',
    'WIREGUARD_ENABLED': 'false',
    'ENABLE_SELF_HEALING': 'false',
    'NODE_ENV': 'production',
    'BCRYPT_ROUNDS': '12',
    'DEMO_DURATION_MINUTES': '60',
}
for k, v in forced.items():
    if re.search(rf'^{k}=', c, re.MULTILINE):
        c = re.sub(rf'^{k}=.*$', f'{k}={v}', c, flags=re.MULTILINE)
    else:
        c += f'\n{k}={v}'

# Sync DATABASE_URL with actual DB_PASSWORD
db_pass = re.search(r'^DB_PASSWORD=(.+)$', c, re.MULTILINE)
db_user = re.search(r'^DB_USER=(.+)$', c, re.MULTILINE)
db_name = re.search(r'^DB_NAME=(.+)$', c, re.MULTILINE)
if db_pass:
    dp = db_pass.group(1).strip()
    du = db_user.group(1).strip() if db_user else 'geminivpn'
    dn = db_name.group(1).strip() if db_name else 'geminivpn'
    new_url = f'postgresql://{du}:{dp}@postgres:5432/{dn}'
    if re.search(r'^DATABASE_URL=', c, re.MULTILINE):
        c = re.sub(r'^DATABASE_URL=.*$', f'DATABASE_URL={new_url}', c, flags=re.MULTILINE)
    else:
        c += f'\nDATABASE_URL={new_url}'

with open(env_file, 'w') as f:
    f.write(c)
print(f".env processed: {env_file}")
