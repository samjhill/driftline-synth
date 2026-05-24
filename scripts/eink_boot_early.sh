#!/usr/bin/env bash
# bootcmd — status only. NO display access (firstboot-light owns the panel).
set -u

for b in /boot/firmware /boot; do
  if [[ -d "$b" ]]; then
    mkdir -p "$b/pi-ambient-synth/boot-logs" 2>/dev/null || true
    echo "$(date -Iseconds) EINK_BOOTCMD_STATUS_ONLY no display" >>"$b/pi-ambient-synth/boot-logs/eink-early.log" 2>/dev/null || true
    echo "$(date -Iseconds) [ok] CLOUD_INIT bootcmd eink status-only" >>"$b/pi-ambient-firstboot-status.txt" 2>/dev/null || true
  fi
done
exit 0
