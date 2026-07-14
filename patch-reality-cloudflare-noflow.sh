set -Eeuo pipefail
CONFIG=/etc/xray/config.json
DOMAIN=www.cloudflare.com
IP=70.39.182.231
PORT=443

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG not found"
  exit 1
fi
cp "$CONFIG" "/etc/xray/config.json.bak.$(date +%s)"

python3 - <<'PY'
import json
p='/etc/xray/config.json'
with open(p) as f:
    c=json.load(f)
inb=c['inbounds'][0]
# Improve compatibility: no xtls-rprx-vision flow, Cloudflare as REALITY target.
for client in inb['settings']['clients']:
    client.pop('flow', None)
r=inb['streamSettings']['realitySettings']
r['dest']='www.cloudflare.com:443'
r['serverNames']=['www.cloudflare.com']
with open(p,'w') as f:
    json.dump(c,f,indent=2)
PY

systemctl daemon-reload
systemctl restart xray
sleep 2
systemctl --no-pager --full status xray || true
ss -tlnp | grep ':443'

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
VLESS="vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#LisaHost-REALITY-443-CF-noflow"
cat >/root/xray-reality-result.txt <<EOF
UUID=$UUID
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
DOMAIN=$DOMAIN
VLESS=$VLESS
EOF

echo "VLESS LINK:"
echo "$VLESS"
echo "Saved: /root/xray-reality-result.txt"
