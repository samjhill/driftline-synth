#!/bin/bash
cd "$(dirname "$0")/.."
BOOT="/Volumes/bootfs"
[[ -d "$BOOT" ]] || BOOT="/Volumes/boot"
if [[ ! -d "$BOOT" ]]; then
  osascript -e 'display alert "SD not mounted" message "Insert SD with bootfs volume."'
  exit 1
fi
/usr/bin/osascript -e "do shell script \"'$PWD/scripts/install_autobringup_rootfs.sh' '$BOOT'\" with administrator privileges"
"$PWD/scripts/check_autobringup_sd_mac.sh" "$BOOT"
read -r -p "Press Enter…"
