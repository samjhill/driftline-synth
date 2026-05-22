#!/usr/bin/env bash
# Mac → Pi: sync isolation scripts and run a chosen step with sudo service stops.
# Usage: ./scripts/run_audio_isolation_on_pi.sh alsa|report|jack|sc
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/pi_ssh.sh
source "$ROOT/scripts/lib/pi_ssh.sh"

STEP="${1:-alsa}"
HOST="${PI_HOST:-pi@raspberrypi.local}"
REMOTE="${PI_REMOTE_ROOT:-/home/pi/pi-ambient-synth}"

case "$STEP" in
  alsa)  SCRIPT="alsa_headphone_smoke_test.sh" ;;
  report) SCRIPT="audio_device_report.sh" ;;
  jack)  SCRIPT="jack_headphone_smoke_test.sh" ;;
  sc)    SCRIPT="sc_jack_known_good_test.sh" ;;
  -h|--help)
    echo "Usage: $0 [alsa|report|jack|sc]"
    exit 0
    ;;
  *)
    echo "Unknown step: $STEP (alsa|report|jack|sc)" >&2
    exit 2
    ;;
esac

pi_ssh_setup
pi_rsync "$ROOT/scripts/" "$HOST:$REMOTE/scripts/" --exclude '__pycache__'
pi_rsync "$ROOT/scripts/lib/" "$HOST:$REMOTE/scripts/lib/"
pi_rsync "$ROOT/synth/sc_direct_smoke.scd" "$HOST:$REMOTE/synth/"
pi_rsync "$ROOT/synth/pi_bind_port.scd" "$HOST:$REMOTE/synth/"
pi_ssh "$HOST" "chmod +x $REMOTE/scripts/*.sh $REMOTE/scripts/lib/*.sh 2>/dev/null || true"

if [[ "$STEP" != "report" ]]; then
  echo "==> stop/mask production audio (sudo)"
  pi_ssh_sudo "$HOST" "systemctl stop pi-ambient-synth pi-ambient-synth-midi pi-ambient-synth-monitor supercollider 2>/dev/null || true; systemctl mask supercollider pi-ambient-synth pi-ambient-synth-midi 2>/dev/null || true; pkill -9 -x sclang scsynth jackd 2>/dev/null || true; sleep 2"
fi

echo "==> run $SCRIPT on Pi"
pi_ssh "$HOST" "INSTALL_DIR=$REMOTE bash $REMOTE/scripts/$SCRIPT"

if [[ "$STEP" != "report" ]]; then
  pi_ssh_sudo "$HOST" "systemctl unmask supercollider pi-ambient-synth pi-ambient-synth-midi 2>/dev/null || true"
fi
