#!/usr/bin/env bash
# Pi SC 3.13: external jackd + scsynth JACK client (no scsynth -H — that embeds jackdmp).
set -euo pipefail

ulimit -l unlimited 2>/dev/null || true
if command -v prlimit >/dev/null 2>&1; then
  prlimit --pid="$$" --memlock=unlimited 2>/dev/null || true
fi

PORT="${SC_SYNTH_PORT:-57110}"
RATE="${SC_SAMPLE_RATE:-48000}"
LOG="${SCSYNTH_START_LOG:-/tmp/scsynth-alsa-start.log}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
DRIVER_FILE="$MARKER_DIR/scsynth_audio.conf"
ALSA_BUF="${SC_ALSA_BUFFER:-4096}"
ALSA_IN="${SC_ALSA_INPUTS:-0}"
ALSA_OUT="${SC_ALSA_OUTPUTS:-2}"
USE_NATIVE_ALSA="${SC_USE_NATIVE_ALSA:-0}"
JACK_PERIOD="${SC_JACK_PERIOD:-4096}"
JACK_NPERIODS="${SC_JACK_NPERIODS:-3}"
SCSYNTH_JACK_SETTLE_SEC="${SCSYNTH_JACK_SETTLE_SEC:-4.0}"
SCSYNTH_STABLE_SEC="${SCSYNTH_STABLE_SEC:-3}"

jack_alsa_dev() {
  local d="${1:-hw:0,0}"
  d="${d#plughw:}"
  d="${d#hw:}"
  echo "hw:${d}"
}

alsa_candidates() {
  local base="${SC_AUDIO_DEVICE:-hw:0,0}"
  case "$base" in
    hw:0,0 | plughw:0,0) printf '%s\n' "hw:0,0" "plughw:0,0" ;;
    hw:0 | plughw:0) printf '%s\n' "hw:0" "plughw:0" ;;
    *) printf '%s\n' "$base" ;;
  esac
}

jack_candidates() {
  local base="${SC_JACK_DEVICE:-${SC_AUDIO_DEVICE:-hw:0,0}}"
  case "$base" in
    hw:0,0 | plughw:0,0) echo "hw:0,0" ;;
    hw:0) echo "hw:0" ;;
    *) echo "$(jack_alsa_dev "$base")" ;;
  esac
}

port_open() {
  if command -v ss >/dev/null; then
    ss -uln 2>/dev/null | grep -qE ":${PORT}[[:space:]]" && return 0
    ss -tln 2>/dev/null | grep -qE ":${PORT}[[:space:]]" && return 0
  fi
  if command -v nc >/dev/null; then
    nc -u -z -w1 127.0.0.1 "$PORT" 2>/dev/null && return 0
    nc -z -w1 127.0.0.1 "$PORT" 2>/dev/null && return 0
  fi
  return 1
}

scsynth_ready() {
  pgrep -x scsynth >/dev/null || return 1
  port_open
}

connect_jack_playback() {
  local root="${PI_AMBIENT_ROOT:-/home/pi/pi-ambient-synth}"
  if [[ -x "$root/scripts/ensure_jack_playback.sh" ]]; then
    "$root/scripts/ensure_jack_playback.sh" || true
    return 0
  fi
  command -v jack_lsp >/dev/null || return 0
  command -v jack_connect >/dev/null || return 0
  local out1 out2
  out1="$(jack_lsp 2>/dev/null | grep -E 'SuperCollider:out_1$' | head -1 || true)"
  out2="$(jack_lsp 2>/dev/null | grep -E 'SuperCollider:out_2$' | head -1 || true)"
  [[ -n "$out1" ]] && jack_connect "$out1" system:playback_1 2>/dev/null || true
  [[ -n "$out2" ]] && jack_connect "$out2" system:playback_2 2>/dev/null || true
}

jack_ready() {
  pgrep -x jackd >/dev/null || return 1
  ls /dev/shm/jack* 1>/dev/null 2>&1
}

