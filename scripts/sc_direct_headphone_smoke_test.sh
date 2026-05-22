#!/usr/bin/env bash
# Phase 1: prove SuperCollider → Pi 3.5 mm jack with zero project stack.
# Does NOT use project engine, OSC, MIDI, monitor, e-ink, ALSA blips, or ensure_jack_playback.sh.
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
SCD="${ROOT}/synth/sc_direct_smoke.scd"
BIND="${ROOT}/synth/pi_bind_port.scd"
HEADLESS_CFG="${ROOT}/config/pi_sclang_headless.yaml"

SCLANG_WRAPPER=()
if command -v xvfb-run >/dev/null 2>&1; then
  SCLANG_WRAPPER=(xvfb-run -a)
fi
PORT="${SC_SYNTH_PORT:-57110}"
RATE="${SC_SAMPLE_RATE:-48000}"
LOG="/tmp/sc-direct-smoke.log"
SC_LOG="/tmp/sc-direct-sclang.log"
JACK_PERIOD="${SC_JACK_PERIOD:-4096}"

log() { echo "$(date -Iseconds) [sc-direct-smoke] $*"; }

# Broken ~/.config/SuperCollider/sclang.yaml causes yaml-cpp errors on Pi.
mkdir -p "${HOME:-/home/pi}/.config/SuperCollider"
printf '%s\n' '# pi-ambient-synth smoke (avoid broken yaml-cpp parse)' \
  >"${HOME:-/home/pi}/.config/SuperCollider/sclang.yaml"

log "stop project services"
stop_ok=1
for unit in pi-ambient-synth pi-ambient-synth-midi pi-ambient-synth-monitor supercollider; do
  if systemctl is-active --quiet "${unit}.service" 2>/dev/null; then
    if sudo -n systemctl stop "${unit}.service" 2>/dev/null; then
      log "stopped ${unit}.service"
    else
      log "ERROR: ${unit}.service still active — run with sudo (see scripts/run_sc_direct_smoke_on_pi.sh)"
      stop_ok=0
    fi
  fi
done
if [[ "$stop_ok" != "1" ]]; then
  exit 1
fi
sleep 2
for unit in supercollider pi-ambient-synth pi-ambient-synth-midi; do
  if systemctl is-active --quiet "${unit}.service" 2>/dev/null; then
    log "WARN: ${unit}.service still active — force stop"
    sudo -n systemctl stop "${unit}.service" 2>/dev/null || true
  fi
done
pkill -x sclang 2>/dev/null || true
pkill -x scsynth 2>/dev/null || true
sleep 2
for unit in supercollider pi-ambient-synth pi-ambient-synth-midi; do
  if systemctl is-active --quiet "${unit}.service" 2>/dev/null; then
    log "ERROR: ${unit}.service still active — run: ./scripts/run_sc_direct_smoke_on_pi.sh (masks units with sudo)"
    exit 1
  fi
done
if pgrep -x sclang >/dev/null || pgrep -x scsynth >/dev/null; then
  log "ERROR: stray sclang/scsynth still running after stop"
  exit 1
fi

log "kill stale audio processes"
if pgrep -x sclang >/dev/null; then
  log "WARN: another sclang is running — stopping it (production must be masked/stopped)"
  pkill -x sclang 2>/dev/null || true
  sleep 1
fi
pkill -f scsynth 2>/dev/null || true
pkill -f sclang 2>/dev/null || true
pkill -x jackd 2>/dev/null || true
pkill -9 -f scsynth 2>/dev/null || true
pkill -9 -x jackd 2>/dev/null || true
sleep 1
rm -f /dev/shm/jack-* /dev/shm/jackdmp* /dev/shm/sem.jack* 2>/dev/null || true

log "headphone output (card 0)"
if command -v raspi-config >/dev/null 2>&1; then
  sudo raspi-config nonint do_audio 1 2>/dev/null || true
fi
amixer -c 0 set PCM 90% unmute 2>/dev/null || true

log "start jackd (alsa plughw:0,0)"
: >"$LOG"
nohup jackd -dalsa -dplughw:0,0 -r"$RATE" -p"$JACK_PERIOD" -n3 -i0 -o2 >>"$LOG" 2>&1 &
JACK_PID=$!
disown "$JACK_PID" 2>/dev/null || true
for _ in $(seq 1 40); do
  pgrep -x jackd >/dev/null && break
  sleep 0.25
done
pgrep -x jackd >/dev/null || { log "FAIL: jackd did not start"; exit 1; }

