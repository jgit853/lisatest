#!/usr/bin/env bash
set -Eeuo pipefail

CONF="/etc/xray/config.json"
PASS="6kBoVkFtLYW7wt0w9ZFnXLxJ"
IP="38.92.14.38"
SNI="www.cloudflare.com"
NAME="LisaHost-Trojan-TLS-443"

printf '[FORCE] set trojan password by JSON parse\n'
if [ ! -f "$CONF" ]; then
  printf '[FORCE] missing %s\n' "$CONF" >&2
  exit 1
fi

mkdir -p /root/xray-backup
cp -a "$CONF" "/root/xray-backup/config.force.$(date +%Y%m%d-%H%M%S).json"

python3 - <<'PY'
import json
from pathlib import Path
p = Path('/etc/xray/config.json')
new_pass = '6kBoVkFtLYW7wt0w9ZFnXLxJ'
data = json.loads(p.read_text())
changed = 0
for inbound in data.get('inbounds', []):
    proto = inbound.get('protocol') or inbound.get('type')
    settings = inbound.get('settings') or {}
    clients = settings.get('clients') or []
    if proto == 'trojan' or any('password' in c for c in clients if isinstance(c, dict)):
        for c in clients:
            if isinstance(c, dict) and 'password' in c:
                old = c.get('password')
                c['password'] = new_pass
                changed += 1
                print('changed_password_from=' + str(old))
if changed == 0:
    raise SystemExit('no trojan client password field found')
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
print('changed_count=' + str(changed))
PY

XRAY="/usr/local/bin/xray"
if [ ! -x "$XRAY" ]; then
  XRAY="$(command -v xray || true)"
fi
if [ -n "$XRAY" ]; then
  "$XRAY" run -test -config "$CONF"
fi

systemctl restart xray
sleep 1
systemctl is-active --quiet xray

printf '\n=== Xray status ===\n'
systemctl status xray --no-pager | sed -n '1,18p'
printf '\n=== Listen 443 ===\n'
ss -tlnp | grep ':443' || true
printf '\n=== Password check ===\n'
python3 - <<'PY'
import json
from pathlib import Path
data=json.loads(Path('/etc/xray/config.json').read_text())
for inbound in data.get('inbounds', []):
    for c in (inbound.get('settings') or {}).get('clients') or []:
        if isinstance(c, dict) and 'password' in c:
            print(c['password'])
PY
printf '\n=== Trojan link ===\n'
LINK="trojan://${PASS}@${IP}:443?security=tls&sni=${SNI}&allowInsecure=1&type=tcp#${NAME}"
printf '%s\n' "$LINK"
printf '%s\n' "$LINK" > /root/xray-trojan-force-link.txt
printf '\n[FORCE] done\n'
