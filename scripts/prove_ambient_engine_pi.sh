#!/usr/bin/env bash
# Pi: prove full ambient stack (jackd + scsynth + engine + OSC note).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
PY="${INSTALL_DIR}/.venv/bin/python"
PROOF="$MARKER_DIR/ambient-engine-proof.json"
TS="$(date -Iseconds)"

log() { echo "$(date -Iseconds) [prove-ambient] $*"; }

[[ "$(cat /etc/pi-ambient-synth/audio-mode.conf 2>/dev/null)" == *ambient* ]] \
  || log "WARN: audio-mode.conf not ambient"

systemctl is-active --quiet supercollider.service \
  || { log "FAIL: supercollider not active"; exit 1; }

[[ -f "$MARKER_DIR/sc-engine-ready" ]] || { log "FAIL: sc-engine-ready missing"; exit 1; }

if [[ -f "$MARKER_DIR/scsynth_audio.conf" ]]; then
  log "scsynth driver: $(grep SC_SYNTH_DRIVER "$MARKER_DIR/scsynth_audio.conf" || true)"
fi

j="$(journalctl -u supercollider -n 100 --no-pager --since "5 min ago" 2>/dev/null || true)"
echo "$j" | grep -qiE 'syntax error|command line parse failed' \
  && { log "FAIL: SC syntax error"; exit 1; }
echo "$j" | grep -qE 'Engine synths started|startup chime' \
  || { log "FAIL: engine not started"; exit 1; }

if [[ -f /etc/systemd/system/supercollider.service.d/audio.conf ]] \
  && grep -q SC_SCLANG_OWNS_AUDIO /etc/systemd/system/supercollider.service.d/audio.conf 2>/dev/null; then
  pgrep -x jackd >/dev/null && log "WARN: jackd running (expected sclang-owned plughw audio)"
else
  pgrep -x jackd >/dev/null || log "WARN: jackd not running"
fi

[[ -x "$PY" ]] && "$PY" "$INSTALL_DIR/scripts/test_osc.py" \
  || { log "FAIL: test_osc.py"; exit 1; }

sleep 1
j2="$(journalctl -u supercollider -n 20 --no-pager --since "45 sec ago" 2>/dev/null || true)"
echo "$j2" | grep -q 'pi_test_beep' \
  || { log "FAIL: no pi_test_beep in journal"; exit 1; }
echo "$j2" | grep -qE 'OSC note_on|playNote:' \
  || { log "FAIL: no playNote after test_osc"; exit 1; }

log "PASS: ambient engine stack (listen for drone + test beep on headphones)"
printf '%s\n' "{\"ok\":true,\"at\":\"$TS\",\"mode\":\"ambient\"}" | sudo tee "$PROOF" >/dev/null
