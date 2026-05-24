# shellcheck shell=bash
# Write WiFi debug bundle to boot partition (readable from Mac).

wifi_debug_bootfs_path() {
  for b in /boot/firmware /boot; do
    if [[ -d "$b" ]]; then
      echo "$b/pi-ambient-wifi-debug.txt"
      return 0
    fi
  done
  echo "/tmp/pi-ambient-wifi-debug.txt"
}

write_wifi_debug_bootfs() {
  local out
  out="$(wifi_debug_bootfs_path)"
  {
    echo "=== pi-ambient-wifi-debug $(date -Iseconds) ==="
    echo ""
    echo "=== ip addr show wlan0 ==="
    ip addr show wlan0 2>&1 || true
    echo ""
    echo "=== iw dev ==="
    iw dev 2>&1 || true
    echo ""
    echo "=== iw dev wlan0 link ==="
    iw dev wlan0 link 2>&1 || true
    echo ""
    echo "=== rfkill list ==="
    rfkill list 2>&1 || true
    echo ""
    echo "=== systemctl status NetworkManager ==="
    systemctl status NetworkManager --no-pager 2>&1 || true
    echo ""
    echo "=== systemctl status systemd-networkd ==="
    systemctl status systemd-networkd --no-pager 2>&1 || true
    echo ""
    echo "=== journalctl -u NetworkManager -b --no-pager | tail -80 ==="
    journalctl -u NetworkManager -b --no-pager 2>/dev/null | tail -80 || true
    echo ""
    echo "=== cloud-init network (status.json excerpt) ==="
    if [[ -f /var/lib/cloud/data/status.json ]]; then
      python3 -c "import json; d=json.load(open('/var/lib/cloud/data/status.json')); print(json.dumps(d.get('v1',{}), indent=2)[:4000])" 2>&1 || cat /var/lib/cloud/data/status.json 2>&1 | head -80
    else
      echo "(no /var/lib/cloud/data/status.json)"
    fi
    echo ""
    echo "=== state summary ==="
    # shellcheck disable=SC1091
    _lib="$(dirname "${BASH_SOURCE[0]}")"
    if [[ -f "$_lib/wifi_state.sh" ]]; then
      # shellcheck source=wifi_state.sh
      source "$_lib/wifi_state.sh"
      echo "wlan_associated=$(wifi_wlan_associated && echo yes || echo no)"
      echo "wlan_ipv4=$(wifi_wlan_has_ipv4 && echo yes || echo no)"
      echo "wlan_ip=$(wifi_wlan_ipv4 || echo none)"
      echo "ssh_listening=$(wifi_ssh_listening && echo yes || echo no)"
      echo "internet_ping=$(wifi_internet_reachable && echo yes || echo no)"
    fi
  } >"$out" 2>&1
  for b in /boot/firmware /boot; do
    [[ -d "$b" ]] && cp -f "$out" "$b/pi-ambient-wifi-debug.txt" 2>/dev/null || true
  done
  echo "$out"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  write_wifi_debug_bootfs
fi
