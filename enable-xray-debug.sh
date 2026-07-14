set -Eeuo pipefail
CONFIG=/etc/xray/config.json
mkdir -p /var/log/xray
cp "$CONFIG" "/etc/xray/config.json.debugbak.$(date +%s)"
python3 - <<'PY'
import json
p='/etc/xray/config.json'
with open(p) as f:
    c=json.load(f)
c['log']={
  'access':'/var/log/xray/access.log',
  'error':'/var/log/xray/error.log',
  'loglevel':'debug'
}
with open(p,'w') as f:
    json.dump(c,f,indent=2)
PY
: >/var/log/xray/access.log
: >/var/log/xray/error.log
systemctl restart xray
sleep 2
echo '=== STATUS ==='
systemctl --no-pager --full status xray || true
echo '=== LISTEN ==='
ss -tlnp | grep ':443' || true
echo 'Debug enabled. Now test once from v2rayN, then run:'
echo 'journalctl -u xray -n 120 --no-pager'
echo 'cat /var/log/xray/access.log'
echo 'cat /var/log/xray/error.log'
