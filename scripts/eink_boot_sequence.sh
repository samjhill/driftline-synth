#!/usr/bin/env bash
# Serialized e-ink boot: splash → network IP → patch (one GPIO owner at a time).
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
LOG="${EINK_LOG:-/var/log/pi-ambient-synth-eink.log}"
MARKER="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
DONE_FLAG="${MARKER}/eink-boot-sequence.done"
LOCK="${EINK_LOCK_FILE:-/tmp/pi-ambient-synth-eink.lock}"

export HOME=/home/pi
export GPIOZERO_PIN_FACTORY=lgpio
export EINK_LOG="$LOG"
export INSTALL_DIR="$ROOT"
export MARKER_DIR="$MARKER"
export EINK_LOCK_FILE="$LOCK"
# Let show_status wait on the lock instead of skipping (boot owns the panel).
export EINK_LOCK_WAIT_SECONDS="${EINK_LOCK_WAIT_SECONDS:-120}"
export EINK_SKIP_PURGE="${EINK_SKIP_PURGE:-1}"
export EINK_NO_DEEP_SLEEP="${EINK_NO_DEEP_SLEEP:-1}"
export EINK_DISPLAY_TIMEOUT="${EINK_DISPLAY_TIMEOUT:-180}"

mkdir -p "$(dirname "$LOG")" "$MARKER" 2>/dev/null || true
rm -f "$LOCK" /home/pi/.lgd-* 2>/dev/null || true

log() {
  echo "$(date -Iseconds) [eink_boot_sequence] $*" | tee -a "$LOG" >/dev/null
}

if [[ "$(id -un)" == "root" ]] && id -u pi &>/dev/null; then
  exec sudo -u pi env \
    EINK_AS_USER=1 \
    INSTALL_DIR="$ROOT" \
    EINK_LOG="$LOG" \
    MARKER_DIR="$MARKER" \
    EINK_LOCK_FILE="$LOCK" \
    EINK_LOCK_WAIT_SECONDS="${EINK_LOCK_WAIT_SECONDS}" \
    EINK_SKIP_PURGE="${EINK_SKIP_PURGE}" \
    GPIOZERO_PIN_FACTORY=lgpio \
    "$0" "$@"
fi

log "start"
KILL="$ROOT/scripts/eink_kill_legacy_holders.sh"
if [[ -x "$KILL" ]]; then
  bash "$KILL"
fi
sleep 2

BD="$ROOT/scripts/boot_display.sh"
AN="$ROOT/scripts/announce_network.sh"
PATCH="$ROOT/scripts/eink_show_patch_status.sh"

step() {
  local name=$1
  shift
  log "step $name"
  if ! "$@"; then
    log "WARN: step $name failed (rc=$?) — continuing"
  fi
  sleep 2
}

step boot "$BD" boot "Booting" "Pi Ambient Synth" "power on"

log "waiting for LAN address (up to 90s)"
ip=""
for _ in $(seq 1 45); do
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "$ip" ]]; then
    log "LAN up: $ip"
    break
  fi
  sleep 2
done

step network "$AN"
step patch "$PATCH"

date -Iseconds >"$DONE_FLAG"
log "done → $DONE_FLAG"