log "start scsynth JACK client (port $PORT)"
export JACK_NO_START_SERVER=1
export JACK_NO_AUDIO_RESERVATION=1
export SC_JACK_DEFAULT_OUTPUTS="system:playback_1,system:playback_2"
nohup scsynth -u "$PORT" -a 16 -i 2 -o 2 -R "$RATE" -l 1 >>"$LOG" 2>&1 &
SC_PID=$!
disown "$SC_PID" 2>/dev/null || true
for _ in $(seq 1 40); do
  pgrep -x scsynth >/dev/null && break
  sleep 0.25
done
pgrep -x scsynth >/dev/null || { log "FAIL: scsynth did not start"; tail -20 "$LOG"; exit 1; }
sleep 3

log "verify SuperCollider → system:playback (scsynth usually auto-connects)"
if jack_lsp -c 2>/dev/null | grep -q 'SuperCollider:out_1'; then
  log "jack route already present (scsynth auto-connect)"
else
  log "manual jack_connect fallback"
  OUT1="$(jack_lsp 2>/dev/null | grep -E 'SuperCollider:out_1$' | head -1 || true)"
  [[ -n "$OUT1" ]] && jack_connect "$OUT1" system:playback_1 2>/dev/null || true
  [[ -n "$OUT1" ]] && jack_connect "$OUT1" system:playback_2 2>/dev/null || true
fi
jack_lsp -c 2>/dev/null | grep -E 'SuperCollider|playback' | head -10 || true
pgrep -x jackd || true
pgrep -x scsynth || true
sleep 2

if [[ ! -f "$BIND" ]]; then
  log "WARN: missing $BIND — OSC notify may fail"
fi
log "run minimal sclang smoke (440 Hz 2s, then chord 4s) — one sclang process only"
export SC_SYNTH_PORT="$PORT"
export HOME="${HOME:-/home/pi}"
export QT_QPA_PLATFORM=offscreen
unset DISPLAY
unset QTWEBENGINE_CHROMIUM_FLAGS
export SC_SYNTHDEF_PATH="${SC_SYNTHDEF_PATH:-}"
export JACK_NO_START_SERVER=1
export JACK_NO_AUDIO_RESERVATION=1
export SC_JACK_DEFAULT_OUTPUTS="system:playback_1,system:playback_2"
# sclang must stay alive while fork plays ~6s audio; headless .scd cannot block on Condition.wait.
SC_SMOKE_PLAY_SEC="${SC_SMOKE_PLAY_SEC:-14}"
SC_SMOKE_COMPILE_TIMEOUT_SEC="${SC_SMOKE_COMPILE_TIMEOUT_SEC:-420}"
: >"$SC_LOG"
log "run sclang via ${SCLANG_WRAPPER[*]:-direct} (blocking; Pi first compile ~60–120s)"
if timeout "$SC_SMOKE_COMPILE_TIMEOUT_SEC" "${SCLANG_WRAPPER[@]}" /usr/bin/sclang -l "$BIND" "$SCD" </dev/null >>"$SC_LOG" 2>&1; then
  log "sclang exited cleanly"
else
  log "WARN: sclang exited non-zero or timed out (see $SC_LOG)"
fi
if grep -q 'sc_direct_smoke: done' "$SC_LOG" 2>/dev/null; then
  log "sclang smoke completed tone + chord"
else
  log "WARN: sc_direct_smoke may not have finished"
  tail -30 "$SC_LOG" >&2 || true
fi
sleep 2
log "cleanup smoke processes"
kill "$SC_PID" 2>/dev/null || true
kill "$JACK_PID" 2>/dev/null || true
pkill -x sclang 2>/dev/null || true
sleep 1
pkill -x scsynth 2>/dev/null || true
pkill -x jackd 2>/dev/null || true
sleep 1

echo ""
echo "SC_DIRECT_AUDIO_HEARD_QUESTION"
echo "Listen on the Pi 3.5 mm headphone jack NOW (test just finished)."
echo "  A) Heard 440 Hz tone (~2 s)?"
echo "  B) Heard warm pad chord (~4 s)?"
echo "  C) Silence?"
echo ""
echo "Reply: tone / chord / silence"
echo "Logs: $LOG (jack/scsynth)  $SC_LOG (sclang)"
echo ""
echo "If silence: stop — do not debug MIDI, OSC, monitor, or e-ink until direct SC works."
echo "If tone or chord heard: proceed to minimal_ambient_engine + proof_note."
