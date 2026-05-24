#!/usr/bin/env bash
# Fallback: run pi_boot_sentinel.sh via cmdline systemd.run (no root-FS e2tools).
# Usage: ./scripts/install_boot_sentinel_cmdline.sh [/Volumes/bootfs]
set -euo pipefail

BOOT_VOL="${1:-}"
for v in /Volumes/bootfs /Volumes/boot; do
  [[ -z "$BOOT_VOL" && -d "$v" ]] && BOOT_VOL="$v"
done
[[ -n "$BOOT_VOL" && -f "$BOOT_VOL/cmdline.txt" ]] || {
  echo "ERROR: boot volume or cmdline.txt not found" >&2
  exit 1
}

SCRIPT_BOOT="/boot/firmware/pi-ambient-synth/scripts/pi_boot_sentinel.sh"
MARK="systemd.run=${SCRIPT_BOOT}"
CMD="$BOOT_VOL/cmdline.txt"

if grep -q 'pi_boot_sentinel\.sh' "$CMD" 2>/dev/null; then
  echo "OK: cmdline already has boot sentinel systemd.run"
  exit 0
fi

# Strip any legacy full-install hooks only
if grep -q 'pi-ambient-synth-firstboot' "$CMD" 2>/dev/null; then
  sed -i.bak 's/ systemd\.run=[^ ]*//g; s/ systemd\.run_success_action=[^ ]*//g; s/ systemd\.unit=kernel-command-line\.service//g' "$CMD"
fi

cp "$CMD" "${CMD}.bak-sentinel"
printf ' %s systemd.run_success_action=none' "$MARK" >>"$CMD"
echo "OK: appended boot sentinel to $CMD"
echo "    (runs before cloud-init; root unit preferred if you can: sudo ./scripts/install_boot_sentinel_rootfs.sh)"
