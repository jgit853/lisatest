set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y tmate openssh-client ca-certificates
pkill -f 'tmate' 2>/dev/null || true
rm -f /tmp/tmate.sock /tmp/tmate.log

tmate -S /tmp/tmate.sock -f /dev/null new-session -d

echo 'Waiting for tmate relay...'
if timeout 90 tmate -S /tmp/tmate.sock wait tmate-ready; then
  echo '=== TMATE SSH ==='
  tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}'
  echo '=== TMATE WEB ==='
  tmate -S /tmp/tmate.sock display -p '#{tmate_web}'
else
  echo 'ERROR: tmate did not become ready within 90s'
  echo '=== TMATE MESSAGES ==='
  tmate -S /tmp/tmate.sock show-messages || true
  echo '=== NETWORK TEST ==='
  getent hosts ssh.tmate.io || true
  nc -vz ssh.tmate.io 22 || true
  nc -vz ssh.tmate.io 2200 || true
  exit 1
fi

echo 'Keep this VNC terminal open. Send me the TMATE SSH line.'
while true; do sleep 3600; done
