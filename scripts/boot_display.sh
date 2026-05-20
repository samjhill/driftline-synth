#!/usr/bin/env bash
# Show boot progress on e-ink (works from SD boot partition before install).
# Usage: boot_display.sh <phase> <title> [subtitle] [detail]
set -euo pipefail

export EINK_FORCE=1
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
phase="${1:-boot}"
title="${2:-Booting}"
subtitle="${3:-}"
detail="${4:-}"

find_script() {
  if [[ -f "$INSTALL_DIR/scripts/show_status.py" ]]; then
    echo "$INSTALL_DIR/scripts/show_status.py"
    return 0
  fi
  local b
  for b in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
    if [[ -f "$b/scripts/show_status.py" ]]; then
      echo "$b/scripts/show_status.py"
      return 0
    fi
  done
  return 1
}

find_python() {
  if [[ -x "$INSTALL_DIR/.venv/bin/python" ]]; then
    echo "$INSTALL_DIR/.venv/bin/python"
    return 0
  fi
  command -v python3 || echo python3
}

script="$(find_script)" || exit 0
py="$(find_python)"

if id -u pi &>/dev/null; then
  sudo -u pi env PYTHONPATH="$INSTALL_DIR/src" HOME=/home/pi \
    "$py" "$script" "$phase" "$title" "$subtitle" "$detail" 2>/dev/null || true
else
  "$py" "$script" "$phase" "$title" "$subtitle" "$detail" 2>/dev/null || true
fi
