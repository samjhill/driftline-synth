#!/usr/bin/env bash
# Pi: prove Flues-Synth + MIDI bridge.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
PY="${INSTALL_DIR}/.venv/bin/python"

log() { echo "$(date -Iseconds) [prove-flues] $*"; }

grep -q 'AUDIO_MODE=flues' /etc/pi-ambient-synth/audio-mode.conf 2>/dev/null \
  || log "WARN: audio-mode not flues"

systemctl is-active --quiet pi-flues-synth.service \
  || { log "FAIL: pi-flues-synth not active"; exit 1; }
pgrep -x flues-synth >/dev/null || { log "FAIL: flues-synth process missing"; exit 1; }

[[ -x "$PY" ]] && "$PY" -c "
import sys
sys.path.insert(0, '$INSTALL_DIR/src')
from flues_client import find_flues_output_port
p = find_flues_output_port()
assert p, 'no Flues MIDI output port'
print('Flues MIDI port:', p)
"

log "PASS: Flues-Synth + MIDI bridge (play KeyStep to hear voices)"
printf '%s\n' "{\"ok\":true,\"at\":\"$(date -Iseconds)\",\"mode\":\"flues\"}" | sudo tee "$MARKER_DIR/flues-engine-proof.json" >/dev/null
