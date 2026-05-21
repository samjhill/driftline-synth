#!/usr/bin/env bash
# Headless SuperCollider engine for systemd (no X11 / Qt xcb).
set -euo pipefail

ROOT="${PI_AMBIENT_ROOT:-/home/pi/pi-ambient-synth}"
SCD="${ROOT}/synth/ambient_engine.scd"

export HOME="${HOME:-/home/pi}"
export QT_QPA_PLATFORM=offscreen
unset DISPLAY
export SC_JACK_DEFAULT_INPUTS="${SC_JACK_DEFAULT_INPUTS:-}"
export SC_JACK_DEFAULT_OUTPUTS="${SC_JACK_DEFAULT_OUTPUTS:-}"
# ALSA device name from `aplay -L` (e.g. default, hw:0,0). Leave empty for SC default.
export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-plughw:0,0}"

# Run script as argument (-l is for libraries, not .scd files; breaks headless systemd).
exec /usr/bin/sclang "$SCD" </dev/null
