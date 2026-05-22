#!/usr/bin/env bash
# Step 4: SuperCollider through JACK using the same settings as jack_headphone_smoke_test.sh
# Run only after user confirms ALSA + JACK tests were audible.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
# shellcheck source=scripts/lib/audio_isolation.sh
source "$INSTALL_DIR/scripts/lib/audio_isolation.sh"

MARKER="$(audio_iso_marker_dir)/jack-known-good.env"
SCD="${INSTALL_DIR}/synth/sc_direct_smoke.scd"
BIND="${INSTALL_DIR}/synth/pi_bind_port.scd"
PORT="${SC_SYNTH_PORT:-57110}"
LOG="/tmp/sc-jack-known-good-jack.log"
SC_LOG="/tmp/sc-jack-known-good-sclang.log"
SC_TIMEOUT_SEC="${SC_JACK_TEST_TIMEOUT_SEC:-420}"

SCLANG_WRAPPER=()
if command -v xvfb-run >/dev/null 2>&1; then
  SCLANG_WRAPPER=(xvfb-run -a)
fi

log() { echo "$(date -Iseconds) [sc-jack-kg] $*"; }

if [[ ! -f "$MARKER" ]]; then
  log "ERROR: missing $MARKER — run scripts/jack_headphone_smoke_test.sh first (and confirm JACK heard)"
  exit 1
fi
# shellcheck source=/dev/null
source "$MARKER"

log "using JACK settings from $MARKER (dev=$JACK_ALSA_DEV rate=$JACK_RATE)"

log "stop project services"
audio_iso_stop_project_services || exit 1
audio_iso_kill_audio_processes
audio_iso_force_headphone_mixer

mkdir -p "${HOME:-/home/pi}/.config/SuperCollider"
printf '%s\n' '# pi-ambient-synth isolation test' >"${HOME:-/home/pi}/.config/SuperCollider/sclang.yaml"

: >"$LOG"
: >"$SC_LOG"

log "start jackd (known-good device)"
nohup jackd -dalsa -d"$JACK_ALSA_DEV" -r"$JACK_RATE" -p"$JACK_PERIOD" -n"$JACK_NPERIODS" -i0 -o2 >>"$LOG" 2>&1 &
for _ in $(seq 1 40); do pgrep -x jackd >/dev/null && break; sleep 0.25; done
pgrep -x jackd >/dev/null || { log "FAIL: jackd"; tail -20 "$LOG"; exit 1; }
sleep 2

export JACK_NO_START_SERVER=1
export JACK_NO_AUDIO_RESERVATION=1
log "start scsynth port=$PORT"
nohup scsynth -u "$PORT" -a 16 -i 2 -o 2 -R "$JACK_RATE" -l 1 >>"$LOG" 2>&1 &
for _ in $(seq 1 40); do pgrep -x scsynth >/dev/null && break; sleep 0.25; done
pgrep -x scsynth >/dev/null || { log "FAIL: scsynth"; tail -20 "$LOG"; exit 1; }
sleep 3

if ! jack_lsp -c 2>/dev/null | grep -q 'SuperCollider:out_1'; then
  OUT1="$(jack_lsp 2>/dev/null | grep -E 'SuperCollider:out_1$' | head -1 || true)"
  [[ -n "$OUT1" ]] && jack_connect "$OUT1" system:playback_1 2>/dev/null || true
  [[ -n "$OUT1" ]] && jack_connect "$OUT1" system:playback_2 2>/dev/null || true
fi

log "run sclang smoke (logs are NOT proof of sound — you must listen)"
export SC_SYNTH_PORT="$PORT"
export QT_QPA_PLATFORM=offscreen
unset DISPLAY
export JACK_NO_START_SERVER=1

if ! timeout "$SC_TIMEOUT_SEC" "${SCLANG_WRAPPER[@]}" /usr/bin/sclang -l "$BIND" "$SCD" </dev/null >>"$SC_LOG" 2>&1; then
  log "WARN: sclang exited non-zero or timed out (see $SC_LOG)"
fi

pkill -x sclang 2>/dev/null || true
sleep 1
pkill -x scsynth 2>/dev/null || true
pkill -x jackd 2>/dev/null || true

echo ""
echo "SC_JACK_KNOWN_GOOD_TEST_DONE_USER_MUST_CONFIRM"
echo "Listen on the Pi 3.5 mm headphone jack."
echo "  Heard 440 Hz tone then pad chord from SuperCollider?"
echo "  Silence?"
echo ""
echo "Reply: heard / silence"
echo "Logs: $LOG (jack/scsynth)  $SC_LOG (sclang)"
echo ""
echo "Log lines like 'sc_direct_smoke: done' are NOT proof — only your ears count."
echo "If silence: hardware/JACK may work but scsynth/sclang path does not — still no MIDI/OSC/e-ink work."
