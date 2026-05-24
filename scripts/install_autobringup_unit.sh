#!/usr/bin/env bash
# Legacy cloud-init hook — delegates to install_autobringup_on_pi.sh.
set -euo pipefail

for b in /boot/firmware /boot; do
  [[ -d "$b" ]] && echo "$(date -Iseconds) [ok] CLOUD_INIT autobringup minimal" \
    >>"$b/pi-ambient-firstboot-status.txt" 2>/dev/null || true
done

SELF=""
for d in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
  if [[ -x "$d/scripts/install_autobringup_on_pi.sh" ]]; then
    SELF="$d/scripts/install_autobringup_on_pi.sh"
    break
  fi
done
[[ -n "$SELF" ]] || { echo "install_autobringup_unit: install_autobringup_on_pi.sh missing" >&2; exit 1; }
exec bash "$SELF"
