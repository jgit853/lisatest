#!/usr/bin/env bash
set -Eeuo pipefail

CONF="/etc/xray/config.json"
PASS="6kBoVkFtLYW7wt0w9ZFnXLxJ"
IP="38.92.14.38"
SNI="www.cloudflare.com"
NAME="LisaHost-Trojan-TLS-443"
XRAY="/usr/local/bin/xray"

printf '[FORCE] set trojan password by JSON parser\n'

if [ ! -f "$CONF" ]; then
  printf '[FORCE] missing %s\n' "$CONF" >&2
  exit 1
fi

if [ ! -x "$XRAY" ]; then
  if command -v xray >/dev/null 2>&1; then
    XRAY="$(command -v xray)"
  else
    printf '[FORCE] missing xray binary\n' >&2
    exit 1
  fi
fi

mkdir -p /root/xray-backup
BACKUP="/root/xray-backup/config.force.$(date +%Y%m%d-%H%M%S).json"
cp -a "$CONF" "$BACKUP"
printf '[FORCE] backup=%s\n' "$BACKUP"

python3 - <<'PY'
import json
from pathlib import Path
p = Path('/etc/xray/config.json')
new_pass = '6kBoVkFtLYW7wt0w9ZFnXLxJ'
d = json.loads(p.read_text())
changed = 0
for inbound in d.get('inbounds', []):
    settings = inbound.get('settings') or {}
    for client in settings.get('clients') or []:
        if isinstance(client, dict) and 'password' in client:
            print('old_password=' + str(client.get('password')))
            client['password'] = new_pass
            changed += 1
if changed < 1:
    raise SystemExit('no trojan client password field found')
p.write_text(json.dumps(d, indent=2) + '\n')
print('changed=' + str(changed))
PY

if ! "$XRAY" run -test -config "$CONF"; then
  printf '[FORCE] xray test failed, rollback backup\n' >&2
  cp -a "$BACKUP" "$CONF"
  systemctl restart xray || true
  exit 1
fi

systemctl restart xray
sleep 1
systemctl is-active --quiet xray

printf '\n=== Xray status ===\n'
systemctl status xray --no-pager | sed -n '1,18p'
printf '\n=== Listen 443 ===\n'
ss -tlnp | grep ':443' || true
printf '\n=== BBR ===\n'
sysctl net.ipv4.tcp_congestion_control 2>/dev/null || true
printf '\n=== Trojan link ===\n'
LINK="trojan://${PASS}@${IP}:443?security=tls&sni=${SNI}&allowInsecure=1&type=tcp#${NAME}"
printf '%s\n' "$LINK"
printf '%s\n' "$LINK" > /root/xray-trojan-rollback-link.txt
printf '\n[FORCE] done\n'
