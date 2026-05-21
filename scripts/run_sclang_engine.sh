#!/usr/bin/env bash
# Headless SuperCollider engine for systemd (no X11 / Qt xcb).
set -euo pipefail

ROOT="${PI_AMBIENT_ROOT:-/home/pi/pi-ambient-synth}"
SCD="${ROOT}/synth/ambient_engine.scd"
READY_MARKER="${PI_SC_READY_MARKER:-/var/lib/pi-ambient-synth/sc-engine-ready}"

export HOME="${HOME:-/home/pi}"
export QT_QPA_PLATFORM=offscreen
unset DISPLAY
export SC_JACK_DEFAULT_INPUTS="${SC_JACK_DEFAULT_INPUTS:-}"
export SC_JACK_DEFAULT_OUTPUTS="${SC_JACK_DEFAULT_OUTPUTS:-system:playback_1,system:playback_2}"
# External jackd from start_scsynth_alsa.sh; do not let scsynth spawn jackdmp.
export JACK_NO_AUDIO_RESERVATION="${JACK_NO_AUDIO_RESERVATION:-1}"
export JACK_NO_START_SERVER="${JACK_NO_START_SERVER:-1}"
# ALSA device name from `aplay -L` (e.g. plughw:0,0). Empty makes scsynth try JACK.
export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-hw:0,0}"
export SC_HEADLESS_ALSA="${SC_HEADLESS_ALSA:-1}"
# Orphan scsynth from a prior crash/restart can leave sclang pointing at dead Nodes (silent OSC).
rm -f "$READY_MARKER" 2>/dev/null || true
pkill -x sclang 2>/dev/null || true
sleep 0.5
"$ROOT/scripts/start_scsynth_alsa.sh" || exit 1

DRIVER_FILE="${PI_SC_DRIVER_FILE:-/var/lib/pi-ambient-synth/scsynth_audio.conf}"
if [[ -f "$DRIVER_FILE" ]] && grep -q '^SC_SYNTH_DRIVER=alsa$' "$DRIVER_FILE" 2>/dev/null; then
  echo "scsynth on native ALSA — skipping JACK playback reconnect loop"
else
  # SC_JACK_DEFAULT_OUTPUTS often does not stick after sclang attaches; reconnect on a schedule.
  (
    for delay in 8 15 22 30 40 55 75; do
      sleep "$delay"
      [[ -x "$ROOT/scripts/ensure_jack_playback.sh" ]] && "$ROOT/scripts/ensure_jack_playback.sh" || true
    done
    while true; do
      sleep 25
      [[ -x "$ROOT/scripts/ensure_jack_playback.sh" ]] && "$ROOT/scripts/ensure_jack_playback.sh" || true
    done
  ) &
fi

# Run script as argument (-l is for libraries, not .scd files; breaks headless systemd).
# Line-buffered stdout so systemd journal shows Booting/scsynth lines promptly.
exec stdbuf -oL -eL /usr/bin/sclang -l "$ROOT/synth/pi_bind_port.scd" "$SCD" </dev/null
