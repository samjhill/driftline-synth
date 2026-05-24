#!/usr/bin/env bash
# Install and start pi-ambient-firstboot.service from boot partition (cloud-init runcmd only).
set -euo pipefail

for b in /boot/firmware /boot; do
  [[ -d "$b" ]] && echo "$(date -Iseconds) [ok] BOOT cloud-init minimal" >>"$b/pi-ambient-firstboot-status.txt" 2>/dev/null || true
done

UNIT_SRC=""
for d in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
  if [[ -f "$d/systemd/pi-ambient-firstboot.service" ]]; then
    UNIT_SRC="$d/systemd/pi-ambient-firstboot.service"
    break
  fi
done

[[ -n "$UNIT_SRC" ]] || { echo "install_firstboot_unit: missing unit on boot partition" >&2; exit 1; }

cp "$UNIT_SRC" /etc/systemd/system/pi-ambient-firstboot.service
chmod 644 /etc/systemd/system/pi-ambient-firstboot.service
systemctl daemon-reload
systemctl enable pi-ambient-firstboot.service
systemctl start pi-ambient-firstboot.service

for b in /boot/firmware /boot; do
  [[ -d "$b" ]] && echo "$(date -Iseconds) [ok] BOOT firstboot.service started" >>"$b/pi-ambient-firstboot-status.txt" 2>/dev/null || true
done
