#!/usr/bin/env bash
# Show primary LAN IP on e-ink and save network.json (callable before venv exists).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[[ -d "$INSTALL_DIR" ]] || INSTALL_DIR="$ROOT"

PY=""
for c in "$INSTALL_DIR/.venv/bin/python" python3; do
  if [[ -x "$c" ]] || command -v "$c" >/dev/null; then
    PY="$c"
    break
  fi
done

export PYTHONPATH="$INSTALL_DIR/src${PYTHONPATH:+:$PYTHONPATH}"
exec "$PY" "$INSTALL_DIR/scripts/announce_network.py" "$@"
