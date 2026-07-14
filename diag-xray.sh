set -Eeuo pipefail

echo '=== TIME ==='
date -u

echo '=== XRAY STATUS ==='
systemctl --no-pager --full status xray || true

echo '=== LISTEN 443 ==='
ss -tlnp | grep ':443' || true

echo '=== CONFIG SUMMARY ==='
python3 - <<'PY'
import json
p='/etc/xray/config.json'
with open(p) as f:
    c=json.load(f)
i=c['inbounds'][0]
r=i['streamSettings']['realitySettings']
print('listen=', i.get('listen'))
print('port=', i.get('port'))
print('client_id=', i['settings']['clients'][0]['id'])
print('flow=', i['settings']['clients'][0].get('flow'))
print('dest=', r.get('dest'))
print('serverNames=', r.get('serverNames'))
print('shortIds=', r.get('shortIds'))
print('privateKey_len=', len(r.get('privateKey','')))
PY

echo '=== SERVER OUTBOUND TEST ==='
curl -4 -I --max-time 10 https://www.microsoft.com || true
curl -4 -I --max-time 10 https://www.cloudflare.com/cdn-cgi/trace || true

echo '=== XRAY RECENT LOG ==='
journalctl -u xray -n 120 --no-pager || true

echo '=== RESULT FILE ==='
cat /root/xray-reality-result.txt || true
