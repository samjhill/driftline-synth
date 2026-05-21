#!/usr/bin/env bash
# engine_smoke_pi.sh — Pi engine check (~30–180s). No systemd restart.
set -euo pipefail

ROOT="${PI_AMBIENT_ROOT:-/home/pi/pi-ambient-synth}"
SCD="${ROOT}/synth/ambient_engine.scd"
BIND="${ROOT}/synth/pi_bind_port.scd"
LOG="${ENGINE_SMOKE_LOG:-/tmp/pi-ambient-engine-smoke.log}"
TIMEOUT="${ENGINE_SMOKE_TIMEOUT:-180}"

export HOME="${HOME:-/home/pi}"
export QT_QPA_PLATFORM=offscreen
unset DISPLAY
export SC_ENGINE_TEST=1
export JACK_NO_AUDIO_RESERVATION=1
export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-hw:0,0}"
export SC_JACK_DEFAULT_INPUTS="${SC_JACK_DEFAULT_INPUTS:-}"
export SC_JACK_DEFAULT_OUTPUTS="${SC_JACK_DEFAULT_OUTPUTS:-}"
export JACK_NO_START_SERVER="${JACK_NO_START_SERVER:-1}"
export SC_HEADLESS_ALSA=1
export SC_SYNTH_PORT="${SC_SYNTH_PORT:-57110}"

wait_udp_port() {
  local i
  for i in $(seq 1 40); do
    if command -v ss >/dev/null && ss -uln 2>/dev/null | grep -qE ":${SC_SYNTH_PORT}[[:space:]]"; then
      return 0
    fi
    sleep 0.15
  done
  return 1
}

stack_up() {
  pgrep -x jackd >/dev/null && pgrep -x scsynth >/dev/null || return 1
  ls /dev/shm/jack* 1>/dev/null 2>&1 || return 1
  if command -v ss >/dev/null && ss -uln 2>/dev/null | grep -qE ":${SC_SYNTH_PORT}[[:space:]]"; then
    return 0
  fi
  command -v nc >/dev/null && nc -u -z -w1 127.0.0.1 "$SC_SYNTH_PORT" 2>/dev/null
}

jack_up() {
  pgrep -x jackd >/dev/null && ls /dev/shm/jack* 1>/dev/null 2>&1
}

if [[ "${1:-}" == "--restart" ]]; then
  pkill -x scsynth 2>/dev/null || true
  pkill -x jackd 2>/dev/null || true
  sleep 0.35
fi
pkill -x sclang 2>/dev/null || true
sleep 0.35

if [[ "${PI_SMOKE_NO_AUDIO:-}" == "1" ]] && stack_up; then
  echo "==> audio stack already up (PI_SMOKE_NO_AUDIO)"
elif [[ "${PI_SMOKE_NO_AUDIO:-}" == "1" ]] && jack_up; then
  echo "==> jackd up, starting scsynth only"
  SC_JACK_ALREADY=1 "$ROOT/scripts/start_scsynth_alsa.sh"
elif [[ "${1:-}" == "--reuse-audio" ]] && stack_up; then
  echo "==> reusing running jackd + scsynth (--reuse-audio)"
else
  echo "==> starting fresh jackd + scsynth"
  pkill -x scsynth 2>/dev/null || true
  pkill -x jackd 2>/dev/null || true
  sleep 0.5
  if ! "$ROOT/scripts/start_scsynth_alsa.sh"; then
    echo "ERROR: start_scsynth_alsa.sh failed — see /tmp/scsynth-alsa-start.log" >&2
    exit 1
  fi
fi

if ! wait_udp_port; then
  echo "ERROR: scsynth UDP port ${SC_SYNTH_PORT} not open" >&2
  exit 1
fi
echo "==> scsynth UDP ${SC_SYNTH_PORT} open"

if [[ ! -f "$SCD" ]]; then
  echo "ERROR: missing $SCD" >&2
  exit 1
fi

ENGINE_MARK="${ENGINE_BUILD_MARK:-sc313-oscPaths}"
if ! grep -q "$ENGINE_MARK" "$SCD"; then
  found="$(grep -o 'build sc313-[^"]*' "$SCD" | head -1 || true)"
  echo "ERROR: engine stale — want $ENGINE_MARK, file has: ${found:-<no sc313 marker>}" >&2
  exit 1
fi

echo "==> engine smoke: $SCD (timeout ${TIMEOUT}s, log $LOG)"
rm -f /var/lib/pi-ambient-synth/sc-engine-ready 2>/dev/null || true

set +e
if command -v timeout &>/dev/null; then
  timeout "${TIMEOUT}s" env SC_HEADLESS_ALSA=1 SC_ENGINE_TEST=1 \
    stdbuf -oL -eL /usr/bin/sclang -l "$BIND" "$SCD" </dev/null >"$LOG" 2>&1
  status=$?
else
  env SC_HEADLESS_ALSA=1 SC_ENGINE_TEST=1 stdbuf -oL -eL /usr/bin/sclang -l "$BIND" "$SCD" </dev/null >"$LOG" 2>&1
  status=$?
fi
set -e

echo "==> exit $status — highlights:"
grep -E 'bindPort|langPort|/done|status.reply|scsynth connected|Attaching|ENGINE_TEST|ERROR|Boolean|syntax|JackTemporary|jackd ready|scsynth ready|WARN:' "$LOG" || true

if grep -qE 'ERROR:|MustBeBoolean|syntax error|not understood|POPen|Command line parse failed' "$LOG"; then
  echo "==> last 25 lines:" >&2
  tail -25 "$LOG" >&2
  exit 1
fi

if ! grep -q 'Pi Ambient Synth ENGINE_TEST ok' "$LOG"; then
  echo "==> did not reach ENGINE_TEST ok (exit $status)" >&2
  tail -25 "$LOG" >&2
  exit 1
fi

echo "OK — engine smoke passed."
