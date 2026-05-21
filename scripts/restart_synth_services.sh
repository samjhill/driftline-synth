#!/usr/bin/env bash
# Clean restart of supercollider + pi-ambient-synth (production deploy + verify).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
READY="$MARKER_DIR/sc-engine-ready"
WAIT_READY_SEC="${WAIT_READY_SEC:-60}"

# shellcheck source=scripts/lib/audio_stack.sh
source "$INSTALL_DIR/scripts/lib/audio_stack.sh"

log() { echo "$(date -Iseconds) [restart-synth] $*"; }

log "stop deploy timer + synth services"
sudo systemctl stop pi-ambient-synth-deploy.timer 2>/dev/null || true
sudo systemctl stop pi-ambient-synth-midi.service 2>/dev/null || true
sudo systemctl stop pi-ambient-synth.service 2>/dev/null || true
sudo systemctl stop supercollider.service 2>/dev/null || true
pkill -x sclang 2>/dev/null || true
free_alsa
sleep 2.0

install_sc_systemd_units "$INSTALL_DIR"
sudo systemctl reset-failed supercollider.service pi-ambient-synth.service 2>/dev/null || true
rm -f "$READY" 2>/dev/null || true

log "start supercollider"
sudo systemctl start supercollider.service
for _ in $(seq 1 "$WAIT_READY_SEC"); do
  if [[ -f "$READY" ]] && systemctl is-active --quiet supercollider.service; then
    log "supercollider active + sc-engine-ready"
    break
  fi
  sleep 1
done

if ! systemctl is-active --quiet supercollider.service; then
  echo "ERROR: supercollider.service not active" >&2
  journalctl -u supercollider -n 20 --no-pager >&2 || true
  exit 1
fi

log "start pi-ambient-synth"
sudo systemctl start pi-ambient-synth.service 2>/dev/null || true
sleep 5
if ! systemctl is-active --quiet pi-ambient-synth.service; then
  echo "ERROR: pi-ambient-synth.service not active" >&2
  exit 1
fi
log "start pi-ambient-synth-midi"
sudo systemctl enable pi-ambient-synth-midi.service 2>/dev/null || true
sudo systemctl start pi-ambient-synth-midi.service 2>/dev/null || true
sleep 3
systemctl is-active supercollider.service pi-ambient-synth.service pi-ambient-synth-midi.service 2>/dev/null || true
sudo systemctl start pi-ambient-synth-deploy.timer 2>/dev/null || true

if [[ ! -f "$READY" ]]; then
  echo "WARN: $READY not present — OSC notes may be silent until engine finishes boot" >&2
fi
