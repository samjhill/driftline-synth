#!/usr/bin/env bash
# Local development: start SuperCollider engine then Python orchestrator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  .venv/bin/pip install -q mido python-rtmidi python-osc PyYAML Pillow numpy
fi

SC_PID=""
cleanup() {
  if [[ -n "$SC_PID" ]] && kill -0 "$SC_PID" 2>/dev/null; then
    kill "$SC_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if command -v sclang &>/dev/null; then
  echo "Starting SuperCollider engine..."
  sclang "$ROOT/synth/ambient_engine.scd" &
  SC_PID=$!
  sleep 3
else
  echo "Warning: sclang not found — start SuperCollider manually"
fi

echo "Starting Python orchestrator..."
.venv/bin/python "$ROOT/src/main.py" "$@"
