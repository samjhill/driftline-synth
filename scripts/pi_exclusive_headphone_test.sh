#!/usr/bin/env bash
# DIAGNOSTIC ONLY: release ALSA from JACK, speaker-test, restart SC.
# Usage: ./scripts/pi_exclusive_headphone_test.sh --destructive-audio-test
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
# shellcheck source=scripts/lib/destructive_audio_guard.sh
source "$INSTALL_DIR/scripts/lib/destructive_audio_guard.sh"
require_destructive_audio_test "$@"

log() { echo "$(date -Iseconds) [headphone-blast] $*"; }

log "stop synth services (free bcm2835 headphone PCM)"
sudo systemctl stop pi-ambient-synth.service 2>/dev/null || true
sudo systemctl stop supercollider.service 2>/dev/null || true
pkill -x jackd scsynth sclang 2>/dev/null || true
sleep 2

if command -v raspi-config >/dev/null; then
  sudo raspi-config nonint do_audio 1 2>/dev/null || true
fi
amixer -c 0 sset PCM 100% unmute 2>/dev/null || true

log "LOUD 440 Hz on hw:0,0 (speaker-test — not SuperCollider)"
timeout 7 speaker-test -D hw:0,0 -c1 -r48000 -t sine -f 440 -l 2 -s 1 2>/dev/null \
  || timeout 7 speaker-test -D plughw:0,0 -c1 -r48000 -t sine -f 440 -l 2 -s 1 2>/dev/null \
  || true

log "restart SuperCollider"
sudo systemctl start supercollider.service
for _ in $(seq 1 90); do
  [[ -f /var/lib/pi-ambient-synth/sc-engine-ready ]] && break
  sleep 1
done
"$INSTALL_DIR/scripts/ensure_jack_playback.sh" 2>/dev/null || true
sudo systemctl start pi-ambient-synth.service 2>/dev/null || true
sudo systemctl start pi-ambient-synth-midi.service 2>/dev/null || true
log "done — run validate_real_synth_path.sh"
