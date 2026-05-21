#!/usr/bin/env bash
# Start scsynth for Pi Ambient Synth (SC 3.13 on Pi: -H device, -R rate; no -a flag).
set -euo pipefail

PORT="${SC_SYNTH_PORT:-57110}"
RATE="${SC_SAMPLE_RATE:-48000}"
LOG="${SCSYNTH_START_LOG:-/tmp/scsynth-alsa-start.log}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
DRIVER_FILE="$MARKER_DIR/scsynth_audio.conf"

# Comma in hw:0,0 breaks some builds; try several ALSA names.
hw_candidates() {
  local base="${SC_SYNTH_HW:-${SC_AUDIO_DEVICE:-hw:0}}"
  case "$base" in
    hw:0 | hw:0,0 | plughw:0,0) echo -e "hw:0\nhw:0,0\nplughw:0,0" ;;
    *) echo "$base" ;;
  esac
}

port_open() {
  if command -v ss >/dev/null && ss -tln 2>/dev/null | grep -q ":${PORT} "; then
    return 0
  fi
  if command -v nc >/dev/null && nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
    return 0
  fi
  return 1
}

wait_scsynth() {
  local pid="$1"
  local i
  for i in $(seq 1 60); do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
    if port_open; then
      return 0
    fi
    sleep 0.2
  done
  return 2
}

try_start() {
  local hw="$1" extra="${2:-}"
  local pid
  pkill -x scsynth 2>/dev/null || true
  sleep 0.35
  {
    echo "=== $(date -Iseconds) hw=$hw port=$PORT rate=$RATE extra=$extra ==="
    echo "cmd: scsynth -u $PORT -i 2 -o 2 -H $hw -R $RATE $extra"
    # SC 3.13 on Raspberry Pi OS: no -a audio-driver flag (invalid args print --help and exit).
    # shellcheck disable=SC2086
    scsynth -u "$PORT" -i 2 -o 2 -H "$hw" -R "$RATE" $extra
  } >>"$LOG" 2>&1 &
  pid=$!
  if wait_scsynth "$pid"; then
    mkdir -p "$MARKER_DIR"
    {
      echo "SC_SYNTH_HW=$hw"
      echo "SC_SYNTH_PORT=$PORT"
      echo "SC_SYNTH_RATE=$RATE"
    } >"$DRIVER_FILE"
    echo "scsynth ready: hw=$hw port=$PORT pid=$pid"
    return 0
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  return 1
}

mkdir -p "$(dirname "$LOG")"
: >"$LOG"

echo "scsynth: $(scsynth -v 2>&1 | head -1 || true)"
echo "Note: Pi SC 3.13 uses -H / -R (no -a driver flag)" | tee -a "$LOG"

while IFS= read -r hw; do
  [[ -n "$hw" ]] || continue
  for extra in "" "-l 0"; do
    if try_start "$hw" "$extra"; then
      exit 0
    fi
  done
done < <(hw_candidates)

echo "ERROR: scsynth did not stay up on port $PORT" >&2
echo "Log: $LOG" >&2
echo "Last log lines:" >&2
tail -30 "$LOG" >&2 || true
echo "Check: aplay -l ; aplay -D hw:0 /usr/share/sounds/alsa/Front_Center.wav" >&2
exit 1
