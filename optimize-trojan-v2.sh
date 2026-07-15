#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG=/etc/xray/config.json
XRAY=/usr/local/bin/xray
BACKUP_DIR=/root/xray-backup
RESULT=/root/xray-trojan-opt-result.txt
SNI=www.cloudflare.com
NODE_NAME=LisaHost-Trojan-TLS-443
IP_FALLBACK=38.92.14.38

say() { printf '\n[OPT] %s\n' "$*"; }
fail() { printf '\n[FAIL] %s\n' "$*" >&2; exit 1; }

rollback() {
  ts=$(cat /root/xray-backup/latest-ts 2>/dev/null || true)
  if [ -n "$ts" ] && [ -f "$BACKUP_DIR/config.json.$ts" ]; then
    cp -a "$BACKUP_DIR/config.json.$ts" "$CONFIG"
    systemctl restart xray || true
    printf '\n[ROLLBACK] restored %s\n' "$BACKUP_DIR/config.json.$ts" >&2
  fi
}
trap 'rollback' ERR

say 'v2 started'
[ "$(id -u)" = "0" ] || fail 'run as root'
[ -x "$XRAY" ] || fail "$XRAY not found or not executable"
[ -f "$CONFIG" ] || fail "$CONFIG not found"
command -v python3 >/dev/null 2>&1 || fail 'python3 not found'
command -v ss >/dev/null 2>&1 || fail 'ss not found'
command -v openssl >/dev/null 2>&1 || fail 'openssl not found'

say 'validate json'
python3 -m json.tool "$CONFIG" >/dev/null || fail 'xray config is not valid JSON'

say 'check 443 owner'
ss -tlnp | grep ':443' || fail 'port 443 is not listening'
ss -tlnp | grep ':443' | grep -qi 'xray' || fail 'port 443 is not owned by xray'

say 'backup'
mkdir -p "$BACKUP_DIR"
ts=$(date +%F-%H%M%S)
cp -a "$CONFIG" "$BACKUP_DIR/config.json.$ts"
[ -f /etc/systemd/system/xray.service ] && cp -a /etc/systemd/system/xray.service "$BACKUP_DIR/xray.service.$ts" || true
[ -d /etc/systemd/system/xray.service.d ] && cp -a /etc/systemd/system/xray.service.d "$BACKUP_DIR/xray.service.d.$ts" || true
printf '%s' "$ts" >/root/xray-backup/latest-ts

say 'enable bbr'
cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null || true

say 'systemd override'
mkdir -p /etc/systemd/system/xray.service.d
cat >/etc/systemd/system/xray.service.d/override.conf <<'EOF'
[Service]
Restart=always
RestartSec=3
LimitNOFILE=1048576
EOF
systemctl daemon-reload

say 'rotate password and reduce logs'
new_pass=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 28)
[ -n "$new_pass" ] || fail 'failed to generate password'
export NEW_TROJAN_PASS="$new_pass"
python3 - <<'PY'
import json, os
p = os.environ['NEW_TROJAN_PASS']
path = '/etc/xray/config.json'
with open(path, 'r', encoding='utf-8') as f:
    cfg = json.load(f)
cfg['log'] = cfg.get('log') or {}
cfg['log']['loglevel'] = 'warning'
cfg['log'].pop('access', None)
changed = False
for inbound in cfg.get('inbounds', []):
    if inbound.get('protocol') == 'trojan':
        clients = inbound.get('settings', {}).get('clients', [])
        if clients:
            clients[0]['password'] = p
            changed = True
if not changed:
    raise SystemExit('no trojan client found in config')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
chmod 600 "$CONFIG"
printf '%s' "$new_pass" >/root/xray-trojan-new-password.txt

say 'test config'
if ! "$XRAY" run -test -config "$CONFIG"; then
  fail 'xray config test failed'
fi

say 'restart xray'
systemctl restart xray
sleep 2
systemctl is-active --quiet xray || fail 'xray is not active after restart'
ss -tlnp | grep ':443' | grep -qi 'xray' || fail 'xray is not listening on 443 after restart'
trap - ERR

say 'write result'
ip=$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)
[ -n "$ip" ] || ip="$IP_FALLBACK"
pass=$(cat /root/xray-trojan-new-password.txt)
link="trojan://${pass}@${ip}:443?security=tls&sni=${SNI}&allowInsecure=1&type=tcp#${NODE_NAME}"
bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
status=$(systemctl is-active xray 2>/dev/null || true)
listen=$(ss -tlnp | grep ':443' || true)
override=$(cat /etc/systemd/system/xray.service.d/override.conf 2>/dev/null || true)
cat >"$RESULT" <<EOF
NEW_TROJAN_LINK=$link
NEW_PASSWORD=$pass
IP=$ip
PORT=443
SNI=$SNI
XRAY_STATUS=$status
BBR=$bbr
BACKUP_DIR=$BACKUP_DIR
BACKUP_TS=$ts
UFW_CHANGED=no

LISTEN_443:
$listen

SYSTEMD_OVERRIDE:
$override

CLIENT_NOTE:
Import NEW_TROJAN_LINK into Shadowrocket or v2rayN. For Mihomo, update server, password, sni, port 443, skip-cert-verify true.

LIMITATION:
This is still IP-direct Trojan with allowInsecure=1. Stealth is medium, not high. High stealth requires domain plus valid certificate and removing allowInsecure.
EOF
cat "$RESULT"

say 'upload result'
upload=$(curl -fsS -F "file=@${RESULT}" https://tmpfiles.org/api/v1/upload 2>/dev/null || true)
if [ -n "$upload" ]; then
  printf '\nUPLOAD_RESULT:\n%s\n' "$upload"
else
  printf '\nUPLOAD_RESULT: failed; copy NEW_TROJAN_LINK above\n'
fi

say 'done'
