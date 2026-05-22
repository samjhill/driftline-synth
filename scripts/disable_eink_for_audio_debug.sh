#!/usr/bin/env bash
# Phase 4 prep: stop e-ink systemd units during headphone/audio debugging.
set -euo pipefail

log() { echo "[disable-eink] $*"; }

for unit in \
  pi-ambient-synth-boot-display.service \
  pi-ambient-synth-network-announce.service \
  pi-ambient-synth-audio-display.service; do
  if systemctl list-unit-files "$unit" &>/dev/null; then
    log "stop + mask $unit"
    sudo systemctl stop "$unit" 2>/dev/null || true
    sudo systemctl mask "$unit" 2>/dev/null || true
  fi
done

log "e-ink display services disabled until audio is verified"
log "Re-enable: sudo systemctl unmask <unit> && sudo systemctl start <unit>"