stop_audio_stack() {
  pkill -x scsynth 2>/dev/null || true
  pkill -x jackd 2>/dev/null || true
  local i
  for i in $(seq 1 30); do
    pgrep -x scsynth >/dev/null && continue
    pgrep -x jackd >/dev/null && continue
    break
  done
  pkill -9 -x scsynth 2>/dev/null || true
  pkill -9 -x jackd 2>/dev/null || true
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${PORT}/udp" 2>/dev/null || true
    fuser -k "${PORT}/tcp" 2>/dev/null || true
  fi
  for i in $(seq 1 40); do
    port_open || break
    sleep 0.15
  done
  sleep 0.8
  rm -f /dev/shm/jack-* /dev/shm/jackdmp* /dev/shm/sem.jack* 2>/dev/null || true
}

wait_jack() {
  local pid="$1" i
  sleep 1.5
  for i in $(seq 1 50); do
    kill -0 "$pid" 2>/dev/null || return 1
    jack_ready && return 0
    sleep 0.2
  done
  kill -0 "$pid" 2>/dev/null
}

wait_scsynth() {
  local pid="$1" i stable=0 need
  need="$(python3 -c "print(max(1, int(float('${SCSYNTH_STABLE_SEC}') / 0.25)))" 2>/dev/null || echo 12)"
  for i in $(seq 1 80); do
    kill -0 "$pid" 2>/dev/null || return 1
    if scsynth_ready; then
      stable=$((stable + 1))
      if [[ "$stable" -ge "$need" ]]; then
        return 0
      fi
    else
      stable=0
    fi
    sleep 0.25
  done
  return 1
}

start_jack() {
  local dev="$1" pid
  {
    echo "=== $(date -Iseconds) jackd dev=$dev rate=$RATE period=$JACK_PERIOD n=$JACK_NPERIODS ==="
    echo "cmd: jackd -m -P75 -dalsa -d$dev -r$RATE -p$JACK_PERIOD -n$JACK_NPERIODS -i0 -o2"
    jackd -m -P75 -dalsa -d"$dev" -r"$RATE" -p"$JACK_PERIOD" -n"$JACK_NPERIODS" -i0 -o2
  } >>"$LOG" 2>&1 &
  pid=$!
  if wait_jack "$pid"; then
    echo "jackd ready: dev=$dev pid=$pid"
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 1
}

start_scsynth_native_alsa() {
  local dev="$1" pid
  pkill -x jackd 2>/dev/null || true
  pkill -9 -x jackd 2>/dev/null || true
  rm -f /dev/shm/jack-* /dev/shm/jackdmp* /dev/shm/sem.jack* 2>/dev/null || true
  pkill -9 -x scsynth 2>/dev/null || true
  for _ in $(seq 1 30); do
    port_open || break
    sleep 0.15
  done
  sleep 0.5
  {
    echo "=== $(date -Iseconds) scsynth native ALSA dev=$dev port=$PORT buf=$ALSA_BUF ==="
    echo "cmd: scsynth -u $PORT -a alsa -H $dev -i $ALSA_IN -o $ALSA_OUT -R $RATE -l 1"
    scsynth -u "$PORT" -a alsa -H "$dev" -i "$ALSA_IN" -o "$ALSA_OUT" -R "$RATE" -l 1
  } >>"$LOG" 2>&1 &
  pid=$!
  if wait_scsynth "$pid"; then
    mkdir -p "$MARKER_DIR"
    {
      echo "SC_SYNTH_DRIVER=alsa"
      echo "SC_ALSA_DEVICE=$dev"
      echo "SC_SYNTH_PORT=$PORT"
      echo "SC_SYNTH_RATE=$RATE"
      echo "SC_ALSA_BUFFER=$ALSA_BUF"
    } >"$DRIVER_FILE"
    echo "scsynth ready: native ALSA dev=$dev port=$PORT pid=$pid"
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 1
}

