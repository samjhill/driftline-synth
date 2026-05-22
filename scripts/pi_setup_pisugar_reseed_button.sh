#!/usr/bin/env bash
# Assign PiSugar single-tap → new ambient patch (reseed.request for MIDI bridge).
# Safe to run repeatedly (deploy / restart).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PI_AMBIENT_ROOT="${PI_AMBIENT_ROOT:-$ROOT}"
export PYTHONPATH="${PI_AMBIENT_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}"

log() { echo "$(date -Iseconds) [pisugar-reseed-btn] $*"; }

if ! systemctl is-active --quiet pisugar-server 2>/dev/null; then
  log "SKIP: pisugar-server not active"
  exit 0
fi

if [[ ! -S /tmp/pisugar-server.sock ]]; then
  log "SKIP: /tmp/pisugar-server.sock missing"
  exit 0
fi

chmod +x "${PI_AMBIENT_ROOT}/scripts/pi_pisugar_button_reseed.sh"

PY="${PI_AMBIENT_ROOT}/.venv/bin/python"
if [[ ! -x "$PY" ]]; then
  PY=python3
fi

if "$PY" - <<'PY'
import sys
from pathlib import Path

from config_loader import load_config
from pisugar_button import setup_reseed_button

root = Path(__import__("os").environ["PI_AMBIENT_ROOT"])
ok = setup_reseed_button(root, load_config())
sys.exit(0 if ok else 1)
PY
then
  log "PiSugar single-tap → reseed (scripts/pi_pisugar_button_reseed.sh)"
else
  log "WARN: setup failed — try: echo 'set_button_shell single ${PI_AMBIENT_ROOT}/scripts/pi_pisugar_button_reseed.sh' | nc -U /tmp/pisugar-server.sock"
  exit 1
fi
