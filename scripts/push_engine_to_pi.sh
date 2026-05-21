#!/usr/bin/env bash
# Mac/Linux: rsync engine + run smoke on Pi in one shot (SSH pi@raspberrypi.local).
#   ./scripts/push_engine_to_pi.sh
#   PI_HOST=pi@192.168.1.64 ./scripts/push_engine_to_pi.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${PI_HOST:-pi@raspberrypi.local}"
REMOTE="${PI_REMOTE_ROOT:-/home/pi/pi-ambient-synth}"

echo "==> rsync engine -> $HOST:$REMOTE/synth/"
rsync -az "$ROOT/synth/ambient_engine.scd" "$HOST:$REMOTE/synth/ambient_engine.scd"
rsync -az "$ROOT/scripts/engine_smoke_pi.sh" "$ROOT/scripts/start_scsynth_alsa.sh" \
  "$ROOT/scripts/run_sclang_engine.sh" "$HOST:$REMOTE/scripts/"

echo "==> remote smoke (no systemd)"
ssh "$HOST" "chmod +x $REMOTE/scripts/engine_smoke_pi.sh && $REMOTE/scripts/engine_smoke_pi.sh --restart"

echo "==> OK. If smoke passed, restart on Pi:"
echo "    ssh $HOST 'sudo systemctl restart supercollider && sleep 20 && sudo systemctl restart pi-ambient-synth'"
