#!/usr/bin/env bash
# Known-good e-ink test — exact eink_official_minimal_test.py from install tree.
# Run on the Pi: sudo ./scripts/eink_known_good_direct_test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
if [[ -d "$INSTALL_DIR/scripts" ]]; then
  ROOT="$INSTALL_DIR"
fi

LOG=""
for d in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
  if [[ -d "$d/boot-logs" ]]; then
    LOG="$d/boot-logs/known-good-eink.log"
    break
  fi
done
[[ -n "$LOG" ]] || LOG="/var/log/known-good-eink.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log() {
  echo "$(date -Iseconds) $*" | tee -a "$LOG"
}

log "known-good direct test start ROOT=$ROOT"
log "python=$(command -v python3 2>/dev/null || echo missing)"
log "spidev=$([[ -e /dev/spidev0.0 ]] && echo present || echo missing)"

# Stop app / e-ink services (not MIDI / FluidSynth).
for u in pi-ambient-synth-eink.service pi-ambient-synth-eink-early.service \
  pi-ambient-synth-firstboot-light.service pi-ambient-synth-firstboot-heavy.service \
  pi-ambient-synth-deploy.service pi-ambient-synth-deploy.timer; do
  systemctl stop "$u" 2>/dev/null || true
done

if [[ -x "$ROOT/scripts/eink_kill_legacy_holders.sh" ]]; then
  INSTALL_DIR="$ROOT" bash "$ROOT/scripts/eink_kill_legacy_holders.sh" 2>/dev/null || true
fi
pkill -9 -f 'eink_display|eink_safe_boot|eink_early_progress|boot_display' 2>/dev/null || true
sleep 1

if command -v fuser >/dev/null 2>&1; then
  log "fuser /dev/spidev0.0: $(fuser -v /dev/spidev0.0 2>&1 || echo none)"
fi

cd "$ROOT"
export HOME="${HOME:-/home/pi}"
export GPIOZERO_PIN_FACTORY=lgpio
export EINK_VALIDATE_BUSY="${EINK_VALIDATE_BUSY:-1}"

MINIMAL="$ROOT/scripts/eink_official_minimal_test.py"
if [[ ! -f "$MINIMAL" ]]; then
  log "FAIL: missing $MINIMAL"
  exit 1
fi

log "command: cd $ROOT && EINK_VALIDATE_BUSY=$EINK_VALIDATE_BUSY python3 scripts/eink_official_minimal_test.py epd2in13_V4"
log "--- stdout/stderr ---"

_run() {
  cd "$ROOT"
  export HOME="${HOME:-/home/pi}"
  export GPIOZERO_PIN_FACTORY=lgpio
  python3 scripts/eink_official_minimal_test.py "$@"
}

_rc=0
if [[ "$(id -u)" -eq 0 ]]; then
  if ! _run epd2in13_V4 2>&1 | tee -a "$LOG"; then _rc=$?; fi
else
  if ! sudo -E env HOME="${HOME:-/home/pi}" GPIOZERO_PIN_FACTORY=lgpio EINK_VALIDATE_BUSY="$EINK_VALIDATE_BUSY" \
    bash -c "cd '$ROOT' && python3 scripts/eink_official_minimal_test.py epd2in13_V4" 2>&1 | tee -a "$LOG"; then
    _rc=$?
  fi
fi

log "--- end rc=$_rc ---"
log "USER_REPORT: Did the panel show white -> black -> white? (visible / blank)"
log "If blank: power off, reseat FPC, rerun with: $0 epd2in13_V3  or  $0 epd2in13_V2"

if [[ $# -gt 0 ]]; then
  for mod in "$@"; do
    log "alternate module: $mod"
    if [[ "$(id -u)" -eq 0 ]]; then
      _run "$mod" 2>&1 | tee -a "$LOG" || _rc=$?
    else
      sudo -E env HOME="${HOME:-/home/pi}" GPIOZERO_PIN_FACTORY=lgpio EINK_VALIDATE_BUSY="$EINK_VALIDATE_BUSY" \
        bash -c "cd '$ROOT' && python3 scripts/eink_official_minimal_test.py '$mod'" 2>&1 | tee -a "$LOG" || _rc=$?
    fi
  done
fi

exit "$_rc"
