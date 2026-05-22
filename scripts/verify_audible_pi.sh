#!/usr/bin/env bash
# Pi: verify headphones produce sound (ALSA + JACK + SC beep + startup chime).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
PY="${INSTALL_DIR}/.venv/bin/python"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"

log() { echo "$(date -Iseconds) [audible] $*"; }

[[ -x "$INSTALL_DIR/scripts/ensure_jack_playback.sh" ]] \
  && "$INSTALL_DIR/scripts/ensure_jack_playback.sh" \
  || { log "FAIL: JACK playback not linked (jackd+scsynth must be up)"; exit 1; }
log "JACK playback linked"

if [[ "${PI_SKIP_APLAY_TEST:-}" != "1" ]] && [[ -x "$PY" ]]; then
  "$PY" "$INSTALL_DIR/scripts/play_headphone_test.py" -D plughw:0,0 -d 2 \
    || { log "FAIL: aplay headphone test"; exit 1; }
  log "ALSA headphone test OK"
fi

systemctl is-active --quiet supercollider.service \
  || { log "FAIL: supercollider not active"; exit 1; }

[[ -f "$MARKER_DIR/sc-engine-ready" ]] || { log "FAIL: sc-engine-ready missing"; exit 1; }

j="$(journalctl -u supercollider -n 80 --no-pager --since "3 min ago" 2>/dev/null || true)"
echo "$j" | grep -qiE 'syntax error|command line parse failed' \
  && { log "FAIL: SC syntax error"; exit 1; }
echo "$j" | grep -q 'build sc313-audibleFx' \
  || echo "$j" | grep -q 'Engine synths started' \
  || { log "FAIL: engine not started"; exit 1; }

if ! echo "$j" | grep -q 'startup chime'; then
  log "WARN: startup chime not in recent journal (service may have started earlier)"
fi

[[ -x "$PY" ]] && "$PY" "$INSTALL_DIR/scripts/test_osc.py" \
  || { log "FAIL: test_osc.py"; exit 1; }

sleep 0.8
j2="$(journalctl -u supercollider -n 15 --no-pager --since "30 sec ago" 2>/dev/null || true)"
echo "$j2" | grep -q 'pi_test_beep.*440' \
  || { log "FAIL: SC did not log pi_test_beep"; exit 1; }

echo "$j2" | grep -qE 'OSC note_on|playNote:' \
  || { log "FAIL: SC did not log OSC note_on / playNote after test_osc"; exit 1; }

log "PASS: audible path verified (ALSA + JACK + SC beep + playNote)"
echo "status=audible-pass at=$(date -Iseconds)" >"$MARKER_DIR/audible-last.txt"
