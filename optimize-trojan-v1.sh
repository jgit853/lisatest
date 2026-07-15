#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG=/etc/xray/config.json
XRAY=/usr/local/bin/xray
BACKUP_DIR=/root/xray-backup
RESULT=/root/xray-trojan-opt-result.txt
SNI=www.cloudflare.com
NODE_NAME=LisaHost-Trojan-TLS-443
IP_FALLBACK=38.92.14.38

say() { printf '[OPT] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" = "0" ] || fail 'run as root'
}

precheck() {
  say 'precheck'
  [ -x "$XRAY" ] || fail "$XRAY not found or not executable"
  [ -f "$CONFIG" ] || fail "$CONFIG not found"
  command -v jq >/dev/null 2>&1 || apt-get update && apt-get install -y jq curl openssl iproute2 ca-certificates >/dev/null
  jq empty "$CONFIG" || fail 'xray config is not valid JSON'
  if ! ss -tlnp | grep -q ':443'; then
    fail 'port 443 is not listening; stop to avoid blind changes'
  fi
  if ! ss -tlnp | grep ':443' | grep -qi 'xray'; then
    ss -tlnp | grep ':443' || true
    fail 'port 443 is not owned by xray; stop to avoid blind changes'
  fi
}

backup() {
  say 'backup config and systemd files'
  mkdir -p "$BACKUP_DIR"
  ts=$(date +%F-%H%M%S)
  cp -a "$CONFIG" "$BACKUP_DIR/config.json.$ts"
  [ -f /etc/systemd/system/xray.service ] && cp -a /etc/systemd/system/xray.service "$BACKUP_DIR/xray.service.$ts" || true
  [ -d /etc/systemd/system/xray.service.d ] && cp -a /etc/systemd/system/xray.service.d "$BACKUP_DIR/xray.service.d.$ts" || true
  printf '%s' "$ts" >/root/xray-backup/latest-ts
}

rollback() {
  ts=$(cat /root/xray-backup/latest-ts 2>/dev/null || true)
  if [ -n "$ts" ] && [ -f "$BACKUP_DIR/config.json.$ts" ]; then
    cp -a "$BACKUP_DIR/config.json.$ts" "$CONFIG"
    systemctl restart xray || true
    printf '[ROLLBACK] restored %s\n' "$BACKUP_DIR/config.json.$ts" >&2
  fi
}
trap 'rollback' ERR

enable_bbr() {
  say 'enable bbr'
  cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null || true
}

harden_systemd() {
  say 'harden systemd restart policy'
  mkdir -p /etc/systemd/system/xray.service.d
  cat >/etc/systemd/system/xray.service.d/override.conf <<'EOF'
[Service]
Restart=always
RestartSec=3
LimitNOFILE=1048576
EOF
  systemctl daemon-reload
}

rotate_and_reduce_logs() {
  say 'rotate trojan password and reduce logs'
  new_pass=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 28)
  [ -n "$new_pass" ] || fail 'failed to generate password'
  tmp=$(mktemp)
  jq --arg p "$new_pass" '
    .log = ((.log // {}) + {"loglevel":"warning"})
    | del(.log.access)
    | (.inbounds[] | select(.protocol == "trojan") | .settings.clients[0].password) = $p
  ' "$CONFIG" >"$tmp"
  jq empty "$tmp"
  cp -a "$tmp" "$CONFIG"
  rm -f "$tmp"
  chmod 600 "$CONFIG"
  printf '%s' "$new_pass" >/root/xray-trojan-new-password.txt
}

test_and_restart() {
  say 'test and restart xray'
  "$XRAY" run -test -config "$CONFIG"
  systemctl restart xray
  sleep 2
  systemctl is-active --quiet xray || fail 'xray is not active after restart'
  ss -tlnp | grep ':443' | grep -qi 'xray' || fail 'xray is not listening on 443 after restart'
}

make_result() {
  say 'write result'
  ip=$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)
  [ -n "$ip" ] || ip="$IP_FALLBACK"
  pass=$(cat /root/xray-trojan-new-password.txt)
  link="trojan://${pass}@${ip}:443?security=tls&sni=${SNI}&allowInsecure=1&type=tcp#${NODE_NAME}"
  bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
  status=$(systemctl is-active xray 2>/dev/null || true)
  listen=$(ss -tlnp | grep ':443' || true)
  override=$(cat /etc/systemd/system/xray.service.d/override.conf 2>/dev/null || true)
  backup_latest=$(cat /root/xray-backup/latest-ts 2>/dev/null || true)
  cat >"$RESULT" <<EOF
NEW_TROJAN_LINK=$link
NEW_PASSWORD=$pass
IP=$ip
PORT=443
SNI=$SNI
XRAY_STATUS=$status
BBR=$bbr
BACKUP_DIR=$BACKUP_DIR
BACKUP_TS=$backup_latest
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
  upload=$(curl -fsS -F "file=@${RESULT}" https://tmpfiles.org/api/v1/upload 2>/dev/null || true)
  if [ -n "$upload" ]; then
    printf '\nUPLOAD_RESULT:\n%s\n' "$upload"
  else
    printf '\nUPLOAD_RESULT: failed; copy the NEW_TROJAN_LINK above\n'
  fi
}

main() {
  require_root
  precheck
  backup
  enable_bbr
  harden_systemd
  rotate_and_reduce_logs
  test_and_restart
  trap - ERR
  make_result
  say 'done'
}

main "$@"
