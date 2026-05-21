#!/usr/bin/env bash
# Pi SC 3.13: scsynth -H still embeds jackdmp (see /tmp/scsynth-alsa-start.log).
# Start a stable jackd on ALSA first, then scsynth as a JACK client (no -H).
set -euo pipefail

PORT="${SC_SYNTH_PORT:-57110}"
RATE="${SC_SAMPLE_RATE:-48000}"
LOG="${SCSYNTH_START_LOG:-/tmp/scsynth-alsa-start.log}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
DRIVER_FILE="$MARKER_DIR/scsynth_audio.conf"
JACK_PERIOD="${SC_JACK_PERIOD:-2048}"
JACK_NPERIODS="${SC_JACK_NPERIODS:-3}"

# jackd -dalsa wants hw:0 or hw:0,0 (not plughw:)
jack_alsa_dev() {
  local d="${1:-hw:0,0}"
  d="${d#plughw:}"
  d="${d#hw:}"
  echo "hw:${d}"
}

jack_candidates() {
  local base="${SC_JACK_DEVICE:-${SC_AUDIO_DEVICE:-hw:0,0}}"
  case "$base" in
    hw:0 | hw:0,0 | plughw:0,0) echo -e "hw:0,0\nhw:0" ;;
    *) echo "$(jack_alsa_dev "$base")" ;;
  esac
}

# scsynth OSC is UDP on 57110 (TCP checks falsely fail and we SIGTERM jackd).
port_open() {
  if command -v ss >/dev/null; then
    if ss -uln 2>/dev/null | grep -qE ":${PORT}[[:space:]]"; then
      return 0
    fi
    if ss -tln 2>/dev/null | grep -qE ":${PORT}[[:space:]]"; then
      return 0
    fi
  fi
  if command -v nc >/dev/null; then
    if nc -u -z -w1 127.0.0.1 "$PORT" 2>/dev/null; then
      return 0
    fi
    if nc -z -w1 127.0.0.1 "$PORT" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

scsynth_ready() {
  pgrep -x scsynth >/dev/null || return 1
  jack_ready || return 1
  if jack_lsp 2>/dev/null | grep -qi supercollider; then
    return 0
  fi
  return 1
}

scsynth_up() {
  port_open || scsynth_ready
}

jack_ready() {
  if command -v jack_lsp >/dev/null && jack_lsp >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

stop_audio_stack() {
  pkill -x scsynth 2>/dev/null || true
  pkill -x jackd 2>/dev/null || true
  sleep 0.5
}

wait_jack() {
  local pid="$1"
  local i
  for i in $(seq 1 80); do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
    if jack_ready; then
      return 0
    fi
    sleep 0.15
  done
  return 2
}

wait_scsynth() {
  local pid="$1"
  local i
  for i in $(seq 1 60); do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
    if scsynth_up; then
      break
    fi
    sleep 0.2
  done
  if ! scsynth_up; then
    return 2
  fi
  # Hold a few seconds — catch post-ready JackTemporaryException / false-negative port checks.
  for i in $(seq 1 15); do
    sleep 0.2
    if ! kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
    if ! scsynth_up; then
      return 1
    fi
  done
  return 0
}

start_jack() {
  local dev="$1"
  local pid
  stop_audio_stack
  {
    echo "=== $(date -Iseconds) jackd dev=$dev rate=$RATE period=$JACK_PERIOD n=$JACK_NPERIODS ==="
    echo "cmd: jackd -dalsa -d$dev -r$RATE -p$JACK_PERIOD -n$JACK_NPERIODS -i0 -o2"
    # Playback-only (-i0); large buffer; no -R (RT often denied on headless Pi).
    jackd -dalsa -d"$dev" -r"$RATE" -p"$JACK_PERIOD" -n"$JACK_NPERIODS" -i0 -o2
  } >>"$LOG" 2>&1 &
  pid=$!
  if wait_jack "$pid"; then
    echo "jackd ready: dev=$dev pid=$pid"
    return 0
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  return 1
}

start_scsynth_client() {
  local dev="$1"
  local pid
  export JACK_NO_START_SERVER=1
  {
    echo "=== $(date -Iseconds) scsynth JACK client dev=$dev port=$PORT rate=$RATE ==="
    echo "cmd: scsynth -u $PORT -i 2 -o 2 -R $RATE -l 0  (no -H; jackd owns ALSA)"
    scsynth -u "$PORT" -i 2 -o 2 -R "$RATE" -l 0
  } >>"$LOG" 2>&1 &
  pid=$!
  if wait_scsynth "$pid"; then
    mkdir -p "$MARKER_DIR"
    {
      echo "SC_SYNTH_DRIVER=jack"
      echo "SC_JACK_DEVICE=$dev"
      echo "SC_SYNTH_PORT=$PORT"
      echo "SC_SYNTH_RATE=$RATE"
      echo "SC_JACK_PERIOD=$JACK_PERIOD"
      echo "SC_JACK_NPERIODS=$JACK_NPERIODS"
    } >"$DRIVER_FILE"
    echo "scsynth ready: jack+alsa dev=$dev port=$PORT pid=$pid"
    return 0
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  return 1
}

try_stack() {
  local dev="$1"
  if start_jack "$dev" && start_scsynth_client "$dev"; then
    return 0
  fi
  stop_audio_stack
  return 1
}

mkdir -p "$(dirname "$LOG")"
: >"$LOG"

echo "scsynth: $(scsynth -v 2>&1 | head -1 || true)"
echo "jackd: $(command -v jackd || echo missing)"
echo "Note: Pi SC 3.13 -H embeds JACK; use external jackd + scsynth client" | tee -a "$LOG"

while IFS= read -r dev; do
  [[ -n "$dev" ]] || continue
  if try_stack "$dev"; then
    exit 0
  fi
done < <(jack_candidates)

echo "ERROR: jackd+scsynth did not stay up on port $PORT" >&2
echo "Log: $LOG" >&2
echo "Last log lines:" >&2
tail -40 "$LOG" >&2 || true
echo "Try: fuser -v /dev/snd/* ; aplay -D hw:0,0 /usr/share/sounds/alsa/Front_Center.wav" >&2
exit 1
