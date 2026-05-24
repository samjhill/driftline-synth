# shellcheck shell=bash
# Exclusive e-ink ownership before any display access.

EINK_LOCK_FILE="${EINK_LOCK_FILE:-/run/pi-ambient-synth/eink-display.lock}"
EINK_SPI_DEV="${EINK_SPI_DEV:-/dev/spidev0.0}"

eink_log_exclusive() {
  local logfile="${1:-}"
  [[ -n "$logfile" ]] || return 0
  {
    echo "=== $(date -Iseconds) exclusive ==="
    echo "$2"
  } >>"$logfile"
}

eink_kill_holders() {
  systemctl stop pi-ambient-synth-eink.service 2>/dev/null || true
  systemctl stop pi-ambient-synth-eink-early.service 2>/dev/null || true
  if [[ -x /home/pi/pi-ambient-synth/scripts/eink_kill_legacy_holders.sh ]]; then
    INSTALL_DIR=/home/pi/pi-ambient-synth bash /home/pi/pi-ambient-synth/scripts/eink_kill_legacy_holders.sh 2>/dev/null || true
  fi
  pkill -9 -f 'eink_safe_boot_indicator|eink_display\.py|eink_early_progress|eink_official_minimal' 2>/dev/null || true
  pkill -9 -f 'show_status\.py|boot_display\.sh|ghostroll.*eink' 2>/dev/null || true
  sleep 1
}

eink_acquire_exclusive() {
  local logfile="${1:-}"
  mkdir -p "$(dirname "$EINK_LOCK_FILE")" 2>/dev/null || true
  eink_kill_holders
  exec 9>"$EINK_LOCK_FILE"
  if ! flock -n 9; then
    eink_log_exclusive "$logfile" "FAIL: flock busy on $EINK_LOCK_FILE"
    return 1
  fi
  eink_log_exclusive "$logfile" "flock acquired on $EINK_LOCK_FILE"
  if command -v fuser >/dev/null 2>&1; then
    eink_log_exclusive "$logfile" "fuser ${EINK_SPI_DEV}: $(fuser -v "$EINK_SPI_DEV" 2>&1 || echo none)"
  fi
  if command -v lsof >/dev/null 2>&1; then
    eink_log_exclusive "$logfile" "lsof ${EINK_SPI_DEV}: $(lsof "$EINK_SPI_DEV" 2>&1 || echo none)"
  fi
  return 0
}

eink_wait_spidev() {
  local logfile="${1:-}"
  local max_wait="${2:-60}"
  local extra_sleep="${3:-5}"
  local n=0
  while [[ ! -e "$EINK_SPI_DEV" ]] && ((n < max_wait)); do
    sleep 1
    n=$((n + 1))
  done
  eink_log_exclusive "$logfile" "spidev wait ${n}s exists=$([[ -e $EINK_SPI_DEV ]] && echo yes || echo no)"
  if [[ ! -e "$EINK_SPI_DEV" ]]; then
    return 1
  fi
  eink_log_exclusive "$logfile" "spidev stabilization sleep ${extra_sleep}s"
  sleep "$extra_sleep"
  return 0
}
