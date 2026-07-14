set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

log(){ printf '\n[BOOT] %s\n' "$*"; }
need_root(){ [ "$(id -u)" = "0" ] || { echo "run as root"; exit 1; }; }

need_root
log "LisaHost Ubuntu 22.04 Xray REALITY + WARP bootstrap"

DOMAIN="www.microsoft.com"
PORT="443"
XRAY_ZIP="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
WARP_PORT="40000"

log "Stop conflicting services"
systemctl stop xray 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop sing-box 2>/dev/null || true
pkill -f '/usr/local/bin/xray' 2>/dev/null || true
pkill -f '/etc/sing-box/sing-box' 2>/dev/null || true

log "Install base packages"
apt-get update -y
apt-get install -y ca-certificates curl wget unzip jq openssl gpg lsb-release iproute2 ufw

log "Install Xray from official release zip"
rm -rf /tmp/xray-install
mkdir -p /tmp/xray-install /usr/local/share/xray /etc/xray
curl -fsSL "$XRAY_ZIP" -o /tmp/xray-install/xray.zip
unzip -o /tmp/xray-install/xray.zip -d /tmp/xray-install >/dev/null
install -m 755 /tmp/xray-install/xray /usr/local/bin/xray
[ -f /tmp/xray-install/geoip.dat ] && install -m 644 /tmp/xray-install/geoip.dat /usr/local/share/xray/geoip.dat || true
[ -f /tmp/xray-install/geosite.dat ] && install -m 644 /tmp/xray-install/geosite.dat /usr/local/share/xray/geosite.dat || true

log "Generate UUID and REALITY keypair"
UUID="$(/usr/local/bin/xray uuid)"
KEYPAIR="$(/usr/local/bin/xray x25519)"
PRIVATE_KEY="$(printf '%s\n' "$KEYPAIR" | awk -F': ' '/Private/{print $2; exit}')"
PUBLIC_KEY="$(printf '%s\n' "$KEYPAIR" | awk -F': ' '/Public/{print $2; exit}')"
SHORT_ID="$(openssl rand -hex 4)"
[ -n "$UUID" ] && [ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ] && [ -n "$SHORT_ID" ]

log "Write Xray VLESS-REALITY config"
cat >/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "vless-reality-443",
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID", "flow": "xtls-rprx-vision", "email": "lisahost" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$DOMAIN:443",
          "xver": 0,
          "serverNames": [ "$DOMAIN" ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [ "$SHORT_ID" ]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF
chmod 600 /etc/xray/config.json

log "Create systemd unit for Xray"
cat >/etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

log "Open firewall only for SSH and VLESS if ufw is present"
ufw --force disable >/dev/null 2>&1 || true
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true

log "Start Xray"
/usr/local/bin/xray test -config /etc/xray/config.json
systemctl daemon-reload
systemctl enable --now xray
sleep 2
systemctl --no-pager --full status xray || true
ss -tlnp | grep ':443' || { echo 'ERROR: port 443 not listening'; journalctl -u xray -n 80 --no-pager; exit 1; }

log "Install Cloudflare WARP client"
install -d -m 0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor >/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-jammy}")"
case "$CODENAME" in jammy|focal|noble|bookworm|bullseye) ;; *) CODENAME="jammy" ;; esac
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $CODENAME main" >/etc/apt/sources.list.d/cloudflare-client.list
apt-get update -y
apt-get install -y cloudflare-warp
systemctl enable --now warp-svc || true
sleep 3

log "Configure WARP SOCKS5 mode on 127.0.0.1:$WARP_PORT"
warp-cli --accept-tos registration new 2>/dev/null || warp-cli --accept-tos register 2>/dev/null || true
warp-cli --accept-tos mode proxy 2>/dev/null || warp-cli --accept-tos set-mode proxy 2>/dev/null || true
warp-cli --accept-tos proxy port "$WARP_PORT" 2>/dev/null || warp-cli --accept-tos set-proxy-port "$WARP_PORT" 2>/dev/null || true
warp-cli --accept-tos connect 2>/dev/null || true
sleep 5
warp-cli --accept-tos status || true
TRACE="$(curl -m 20 --socks5-hostname 127.0.0.1:$WARP_PORT -s https://www.cloudflare.com/cdn-cgi/trace || true)"
printf '%s\n' "$TRACE" | grep -E '^(ip|warp|loc)=' || true

VLESS="vless://${UUID}@70.39.182.231:${PORT}?encryption=none&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision&headerType=none#LisaHost-REALITY-443"

cat >/root/xray-reality-result.txt <<EOF
UUID=$UUID
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
WARP_SOCKS5=127.0.0.1:$WARP_PORT
VLESS=$VLESS
EOF

log "DONE"
echo "UUID: $UUID"
echo "PublicKey: $PUBLIC_KEY"
echo "ShortID: $SHORT_ID"
echo "WARP SOCKS5: 127.0.0.1:$WARP_PORT"
echo "VLESS LINK:"
echo "$VLESS"
echo "Saved: /root/xray-reality-result.txt"
