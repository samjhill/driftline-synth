#!/usr/bin/env bash
# Prove direct ALSA KeyStep audio (jack must be stopped).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
PY="${INSTALL_DIR}/.venv/bin/python"
PROOF="/var/lib/pi-ambient-synth/direct-keys-proof.json"

log() { echo "$(date -Iseconds) [prove-direct-keys] $*"; }

[[ "$(cat /etc/pi-ambient-synth/audio-mode.conf 2>/dev/null)" == *direct_keys* ]] \
  || log "WARN: audio-mode.conf not direct_keys"

pgrep -x jackd >/dev/null && log "WARN: jackd still running (aplay may fail)"

log "aplay blip C4 on hw:0,0"
amixer -c 0 sset PCM 100% unmute 2>/dev/null || true
"$PY" "$INSTALL_DIR/scripts/play_keyboard_blip.py" 60 127 -D hw:0,0 -d 0.25 \
  || { log "FAIL: aplay blip"; exit 1; }

systemctl is-active --quiet pi-ambient-synth-midi.service \
  || { log "FAIL: midi service not active"; exit 1; }

grep -q '"listening": true' /var/lib/pi-ambient-synth/midi-status.json 2>/dev/null \
  || log "WARN: midi not listening (KeyStep unplugged?)"

TS=$(date -Iseconds)
printf '%s\n' "{\"ok\":true,\"at\":\"$TS\",\"mode\":\"direct_keys\"}" | sudo tee "$PROOF" >/dev/null
log "PASS — proof at $PROOF (listen: one blip now; keys via MIDI bridge)"
