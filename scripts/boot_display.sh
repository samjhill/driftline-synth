#!/usr/bin/env bash
# Show boot / first-boot progress on e-ink (works from SD before install).
# Usage:
#   boot_display.sh <phase> <title> [subtitle] [detail]
#   FIRST_BOOT_TRACK=1 boot_display.sh ...   # auto step counter (1..TOTAL)
set -euo pipefail

export EINK_FORCE=1
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
STEP_FILE="$MARKER_DIR/first_boot_step"
FIRST_BOOT_TOTAL="${FIRST_BOOT_TOTAL:-12}"

phase="${1:-boot}"
title="${2:-Booting}"
subtitle="${3:-}"
detail="${4:-}"
step_arg=""
total_arg=""

if [[ "${FIRST_BOOT_TRACK:-0}" == "1" ]]; then
  mkdir -p "$MARKER_DIR"
  n=$(($(cat "$STEP_FILE" 2>/dev/null || echo 0) + 1))
  echo "$n" > "$STEP_FILE"
  step_arg="--step $n"
  total_arg="--total $FIRST_BOOT_TOTAL"
fi

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

config_path() {
  if [[ -f "$INSTALL_DIR/config/default.yaml" ]]; then
    echo "$INSTALL_DIR/config/default.yaml"
    return 0
  fi
  local b
  for b in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
    if [[ -f "$b/config/default.yaml" ]]; then
      echo "$b/config/default.yaml"
      return 0
    fi
  done
  return 1
}

script="$(find_script)" || exit 0
py="$(find_python)"
cfg=()
if cfg_file="$(config_path)"; then
  cfg=(--config "$cfg_file")
fi

if id -u pi &>/dev/null; then
  sudo -u pi env PYTHONPATH="$INSTALL_DIR/src" HOME=/home/pi \
    "$py" "$script" "${cfg[@]}" $step_arg $total_arg \
    "$phase" "$title" "$subtitle" "$detail" 2>/dev/null || true
else
  "$py" "$script" "${cfg[@]}" $step_arg $total_arg \
    "$phase" "$title" "$subtitle" "$detail" 2>/dev/null || true
fi
