#!/usr/bin/env bash
set -Eeuo pipefail

OLD="YrAnIlQjSvtBGuryYhhtKfkfOLRk"
NEW="6kBoVkFtLYW7wt0w9ZFnXLxJ"
CONF="/etc/xray/config.json"
IP="38.92.14.38"
SNI="www.cloudflare.com"
NAME="LisaHost-Trojan-TLS-443"

printf '[RB] start rollback trojan password\n'
if [ ! -f "$CONF" ]; then
  printf '[RB] missing %s\n' "$CONF" >&2
  exit 1
fi

mkdir -p /root/xray-backup
cp -a "$CONF" "/root/xray-backup/config.rollback.$(date +%Y%m%d-%H%M%S).json"

python3 - <<'PY'
from pathlib import Path
p = Path('/etc/xray/config.json')
old = 'YrAnIlQjSvtBGuryYhhtKfkfOLRk'
new = '6kBoVkFtLYW7wt0w9ZFnXLxJ'
s = p.read_text()
if old not in s and new not in s:
    raise SystemExit('neither old nor rollback password found in config')
s = s.replace(old, new)
p.write_text(s)
PY

if command -v xray >/dev/null 2>&1; then
  xray run -test -config "$CONF"
elif [ -x /usr/local/bin/xray ]; then
  /usr/local/bin/xray run -test -config "$CONF"
fi

systemctl restart xray
sleep 1
systemctl is-active --quiet xray

printf '\n=== Xray status ===\n'
systemctl status xray --no-pager | sed -n '1,18p'
printf '\n=== Listen 443 ===\n'
ss -tlnp | grep ':443' || true
printf '\n=== Password check ===\n'
grep -o 'YrAnIlQjSvtBGuryYhhtKfkfOLRk\|6kBoVkFtLYW7wt0w9ZFnXLxJ' "$CONF" || true
printf '\n=== Trojan link ===\n'
LINK="trojan://${NEW}@${IP}:443?security=tls&sni=${SNI}&allowInsecure=1&type=tcp#${NAME}"
printf '%s\n' "$LINK"
printf '%s\n' "$LINK" > /root/xray-trojan-rollback-link.txt
printf '\n[RB] done\n'
