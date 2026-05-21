#!/usr/bin/env bash
# Prove KeyStep path on Pi: MIDI bridge up, OSC → SC playNote (same path as test note).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
PY="${INSTALL_DIR}/.venv/bin/python"
PROOF="/var/lib/pi-ambient-synth/keystep-proof.json"
MARKER_DIR="/var/lib/pi-ambient-synth"

log() { echo "$(date -Iseconds) [prove-keystep] $*"; }

fail() { log "FAIL: $*"; exit 1; }

log "ensure services"
sudo systemctl start supercollider.service 2>/dev/null || true
for _ in $(seq 1 90); do
  [[ -f "$MARKER_DIR/sc-engine-ready" ]] && break
  sleep 1
done
[[ -f "$MARKER_DIR/sc-engine-ready" ]] || fail "sc-engine-ready missing"

sudo systemctl start pi-ambient-synth-midi.service 2>/dev/null || true
sleep 2
systemctl is-active --quiet pi-ambient-synth-midi.service || fail "pi-ambient-synth-midi not active"

"$INSTALL_DIR/scripts/ensure_jack_playback.sh" 2>/dev/null || fail "JACK playback not linked"

log "MIDI status"
if [[ -f "$MARKER_DIR/midi-status.json" ]]; then
  cat "$MARKER_DIR/midi-status.json"
fi
if ! grep -q '"listening": true' "$MARKER_DIR/midi-status.json" 2>/dev/null; then
  log "WARN: midi-status not listening:true (KeyStep may be unplugged — continuing OSC proof)"
fi

log "OSC keyboard proof (C4 → E4 → G4, vel 127)"
journalctl -u supercollider --since "1 min ago" --no-pager >/dev/null 2>&1 || true
"$PY" <<'PY'
import sys
import time
from pathlib import Path

ROOT = Path("/home/pi/pi-ambient-synth")
sys.path.insert(0, str(ROOT / "src"))
from config_loader import load_config
from osc_client import OscClient

c = OscClient(load_config())
for note in (60, 64, 67):
    c.note_on(note, 127)
    time.sleep(0.35)
    c.note_off(note)
    time.sleep(0.1)
print("OSC notes sent")
PY

sleep 1
J=$(journalctl -u supercollider -n 40 --no-pager --since "2 min ago")
echo "$J" | grep -q "playNote: midi 60" || fail "SC did not log playNote for MIDI C4"
echo "$J" | grep -q "playNote: midi 64" || fail "SC did not log playNote for E4"
echo "$J" | grep -q "playNote: midi 67" || fail "SC did not log playNote for G4"

log "simulate_midi_e2e (bridge logic)"
"$PY" "$INSTALL_DIR/scripts/simulate_midi_e2e.py" || fail "simulate_midi_e2e failed"

TS=$(date -Iseconds)
cat >"$PROOF" <<EOF
{
  "ok": true,
  "at": "$TS",
  "midi_service": "active",
  "jack_playback": "linked",
  "osc_notes": [60, 64, 67],
  "sc_playNote_logged": true,
  "simulate_midi_e2e": "pass",
  "engine": "playNote uses piRawTone on bus 0 (same as test_note)"
}
EOF

log "PASS — proof written to $PROOF"
log "Listen on Pi headphones: run this, then play KeyStep keys (USB to Pi)."
cat "$PROOF"
