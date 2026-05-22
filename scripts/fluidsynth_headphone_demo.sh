#!/usr/bin/env bash
# Prove FluidSynth → plughw:0,0 → Pi headphone jack (no JACK, no SuperCollider).
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
PY="${ROOT}/.venv/bin/python"
[[ -x "$PY" ]] || PY="$(command -v python3)"

if ! command -v fluidsynth >/dev/null 2>&1; then
  echo "Installing fluidsynth + GM soundfont (sudo)..." >&2
  sudo apt-get update -qq
  sudo apt-get install -y fluidsynth fluid-soundfont-gm
fi

exec "$PY" "$ROOT/scripts/fluidsynth_headphone_demo.py"
