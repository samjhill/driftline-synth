#!/usr/bin/env bash
# Show boot / first-boot progress on e-ink (works from SD before install).
# Usage:
#   boot_display.sh <phase> <title> [subtitle] [detail]
#   FIRST_BOOT_TRACK=1 boot_display.sh ...   # auto step counter (1..TOTAL)
set -euo pipefail

# GPIO/lgpio is owned by user pi; root often gets "GPIO busy" if GhostRoll/synth held the HAT.
if [[ "$(id -un)" != "pi" ]] && [[ "${EINK_AS_USER:-0}" != "1" ]] && [[ "${EINK_ALLOW_ROOT:-0}" != "1" ]]; then
  if id -u pi &>/dev/null && sudo -u pi true 2>/dev/null; then
    exec sudo -u pi env \
      EINK_AS_USER=1 \
      EINK_FORCE="${EINK_FORCE:-1}" \
      EINK_LOG="${EINK_LOG:-/var/log/pi-ambient-synth-eink.log}" \
      INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}" \
      MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}" \
      FIRST_BOOT_TRACK="${FIRST_BOOT_TRACK:-0}" \
      FIRST_BOOT_TOTAL="${FIRST_BOOT_TOTAL:-12}" \
      EINK_DISPLAY_TIMEOUT="${EINK_DISPLAY_TIMEOUT:-50}" \
      HOME=/home/pi \
      "$0" "$@"
  fi
  echo "WARN: e-ink expects user pi (got $(id -un)); GPIO may fail" >&2
fi

EINK_LOG="${EINK_LOG:-/var/log/pi-ambient-synth-eink.log}"
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
  # Prefer venv (PIL, yaml, gpiozero+lgpio via system-site-packages); lazy imports avoid numpy on status-only runs.
  if [[ -x "$INSTALL_DIR/.venv/bin/python" ]]; then
    echo "$INSTALL_DIR/.venv/bin/python"
    return 0
  fi
  if /usr/bin/python3 -c "import gpiozero, spidev, PIL" 2>/dev/null; then
    echo /usr/bin/python3
    return 0
  fi
  command -v python3 || echo python3
}

find_src_path() {
  if [[ -d "$INSTALL_DIR/src" ]]; then
    echo "$INSTALL_DIR/src"
    return 0
  fi
  local b
  for b in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
    if [[ -d "$b/src" ]]; then
      echo "$b/src"
      return 0
    fi
  done
  return 1
}

boot_log_dir() {
  for b in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
    if [[ -d "$b" ]]; then
      echo "$b/boot-logs"
      return 0
    fi
  done
  return 1
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

script="$(find_script)" || { echo "boot_display: show_status.py not found" >&2; exit 1; }
py="$(find_python)"
src="$(find_src_path)" || { echo "boot_display: src/ not found on SD or install dir" >&2; exit 1; }

ensure_ws() {
  local ws="$INSTALL_DIR/scripts/ensure_waveshare_vendor.sh"
  if [[ ! -x "$ws" ]]; then
    for b in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
      if [[ -x "$b/scripts/ensure_waveshare_vendor.sh" ]]; then
        ws="$b/scripts/ensure_waveshare_vendor.sh"
        break
      fi
    done
  fi
  if [[ -x "$ws" ]]; then
    mkdir -p "$(dirname "$EINK_LOG")" 2>/dev/null || true
    bash "$ws" >>"$EINK_LOG" 2>&1 || true
  fi
}
ensure_ws
cfg=()
if cfg_file="$(config_path)"; then
  cfg=(--config "$cfg_file")
fi

mkdir -p "$(dirname "$EINK_LOG")" 2>/dev/null || true
BOOT_LOG_MIRROR=""
if bl="$(boot_log_dir)"; then
  mkdir -p "$bl" 2>/dev/null || true
  BOOT_LOG_MIRROR="$bl/eink.log"
fi

run_display() {
  local display_timeout="${EINK_DISPLAY_TIMEOUT:-50}"
  export PYTHONPATH="$src" HOME=/home/pi GPIOZERO_PIN_FACTORY=lgpio
  case "$phase" in
    boot|wifi|network|install|ready|failed) export EINK_FORCE=1 ;;
  esac
  cd /home/pi || return 1
  rm -f .lgd-* 2>/dev/null || true
  if command -v timeout &>/dev/null; then
    timeout --kill-after=5 "${display_timeout}" \
      "$py" "$script" "${cfg[@]}" $step_arg $total_arg \
      "$phase" "$title" "$subtitle" "$detail"
  else
    "$py" "$script" "${cfg[@]}" $step_arg $total_arg \
      "$phase" "$title" "$subtitle" "$detail"
  fi
}

display_rc=0
{
  echo "$(date -Iseconds) boot_display phase=$phase title=$title"
  run_display
} >>"$EINK_LOG" 2>&1 || display_rc=1
if [[ "$display_rc" -ne 0 ]]; then
  echo "$(date -Iseconds) boot_display FAILED phase=$phase (non-fatal for systemd)" >>"$EINK_LOG"
  echo "boot_display: e-ink update failed (see $EINK_LOG); synth stack can still start" >&2
  # Early boot: GPIO busy / panel slow — do not mark systemd unit failed.
  display_rc=0
fi

# Boot partition is often read-only after first boot — never fail the display on mirror errors.
if [[ -n "$BOOT_LOG_MIRROR" && -f "$EINK_LOG" ]]; then
  set +e
  if touch "$BOOT_LOG_MIRROR" 2>/dev/null; then
    tail -n 500 "$EINK_LOG" >"$BOOT_LOG_MIRROR" 2>/dev/null
  fi
  set -e
fi

exit "$display_rc"
