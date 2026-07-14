set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y tmate openssh-client ca-certificates
pkill -f 'tmate' 2>/dev/null || true
rm -rf /tmp/tmate.sock

tmate -S /tmp/tmate.sock new-session -d
for i in $(seq 1 30); do
  if tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}' >/tmp/tmate_ssh 2>/dev/null; then
    break
  fi
  sleep 1
done

echo '=== TMATE SSH ==='
cat /tmp/tmate_ssh || true
echo '=== TMATE WEB ==='
tmate -S /tmp/tmate.sock display -p '#{tmate_web}' || true
echo 'Keep this VNC terminal open. Do not reboot. Send me the TMATE SSH line.'
while true; do sleep 3600; done
