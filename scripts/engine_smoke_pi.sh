#!/usr/bin/env bash
# engine_smoke_pi.sh v2 (marker sc313-jackExternal)
# Fast SuperCollider engine check on the Pi (~15–90s). No systemd restart.
#   ~/pi-ambient-synth/scripts/engine_smoke_pi.sh
#   ~/pi-ambient-synth/scripts/engine_smoke_pi.sh --restart   # pkill scsynth first
set -euo pipefail

ROOT="${PI_AMBIENT_ROOT:-/home/pi/pi-ambient-synth}"
SCD="${ROOT}/synth/ambient_engine.scd"
LOG="${ENGINE_SMOKE_LOG:-/tmp/pi-ambient-engine-smoke.log}"
TIMEOUT="${ENGINE_SMOKE_TIMEOUT:-90}"

export HOME="${HOME:-/home/pi}"
export QT_QPA_PLATFORM=offscreen
unset DISPLAY
export SC_ENGINE_TEST=1
export JACK_NO_AUDIO_RESERVATION=1
export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-hw:0,0}"
export SC_JACK_DEFAULT_INPUTS="${SC_JACK_DEFAULT_INPUTS:-}"
export SC_JACK_DEFAULT_OUTPUTS="${SC_JACK_DEFAULT_OUTPUTS:-}"

export SC_HEADLESS_ALSA=1
if [[ "${1:-}" == "--restart" ]]; then
  pkill -x scsynth 2>/dev/null || true
  sleep 0.35
fi
if ! "$ROOT/scripts/start_scsynth_alsa.sh"; then
  echo "ERROR: start_scsynth_alsa.sh failed — see /tmp/scsynth-alsa-start.log" >&2
  echo "Run: $ROOT/scripts/diagnose_scsynth_audio.sh" >&2
  exit 1
fi

if [[ ! -f "$SCD" ]]; then
  echo "ERROR: missing $SCD" >&2
  exit 1
fi

ENGINE_MARK="${ENGINE_BUILD_MARK:-sc313-jackExternal}"
if ! grep -q "$ENGINE_MARK" "$SCD"; then
  found="$(grep -o 'build sc313-[^"]*' "$SCD" | head -1 || true)"
  echo "WARN: engine stale — want $ENGINE_MARK, file has: ${found:-<no sc313 marker>}" >&2
  echo "  curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/e810b35/synth/ambient_engine.scd -o $SCD" >&2
fi

echo "==> engine smoke: $SCD (timeout ${TIMEOUT}s, log $LOG)"
rm -f /var/lib/pi-ambient-synth/sc-engine-ready 2>/dev/null || true

set +e
if command -v timeout &>/dev/null; then
  timeout "${TIMEOUT}s" env SC_HEADLESS_ALSA=1 SC_ENGINE_TEST=1 \
    stdbuf -oL -eL /usr/bin/sclang "$SCD" </dev/null >"$LOG" 2>&1
  status=$?
else
  env SC_HEADLESS_ALSA=1 SC_ENGINE_TEST=1 stdbuf -oL -eL /usr/bin/sclang "$SCD" </dev/null >"$LOG" 2>&1
  status=$?
fi
set -e

echo "==> exit $status — highlights:"
grep -E 'jackExternal|SC_AUDIO|scsynth connected|listening on OSC|Engine synths|ENGINE_TEST|ERROR|Boolean|syntax|JackTemporary|jackd ready|scsynth ready|WARN:' "$LOG" || true

if grep -qE 'ERROR:|MustBeBoolean|syntax error|Command line parse failed' "$LOG"; then
  echo "==> last 25 lines:" >&2
  tail -25 "$LOG" >&2
  exit 1
fi

if ! grep -q 'Pi Ambient Synth ENGINE_TEST ok' "$LOG"; then
  echo "==> did not reach ENGINE_TEST ok (exit $status)" >&2
  tail -25 "$LOG" >&2
  exit 1
fi

if [[ -f /var/lib/pi-ambient-synth/sc-engine-ready ]]; then
  echo "==> sc-engine-ready: $(cat /var/lib/pi-ambient-synth/sc-engine-ready)"
else
  echo "WARN: sc-engine-ready marker missing (smoke uses SC_ENGINE_TEST early exit)" >&2
fi

echo "OK — engine smoke passed. Restart services when ready:"
echo "  sudo systemctl restart supercollider pi-ambient-synth"
