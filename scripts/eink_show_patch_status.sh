#!/usr/bin/env bash
# Canonical patch/status e-ink refresh (user pi, file lock, 35s cap).
# Spawned detached from pi_midi_bridge on startup/reseed — must not block MIDI/audio.
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
LOG="${EINK_LOG:-/var/log/pi-ambient-synth-eink.log}"
LOCK="${EINK_LOCK_FILE:-/tmp/pi-ambient-synth-eink.lock}"
PY="${ROOT}/.venv/bin/python"
SCRIPT="${ROOT}/scripts/show_status.py"
MARKER="${MARKER_DIR:-/var/lib/pi-ambient-synth}"

log() {
  echo "$(date -Iseconds) [eink_show_patch] $*" | tee -a "$LOG" >/dev/null
}

# Never hold GPIO as root unless explicitly allowed.
if [[ "$(id -un)" == "root" ]] && [[ "${EINK_ALLOW_ROOT:-0}" != "1" ]]; then
  if id -u pi &>/dev/null && sudo -u pi true 2>/dev/null; then
    exec sudo -u pi env \
      EINK_AS_USER=1 \
      INSTALL_DIR="$ROOT" \
      EINK_LOG="$LOG" \
      EINK_LOCK_FILE="$LOCK" \
      MARKER_DIR="$MARKER" \
      GPIOZERO_PIN_FACTORY=lgpio \
      "$0" "$@"
  fi
  log "ERROR: refuse root (set EINK_ALLOW_ROOT=1 to override)"
  exit 4
fi

mkdir -p "$(dirname "$LOG")" "$MARKER" 2>/dev/null || true

if [[ ! -x "$PY" ]] || [[ ! -f "$SCRIPT" ]]; then
  log "ERROR: missing venv or show_status.py"
  exit 5
fi

# Lock is acquired inside show_status.py (waits up to EINK_LOCK_WAIT_SECONDS).
export HOME=/home/pi
export EINK_LOCK_WAIT_SECONDS="${EINK_LOCK_WAIT_SECONDS:-90}"
export GPIOZERO_PIN_FACTORY=lgpio
export EINK_FORCE=1
export EINK_LOG="$LOG"
export EINK_LOCK_FILE="$LOCK"
export MARKER_DIR="$MARKER"
export PYTHONPATH="${ROOT}/src"

log "start --restore-patch (timeout 35s)"
set +e
if command -v timeout >/dev/null; then
  timeout --kill-after=10 90 "$PY" "$SCRIPT" --restore-patch >>"$LOG" 2>&1
  rc=$?
else
  "$PY" "$SCRIPT" --restore-patch >>"$LOG" 2>&1
  rc=$?
fi
set -e

case "$rc" in
  0) log "OK"; exit 0 ;;
  2) log "EINK_BUSY_TIMEOUT"; exit 2 ;;
  3) log "SKIPPED_LOCKED"; exit 3 ;;
  124|137) log "ERROR: timeout/killed (rc=$rc)"; exit 2 ;;
  *)
    log "ERROR: show_status exit rc=$rc"
    exit 1
    ;;
esac
