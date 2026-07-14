set -Eeuo pipefail
CONFIG=/etc/xray/config.json
DOMAIN=www.microsoft.com
IP=70.39.182.231
PORT=443

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG not found"
  exit 1
fi
if [ ! -x /usr/local/bin/xray ]; then
  echo "ERROR: /usr/local/bin/xray not found"
  exit 1
fi

UUID=$(python3 - <<'PY'
import json
with open('/etc/xray/config.json') as f:
    c=json.load(f)
print(c['inbounds'][0]['settings']['clients'][0]['id'])
PY
)
PRIVATE_KEY=$(python3 - <<'PY'
import json
with open('/etc/xray/config.json') as f:
    c=json.load(f)
print(c['inbounds'][0]['streamSettings']['realitySettings']['privateKey'])
PY
)
SHORT_ID=$(python3 - <<'PY'
import json
with open('/etc/xray/config.json') as f:
    c=json.load(f)
print(c['inbounds'][0]['streamSettings']['realitySettings']['shortIds'][0])
PY
)
PUBLIC_KEY=$(/usr/local/bin/xray x25519 -i "$PRIVATE_KEY" | awk -F':' '/Public/{gsub(/^ +/,"",$2); print $2; exit}')

if [ -z "$UUID" ] || [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$SHORT_ID" ]; then
  echo "ERROR: failed to extract UUID/private/public/shortId"
  exit 1
fi

VLESS="vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision&headerType=none#LisaHost-REALITY-443"
cat >/root/xray-reality-result.txt <<EOF
UUID=$UUID
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
VLESS=$VLESS
EOF

echo "VLESS LINK:"
echo "$VLESS"
echo "Saved: /root/xray-reality-result.txt"
