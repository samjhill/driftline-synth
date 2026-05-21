#!/usr/bin/env bash
# Mac → Pi: rsync current tree, restart synth services (no GitHub timer).
#   ./scripts/deploy_to_pi.sh
#   ./scripts/deploy_to_pi.sh --no-restart
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/pi_ssh.sh
source "$ROOT/scripts/lib/pi_ssh.sh"

HOST="${PI_HOST:-pi@raspberrypi.local}"
REMOTE="${PI_REMOTE_ROOT:-/home/pi/pi-ambient-synth}"
REF="$(git -C "$ROOT" rev-parse HEAD)"
SHORT="${REF:0:7}"
RESTART=1

for arg in "$@"; do
  case "$arg" in
    --no-restart) RESTART=0 ;;
    -h|--help)
      echo "Usage: $0 [--no-restart]"
      exit 0
      ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

export PI_HOST="$HOST"
pi_ssh_setup

echo "==> deploy $SHORT → $HOST:$REMOTE"

pi_ssh "$HOST" "bash -s" <<'REMOTE_STOP'
set -euo pipefail
sudo systemctl stop pi-ambient-synth-deploy.timer 2>/dev/null || true
sudo systemctl stop pi-ambient-synth-deploy.service 2>/dev/null || true
REMOTE_STOP

mkdir -p "$ROOT/scripts/lib"
pi_rsync "$ROOT/scripts/" "$HOST:$REMOTE/scripts/" \
  --exclude '__pycache__' --exclude '*.pyc'
pi_rsync "$ROOT/scripts/lib/" "$HOST:$REMOTE/scripts/lib/"
pi_rsync "$ROOT/src/" "$HOST:$REMOTE/src/"
pi_rsync "$ROOT/synth/" "$HOST:$REMOTE/synth/"
pi_rsync "$ROOT/config/default.yaml" "$HOST:$REMOTE/config/"
pi_rsync "$ROOT/systemd/" "$HOST:$REMOTE/systemd/"

pi_ssh "$HOST" "chmod +x $REMOTE/scripts/*.sh 2>/dev/null || true"

pi_ssh "$HOST" "bash -s" <<REMOTE_MARK
set -euo pipefail
MARKER=/var/lib/pi-ambient-synth
sudo mkdir -p "\$MARKER"
echo '$REF' | sudo tee "\$MARKER/last_deploy_sha" >/dev/null
echo '$SHORT' | sudo tee "$REMOTE/.deploy_sha" >/dev/null
echo "Marked deploy SHA: $SHORT"
REMOTE_MARK

pi_ssh "$HOST" "bash -s" <<REMOTE_UNITS
set -euo pipefail
for u in pi-ambient-synth-midi.service pi-ambient-synth-monitor.service; do
  if [[ -f "$REMOTE/systemd/\$u" ]]; then
    sudo cp "$REMOTE/systemd/\$u" /etc/systemd/system/
  fi
done
sudo systemctl daemon-reload
sudo systemctl enable pi-ambient-synth-midi.service pi-ambient-synth-monitor.service 2>/dev/null || true
REMOTE_UNITS

if [[ "$RESTART" == "1" ]]; then
  echo "==> restart synth services"
  pi_ssh "$HOST" "export PI_AMBIENT_ROOT=$REMOTE PI_SKIP_DEPLOY_TIMER=1; $REMOTE/scripts/restart_synth_services.sh"
  echo "==> restart monitor"
  pi_ssh "$HOST" "sudo systemctl restart pi-ambient-synth-monitor.service; sleep 1; systemctl is-active pi-ambient-synth-monitor.service"
fi

PI_IP="$(pi_ssh "$HOST" "hostname -I 2>/dev/null | awk '{print \$1}'" 2>/dev/null | tr -d '\r\n' || true)"
PI_IP="${PI_IP:-192.168.1.64}"
echo "==> done ($SHORT). Monitor (any device on LAN): http://${PI_IP}:8080/ — audio is on Pi headphones"
