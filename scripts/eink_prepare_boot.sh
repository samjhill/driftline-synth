#!/usr/bin/env bash
# Boot-time: free the Waveshare HAT from prior projects (GhostRoll) before any synth e-ink refresh.
# Safe to run on every boot — does not stop pi-ambient-synth-boot-display or MIDI/audio.
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
KILL="$ROOT/scripts/eink_kill_legacy_holders.sh"
LOG="${EINK_LOG:-/var/log/pi-ambient-synth-eink.log}"

mkdir -p "$(dirname "$LOG")" /var/lib/pi-ambient-synth 2>/dev/null || true

{
  echo "$(date -Iseconds) eink_prepare_boot start"
  if [[ -x "$KILL" ]]; then
    INSTALL_DIR="$ROOT" EINK_LOG="$LOG" bash "$KILL"
  else
    echo "WARN: $KILL missing"
  fi
  echo "$(date -Iseconds) eink_prepare_boot done"
} >>"$LOG" 2>&1