start_scsynth_client() {
  local dev="$1" pid
  export JACK_NO_START_SERVER=1

  jack_ready || return 1
  sleep "$SCSYNTH_JACK_SETTLE_SEC"

  pkill -9 -x scsynth 2>/dev/null || true
  for _ in $(seq 1 30); do
    port_open || break
    sleep 0.15
  done
  sleep 0.5

  # -l is language; do not pass -z (also language on Pi SC 3.13, not zeroconf off).
  {
    echo "=== $(date -Iseconds) scsynth JACK client dev=$dev port=$PORT ==="
    echo "cmd: scsynth -u $PORT -i 2 -o 2 -R $RATE -l 1"
    scsynth -u "$PORT" -i 2 -o 2 -R "$RATE" -l 1
  } >>"$LOG" 2>&1 &
  pid=$!
  if wait_scsynth "$pid"; then
    connect_jack_playback
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
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 1
}

try_stack() {
  local dev="$1"
  start_jack "$dev" || return 1
  if [[ "${SC_WAIT_FOR_BOOT:-}" == "1" ]]; then
    mkdir -p "$MARKER_DIR"
    {
      echo "SC_SYNTH_DRIVER=jack+waitForBoot"
      echo "SC_JACK_DEVICE=$dev"
      echo "SC_SYNTH_PORT=$PORT"
      echo "SC_SYNTH_RATE=$RATE"
      echo "SC_JACK_PERIOD=$JACK_PERIOD"
      echo "SC_JACK_NPERIODS=$JACK_NPERIODS"
    } >"$DRIVER_FILE"
    echo "jackd ready for s.waitForBoot dev=$dev"
    return 0
  fi
  start_scsynth_client "$dev"
}

mkdir -p "$(dirname "$LOG")"
: >"$LOG"

echo "scsynth: $(scsynth -v 2>&1 | head -1 || true)"
echo "jackd: $(command -v jackd || echo missing)"
if [[ "$USE_NATIVE_ALSA" == "1" ]]; then
  echo "Note: Pi — native ALSA scsynth (no jackd); JACK fallback if this fails" | tee -a "$LOG"
else
  echo "Note: Pi SC 3.13 — external jackd + scsynth JACK client" | tee -a "$LOG"
fi

stop_audio_stack

if [[ "$USE_NATIVE_ALSA" == "1" ]]; then
  while IFS= read -r dev; do
    [[ -n "$dev" ]] || continue
    if start_scsynth_native_alsa "$dev"; then
      exit 0
    fi
    echo "native ALSA failed for $dev" >>"$LOG"
    stop_audio_stack
  done < <(alsa_candidates)
  if [[ "${SC_NATIVE_ALSA_ONLY:-}" == "1" ]]; then
    echo "ERROR: native ALSA scsynth did not stay up on port $PORT" >&2
    tail -40 "$LOG" >&2 || true
    exit 1
  fi
  echo "WARN: native ALSA failed — trying JACK stack" | tee -a "$LOG"
fi

if [[ "${SC_JACK_ALREADY:-}" == "1" ]]; then
  dev="$(jack_candidates | head -1)"
  [[ -n "$dev" ]] || dev="hw:0,0"
  if jack_ready && start_scsynth_client "$dev"; then
    exit 0
  fi
  echo "ERROR: SC_JACK_ALREADY=1 but scsynth restart failed" >&2
  exit 1
fi

while IFS= read -r dev; do
  [[ -n "$dev" ]] || continue
  if try_stack "$dev"; then
    exit 0
  fi
  echo "try_stack failed for $dev — full teardown before next device" >>"$LOG"
  stop_audio_stack
done < <(jack_candidates)

echo "ERROR: jackd+scsynth did not stay up on port $PORT" >&2
echo "Log: $LOG" >&2
tail -40 "$LOG" >&2 || true
echo "Try: fuser -v /dev/snd/* ; aplay -D hw:0,0 /usr/share/sounds/alsa/Front_Center.wav" >&2
exit 1
