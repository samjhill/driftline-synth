#!/usr/bin/env bash
# Loud ALSA tone on the Pi jack — stops only SuperCollider/JACK (not monitor/MIDI).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"

log() { echo "$(date -Iseconds) [headphone-tone] $*"; }

log "stop SuperCollider (free headphone PCM; keep monitor + MIDI)"
sudo systemctl stop pi-ambient-synth.service 2>/dev/null || true
sudo systemctl stop supercollider.service 2>/dev/null || true
pkill -x jackd scsynth sclang 2>/dev/null || true
sleep 2

if command -v raspi-config >/dev/null; then
  sudo raspi-config nonint do_audio 1 2>/dev/null || true
fi
amixer -c 0 sset PCM 100% unmute 2>/dev/null || true

log "LOUD 440 Hz ~6s on hw:0,0"
timeout 7 speaker-test -D hw:0,0 -c1 -r48000 -t sine -f 440 -l 2 -s 1 2>/dev/null \
  || timeout 7 speaker-test -D plughw:0,0 -c1 -r48000 -t sine -f 440 -l 2 -s 1 2>/dev/null \
  || true

log "restart SuperCollider"
sudo systemctl start supercollider.service
for _ in $(seq 1 90); do
  [[ -f /var/lib/pi-ambient-synth/sc-engine-ready ]] && break
  sleep 1
done
[[ -f /var/lib/pi-ambient-synth/sc-engine-ready ]] || {
  log "FAIL: sc-engine-ready missing"
  exit 1
}
"$INSTALL_DIR/scripts/ensure_jack_playback.sh" 2>/dev/null || true
sudo systemctl start pi-ambient-synth.service 2>/dev/null || true
sudo systemctl start pi-ambient-synth-midi.service 2>/dev/null || true
log "done (SC + MIDI bridge up)"
