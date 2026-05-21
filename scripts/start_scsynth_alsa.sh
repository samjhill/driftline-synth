#!/usr/bin/env bash
# Start scsynth for Pi Ambient Synth (tries native ALSA and fallbacks; logs each attempt).
set -euo pipefail

PORT="${SC_SYNTH_PORT:-57110}"
RATE="${SC_SAMPLE_RATE:-48000}"
LOG="${SCSYNTH_START_LOG:-/tmp/scsynth-alsa-start.log}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
DRIVER_FILE="$MARKER_DIR/scsynth_audio.conf"

# hw:0 — commas in hw:0,0 break JACK client name "0,0".
map_hw() {
  case "${1:-}" in
    "" | hw:0 | hw:0,0 | plughw:0,0) echo hw:0 ;;
    plughw:*) echo "${1#plughw:}" | cut -d, -f1 ;;
    *) echo "${1%%,*}" ;;
  esac
}

HWDEV="$(map_hw "${SC_SYNTH_HW:-${SC_AUDIO_DEVICE:-hw:0}}")"

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
  local pid="$1" i
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
  local driver="$1" hw="$2" pid
  pkill -x scsynth 2>/dev/null || true
  sleep 0.35
  {
    echo "=== $(date -Iseconds) driver=${driver:-<default>} hw=$hw port=$PORT rate=$RATE ==="
    if [[ -z "$driver" ]]; then
      echo "cmd: scsynth -u $PORT -i 2 -o 2 -H $hw -r $RATE"
      scsynth -u "$PORT" -i 2 -o 2 -H "$hw" -r "$RATE"
    else
      echo "cmd: scsynth -u $PORT -i 2 -o 2 -a $driver -H $hw -r $RATE"
      scsynth -u "$PORT" -i 2 -o 2 -a "$driver" -H "$hw" -r "$RATE"
    fi
  } >>"$LOG" 2>&1 &
  pid=$!
  if wait_scsynth "$pid"; then
    mkdir -p "$MARKER_DIR"
    {
      echo "SC_SYNTH_DRIVER=${driver}"
      echo "SC_SYNTH_HW=$hw"
      echo "SC_SYNTH_PORT=$PORT"
    } >"$DRIVER_FILE"
    echo "scsynth ready: driver=${driver:-default} hw=$hw port=$PORT pid=$pid"
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

echo "scsynth: $(command -v scsynth) — $(scsynth -v 2>&1 | head -1 || true)"
scsynth --help 2>&1 | head -20 >>"$LOG" || true

# driver|hw — empty driver = omit -a (build default)
ATTEMPTS=(
  "alsa|${HWDEV}"
  "jack|${HWDEV}"
  "|${HWDEV}"
  "pulseaudio|${HWDEV}"
  "alsa|hw:0,0"
  "jack|hw:0,0"
  "dummy|${HWDEV}"
)

for spec in "${ATTEMPTS[@]}"; do
  driver="${spec%%|*}"
  hw="${spec#*|}"
  if try_start "$driver" "$hw"; then
    exit 0
  fi
done

echo "ERROR: all scsynth start attempts failed" >&2
echo "Log: $LOG" >&2
echo "Last log lines:" >&2
tail -25 "$LOG" >&2 || true
echo "Try: aplay -l ; scsynth --help 2>&1 | head -30" >&2
exit 1
