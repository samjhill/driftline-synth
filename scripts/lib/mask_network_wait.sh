# shellcheck shell=bash
# Mask systemd units that block boot/cloud-init on slow or missing WiFi.

mask_network_wait_online() {
  local u
  for u in \
    NetworkManager-wait-online.service \
    systemd-networkd-wait-online.service; do
    systemctl stop "$u" 2>/dev/null || true
    systemctl disable "$u" 2>/dev/null || true
    systemctl mask "$u" 2>/dev/null || true
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  mask_network_wait_online
  echo "masked NetworkManager-wait-online and systemd-networkd-wait-online"
fi
