set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

IP=70.39.182.231
PORT=443
DOMAIN=www.cloudflare.com
PASS=6kBoVkFtLYW7wt0w9ZFnXLxJ
XRAY_BIN=/usr/local/bin/xray

if [ ! -x "$XRAY_BIN" ]; then
  echo 'ERROR: /usr/local/bin/xray not found. Run Xray install first.'
  exit 1
fi

mkdir -p /etc/xray/certs /var/log/xray
systemctl stop xray 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /etc/xray/certs/trojan.key \
  -out /etc/xray/certs/trojan.crt \
  -days 3650 \
  -subj "/CN=${DOMAIN}" >/dev/null 2>&1
chmod 600 /etc/xray/certs/trojan.key

cp /etc/xray/config.json "/etc/xray/config.json.bak.trojan.$(date +%s)" 2>/dev/null || true
cat >/etc/xray/config.json <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "trojan-tls-443",
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "trojan",
      "settings": {
        "clients": [
          { "password": "${PASS}", "email": "lisahost" }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${DOMAIN}",
          "certificates": [
            {
              "certificateFile": "/etc/xray/certs/trojan.crt",
              "keyFile": "/etc/xray/certs/trojan.key"
            }
          ]
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

systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 2
systemctl --no-pager --full status xray || true
ss -tlnp | grep ':443'

LINK="trojan://${PASS}@${IP}:${PORT}?security=tls&sni=${DOMAIN}&allowInsecure=1&type=tcp#LisaHost-Trojan-TLS-443"
cat >/root/trojan-tls-result.txt <<EOF
PASS=${PASS}
DOMAIN=${DOMAIN}
LINK=${LINK}
EOF

echo 'TROJAN LINK:'
echo "$LINK"
echo 'Saved: /root/trojan-tls-result.txt'
