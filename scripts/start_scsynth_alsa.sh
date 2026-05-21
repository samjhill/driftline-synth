#!/usr/bin/env bash
# Start scsynth with native ALSA (no embedded JACK — avoids JackTemporaryException on Pi).
# Used by run_sclang_engine.sh and engine_smoke_pi.sh before sclang loads ambient_engine.scd.
set -euo pipefail

PORT="${SC_SYNTH_PORT:-57110}"
RATE="${SC_SAMPLE_RATE:-48000}"
# hw:0 — commas in hw:0,0 become JACK client name "0,0" and break audio.
HWDEV="${SC_SYNTH_HW:-hw:0}"
# User override may be plughw:0,0; map to hw:0 for scsynth -H.
case "$HWDEV" in
  plughw:0,0 | hw:0,0) HWDEV=hw:0 ;;
esac
if [[ -n "${SC_AUDIO_DEVICE:-}" ]]; then
  case "$SC_AUDIO_DEVICE" in
    plughw:0,0 | hw:0,0) HWDEV=hw:0 ;;
    *) HWDEV="${SC_AUDIO_DEVICE%%,*}" ;;
  esac
fi

pick_driver() {
  local help
  help="$(scsynth --help 2>&1 || true)"
  if grep -qiE 'audio.*alsa|alsa.*audio' <<<"$help"; then
    echo alsa
    return 0
  fi
  echo ALSA
}

# Always replace any prior scsynth (often a crashed JACK instance with client name 0,0).
pkill -x scsynth 2>/dev/null || true
sleep 0.35

DRIVER="$(pick_driver)"
LOG="${SCSYNTH_START_LOG:-/tmp/scsynth-alsa-start.log}"
echo "Starting scsynth: -a $DRIVER -H $HWDEV -r $RATE -u $PORT (log $LOG)"
scsynth -u "$PORT" -i 2 -o 2 -a "$DRIVER" -H "$HWDEV" -r "$RATE" >>"$LOG" 2>&1 &
SYNTH_PID=$!

for _ in $(seq 1 50); do
  if command -v nc >/dev/null && nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
    echo "scsynth ready on port $PORT (pid $SYNTH_PID)"
    exit 0
  fi
  if ! kill -0 "$SYNTH_PID" 2>/dev/null; then
    echo "ERROR: scsynth exited during startup" >&2
    exit 1
  fi
  sleep 0.2
done

echo "WARN: scsynth port $PORT not confirmed (pid $SYNTH_PID still running)" >&2
