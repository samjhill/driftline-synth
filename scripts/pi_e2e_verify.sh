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

check_sc_source() {
  [[ -x "$PY" ]] || fail "venv python missing"
  "$PY" "$INSTALL_DIR/scripts/validate_ambient_engine.py" "$INSTALL_DIR/synth/ambient_engine.scd" \
    || fail "ambient_engine.scd failed static SC validation"
  log "ambient_engine.scd static validation OK"
}

check_supercollider() {
  systemctl is-active --quiet supercollider.service || fail "supercollider not active"
  [[ -f "$MARKER_DIR/sc-engine-ready" ]] || fail "sc-engine-ready missing"
  local j
  j="$(journalctl -u supercollider -n 40 --no-pager --since "10 min ago" 2>/dev/null || true)"
  echo "$j" | grep -qiE 'syntax error|Command line parse failed|unexpected.*expecting' \
    && fail "sclang compile/parse error in journal (fix ambient_engine.scd)"
  echo "$j" | grep -q 'Engine synths started' \
    || fail "SC engine synths never started (journal missing 'Engine synths started')"
  echo "$j" | grep -q 'listening on OSC port 57120' \
    || fail "sclang not listening on 57120"
  echo "$j" | grep -qi 'linearRamp.*not understood' \
    && fail "SC still hitting linearRamp errors"
  echo "$j" | grep -q 'build sc313-audibleFx\|build sc313-jackOutputs\|build sc313-noLinearRamp\|build sc313-oscPaths' \
    || fail "engine build marker missing (stale ambient_engine.scd?)"
}

check_audible() {
  [[ -x "$INSTALL_DIR/scripts/verify_audible_pi.sh" ]] || fail "verify_audible_pi.sh missing"
  chmod +x "$INSTALL_DIR/scripts/verify_audible_pi.sh" 2>/dev/null || true
  PI_SKIP_APLAY_TEST="${PI_SKIP_APLAY_TEST:-0}" "$INSTALL_DIR/scripts/verify_audible_pi.sh" \
    || fail "audible verify failed (headphones silent?)"
  log "audible verify OK"
}

check_jack_playback() {
  command -v jack_lsp >/dev/null || fail "jack_lsp missing"
  if [[ -x "$INSTALL_DIR/scripts/ensure_jack_playback.sh" ]]; then
    "$INSTALL_DIR/scripts/ensure_jack_playback.sh" || fail "ensure_jack_playback failed"
  fi
  local conn
  conn="$(jack_lsp -c 2>/dev/null || true)"
  if echo "$conn" | awk '/^system:playback_1$/{getline; if(/SuperCollider:out_1/) found=1} END{exit !found}'; then
    log "JACK: SuperCollider:out_1 → system:playback_1 (verified)"
    return 0
  fi
  fail "JACK playback not linked (run ensure_jack_playback.sh — headphones silent without this)"
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
    fail "pi-ambient-synth is $state (SIGBUS? check journal)"
  fi
  journalctl -u pi-ambient-synth -n 15 --no-pager --since "2 min ago" 2>/dev/null \
    | grep -q 'status=7/BUS' && fail "pi-ambient-synth still SIGBUS in journal"
  log "pi-ambient-synth active"
  if systemctl is-active --quiet pi-ambient-synth-midi.service 2>/dev/null; then
    journalctl -u pi-ambient-synth-midi -n 20 --no-pager --since "3 min ago" 2>/dev/null \
      | grep -q 'MIDI bridge running' \
      || fail "pi-ambient-synth-midi started but bridge log missing"
    log "pi-ambient-synth-midi active"
  else
    log "WARN: pi-ambient-synth-midi not active (simulate_midi_e2e still validates OSC path)"
  fi
  return 0
}

check_midi_paths() {
  [[ -x "$PY" ]] || fail "venv python missing"
  "$PY" "$INSTALL_DIR/scripts/simulate_midi_e2e.py" || fail "simulate_midi_e2e.py failed"
}

check_status_page() {
  local phase="$1"
  [[ -x "$PY" ]] || fail "venv python missing"
  export MARKER_DIR
  "$PY" "$INSTALL_DIR/scripts/assert_monitor_status.py" --phase "$phase" \
    || fail "status page assertions failed (--phase $phase)"
}

log "=== pi e2e verify ==="
check_sc_source
sudo systemctl reset-failed pi-ambient-synth.service pi-ambient-synth-midi.service 2>/dev/null || true
sleep 3
check_status_page wait
check_supercollider
check_jack_playback
check_osc_beep
check_status_page post-osc
check_synth_service || true
check_midi_paths
check_status_page final
check_audible
pass
