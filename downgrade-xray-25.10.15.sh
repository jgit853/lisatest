set -Eeuo pipefail
VER=v25.10.15
URL="https://github.com/XTLS/Xray-core/releases/download/${VER}/Xray-linux-64.zip"
TMP=/tmp/xray-downgrade

mkdir -p "$TMP"
rm -rf "$TMP"/*
echo "Downloading $URL"
curl -fL "$URL" -o "$TMP/xray.zip"
unzip -o "$TMP/xray.zip" -d "$TMP" >/dev/null
if [ ! -x "$TMP/xray" ]; then
  echo "ERROR: xray binary missing in zip"
  exit 1
fi
systemctl stop xray || true
cp -a /usr/local/bin/xray "/usr/local/bin/xray.bak.$(date +%s)" || true
install -m 755 "$TMP/xray" /usr/local/bin/xray
/usr/local/bin/xray version
systemctl daemon-reload
systemctl restart xray
sleep 2
systemctl --no-pager --full status xray || true
ss -tlnp | grep ':443'
echo 'Downgrade done. Keep using existing vless-link.txt / current node.'
echo 'After one client test, check:'
echo 'cat /var/log/xray/error.log'
