#!/usr/bin/env bash
# Pi: verify production main.py imports without numpy (avoids SIGBUS on some images).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
PY="${INSTALL_DIR}/.venv/bin/python"

export PI_NO_MIDI=1
exec "$PY" -c "
import sys
sys.path.insert(0, '${INSTALL_DIR}/src')
import main
print('OK: main.py imports without numpy')
"
