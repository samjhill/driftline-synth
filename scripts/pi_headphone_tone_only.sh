#!/usr/bin/env bash
# DIAGNOSTIC ONLY: loud ALSA speaker-test — stops SuperCollider/JACK (never call from monitor UI).
# Usage: ./scripts/pi_headphone_tone_only.sh --destructive-audio-test
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
# shellcheck source=scripts/lib/destructive_audio_guard.sh
source "$INSTALL_DIR/scripts/lib/destructive_audio_guard.sh"
require_destructive_audio_test "$@"

log() { echo "$(date -Iseconds) [headphone-tone] $*"; }

log "DIAGNOSTIC: stop SuperCollider (free headphone PCM)"
sudo systemctl stop pi-ambient-synth.service 2>/dev/null || true
sudo systemctl stop supercollider.service 2>/dev/null || true
pkill -x jackd scsynth sclang 2>/dev/null || true
sleep 2

if command -v raspi-config >/dev/null; then
  sudo raspi-config nonint do_audio 1 2>/dev/null || true
fi
amixer -c 0 sset PCM 100% unmute 2>/dev/null || true

log "LOUD 440 Hz ~6s on hw:0,0 (speaker-test — not SuperCollider)"
timeout 7 speaker-test -D hw:0,0 -c1 -r48000 -t sine -f 440 -l 2 -s 1 2>/dev/null \
  || timeout 7 speaker-test -D plughw:0,0 -c1 -r48000 -t sine -f 440 -l 2 -s 1 2>/dev/null \
  || true

log "restart SuperCollider (you must verify services came back)"
sudo systemctl start supercollider.service
for _ in $(seq 1 90); do
  [[ -f /var/lib/pi-ambient-synth/sc-engine-ready ]] && break
  sleep 1
done
[[ -f /var/lib/pi-ambient-synth/sc-engine-ready ]] || {
  log "FAIL: sc-engine-ready missing after restart"
  exit 1
}
"$INSTALL_DIR/scripts/ensure_jack_playback.sh" 2>/dev/null || true
sudo systemctl start pi-ambient-synth.service 2>/dev/null || true
sudo systemctl start pi-ambient-synth-midi.service 2>/dev/null || true
log "done — run validate_real_synth_path.sh before trusting KeyStep audio"
