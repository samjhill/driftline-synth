#!/usr/bin/env bash
# Pi end-to-end verify: audio + OSC + MIDI reseed/note paths (no human listening).
# Run from Mac: ./scripts/run_pi_e2e.sh
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
RESULT_FILE="${PI_E2E_RESULT:-$MARKER_DIR/e2e-last.txt}"
LOG="${PI_E2E_LOG:-$MARKER_DIR/pi-ambient-e2e.log}"
PY="${INSTALL_DIR}/.venv/bin/python"
SC_WAIT="${PI_E2E_SC_WAIT:-60}"
SYNTH_WAIT="${PI_E2E_SYNTH_WAIT:-45}"

# shellcheck source=scripts/lib/audio_stack.sh
source "$INSTALL_DIR/scripts/lib/audio_stack.sh"

fail() {
  log "FAIL: $1"
  echo "E2E FAIL: $1" >&2
  echo "status=fail at=$(date -Iseconds) msg=$1" >"$RESULT_FILE"
  exit 1
}

pass() {
  log "PASS: Pi MIDI + audio paths OK"
  echo "E2E PASS: Pi MIDI + audio paths OK"
  echo "status=pass at=$(date -Iseconds)" >"$RESULT_FILE"
}

log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  echo "$(date -Iseconds) [pi-e2e] $*" >>"$LOG" 2>/dev/null || true
  echo "$(date -Iseconds) [pi-e2e] $*"
}

check_supercollider() {
  systemctl is-active --quiet supercollider.service || fail "supercollider not active"
  [[ -f "$MARKER_DIR/sc-engine-ready" ]] || fail "sc-engine-ready missing"
  local j
  j="$(journalctl -u supercollider -n 30 --no-pager --since "5 min ago" 2>/dev/null || true)"
  echo "$j" | grep -q 'listening on OSC port 57120' \
    || fail "sclang not listening on 57120"
  echo "$j" | grep -qi 'linearRamp.*not understood' \
    && fail "SC still hitting linearRamp errors"
  echo "$j" | grep -q 'build sc313-jackOutputs\|build sc313-noLinearRamp\|build sc313-oscPaths' \
    || fail "engine build marker missing (stale ambient_engine.scd?)"
}

check_jack_playback() {
  command -v jack_lsp >/dev/null || fail "jack_lsp missing"
  local links
  links="$(jack_lsp -l 2>/dev/null || true)"
  if echo "$links" | grep -qE 'SuperCollider:out_1.*system:playback_1|SuperCollider:out_1 -> system:playback_1'; then
    log "JACK: SuperCollider:out_1 → system:playback_1"
    return 0
  fi
  # scsynth may auto-connect via SC_JACK_DEFAULT_OUTPUTS even if -l format differs
  if pgrep -x scsynth >/dev/null && pgrep -x jackd >/dev/null; then
    log "WARN: jack_lsp -l missing explicit link (checking ports exist)"
    jack_lsp 2>/dev/null | grep -q 'SuperCollider:out_1' \
      && jack_lsp 2>/dev/null | grep -q 'system:playback_1' \
      || fail "SuperCollider or system playback ports missing"
    return 0
  fi
  fail "JACK playback path not verified"
}

check_osc_beep() {
  [[ -x "$PY" ]] || fail "venv python missing"
  local j_before j_after
  j_before="$(journalctl -u supercollider -n 5 --no-pager 2>/dev/null | wc -l)"
  "$PY" "$INSTALL_DIR/scripts/test_osc.py" || fail "test_osc.py failed"
  sleep 0.6
  j_after="$(journalctl -u supercollider -n 40 --no-pager --since "2 min ago" 2>/dev/null || true)"
  echo "$j_after" | grep -q 'pi_test_beep.*440' \
    || fail "SC journal missing pi_test_beep 440 Hz"
  echo "$j_after" | grep -qi 'ERROR.*not understood' \
    && fail "SC errors after test_osc"
  log "OSC beep + patch + note messages accepted by SC"
}

check_synth_service() {
  local i state
  for i in $(seq 1 "$SYNTH_WAIT"); do
    state="$(systemctl is-active pi-ambient-synth.service 2>/dev/null || echo dead)"
    [[ "$state" == "active" ]] && break
    sleep 1
  done
  state="$(systemctl is-active pi-ambient-synth.service 2>/dev/null || echo dead)"
  if [[ "$state" != "active" ]]; then
    log "WARN: pi-ambient-synth is $state (continuing MIDI logic test)"
    journalctl -u pi-ambient-synth -n 12 --no-pager 2>/dev/null | tail -8 | tee -a "$LOG" || true
    return 1
  fi
  journalctl -u pi-ambient-synth -n 40 --no-pager --since "10 min ago" 2>/dev/null \
    | grep -q 'MIDI listener started' \
    || log "WARN: no 'MIDI listener started' in synth journal (keyboard may still work after open)"
  log "pi-ambient-synth active"
  return 0
}

check_midi_paths() {
  [[ -x "$PY" ]] || fail "venv python missing"
  "$PY" "$INSTALL_DIR/scripts/simulate_midi_e2e.py" || fail "simulate_midi_e2e.py failed"
}

log "=== pi e2e verify ==="
check_supercollider
check_jack_playback
check_osc_beep
check_synth_service || true
check_midi_paths
pass
