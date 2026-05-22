#!/usr/bin/env bash
# Full Pi audio reset: jackd+scsynth+sclang, JACK links, loud test (run on the Pi).
# Usage: ./scripts/pi_fix_audio_now.sh --destructive-audio-test
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
PY="${INSTALL_DIR}/.venv/bin/python"
# shellcheck source=scripts/lib/destructive_audio_guard.sh
source "$INSTALL_DIR/scripts/lib/destructive_audio_guard.sh"
require_destructive_audio_test "$@"

log() { echo "$(date -Iseconds) [fix-audio] $*"; }

log "stop services"
sudo systemctl stop pi-ambient-synth-midi.service 2>/dev/null || true
sudo systemctl stop pi-ambient-synth-monitor.service 2>/dev/null || true
sudo systemctl stop pi-ambient-synth.service 2>/dev/null || true
sudo systemctl stop supercollider.service 2>/dev/null || true
sleep 2

log "direct ALSA headphone test (bypasses SuperCollider)"
amixer -c 0 sset PCM 95% unmute 2>/dev/null || true
if [[ -x "$PY" ]]; then
  "$PY" "$INSTALL_DIR/scripts/play_headphone_test.py" -D plughw:0,0 -r 48000 -d 3 \
    || { log "FAIL: aplay direct — check headphone jack on card 0"; exit 1; }
fi

log "start supercollider (fresh jack + scsynth + sclang)"
sudo systemctl start supercollider.service
for _ in $(seq 1 90); do
  [[ -f /var/lib/pi-ambient-synth/sc-engine-ready ]] && break
  sleep 1
done
[[ -f /var/lib/pi-ambient-synth/sc-engine-ready ]] || {
  log "FAIL: sc-engine-ready missing"
  journalctl -u supercollider -n 40 --no-pager >&2 || true
  exit 1
}

"$INSTALL_DIR/scripts/ensure_jack_playback.sh" || { log "FAIL: JACK playback not linked"; exit 1; }
jack_lsp -c 2>/dev/null | head -10 || true

log "OSC loud test"
if [[ -x "$PY" ]]; then
  "$PY" "$INSTALL_DIR/scripts/test_osc.py"
fi
sleep 1
journalctl -u supercollider -n 15 --no-pager | grep -iE 'Engine synths|playNote|test_beep|ensureEngine' || true

log "start midi + monitor"
sudo systemctl start pi-ambient-synth.service pi-ambient-synth-midi.service pi-ambient-synth-monitor.service 2>/dev/null || true

log "DONE — listen on Pi headphone jack now. If aplay worked but OSC did not, check journal above."
