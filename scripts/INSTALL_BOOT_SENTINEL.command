#!/bin/bash
# Double-click in Finder: install boot sentinel on inserted SD (admin password once).
cd "$(dirname "$0")/.."
BOOT="/Volumes/bootfs"
[[ -d "$BOOT" ]] || BOOT="/Volumes/boot"
if [[ ! -d "$BOOT" ]]; then
  osascript -e 'display alert "SD not mounted" message "Insert SD and open bootfs volume first."'
  exit 1
fi
/usr/bin/osascript -e "do shell script \"'$PWD/scripts/install_boot_sentinel_rootfs.sh' '$BOOT'\" with administrator privileges"
"$PWD/scripts/check_sd_boot_mac.sh" "$BOOT" 2>&1 | tail -20
read -r -p "Press Enter to close…"
