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
# Prevent scsynth from spawning JACK to grab hw:0 on headless Pi.
export JACK_NO_AUDIO_RESERVATION="${JACK_NO_AUDIO_RESERVATION:-1}"
# ALSA device name from `aplay -L` (e.g. plughw:0,0). Empty makes scsynth try JACK.
export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-plughw:0,0}"

# Run script as argument (-l is for libraries, not .scd files; breaks headless systemd).
# Line-buffered stdout so systemd journal shows Booting/scsynth lines promptly.
exec stdbuf -oL -eL /usr/bin/sclang "$SCD" </dev/null
