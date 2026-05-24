# shellcheck shell=bash
# WiFi/LAN state — separate association, IP, SSH, and internet.

wifi_wlan_associated() {
  if command -v iw >/dev/null 2>&1; then
    iw dev wlan0 link 2>/dev/null | grep -q 'Connected to' && return 0
  fi
  if command -v nmcli >/dev/null 2>&1; then
    nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep -q '^wlan0:connected' && return 0
  fi
  return 1
}

wifi_wlan_has_ipv4() {
  ip -4 addr show wlan0 2>/dev/null | grep -q 'inet '
}

wifi_wlan_ipv4() {
  ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1
}

wifi_ssh_listening() {
  ss -tln 2>/dev/null | grep -q ':22 ' || \
    ss -tln 2>/dev/null | grep -q ':22$'
}

wifi_internet_reachable() {
  ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1
}
