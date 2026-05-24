#!/usr/bin/env bash
# Append WiFi/link diagnostics to bootfs every 15s during firstboot.
set +e

INTERVAL="${FIRSTBOOT_NET_DEBUG_INTERVAL:-15}"
LOG_NAME="firstboot-network.log"
DONE_MARKERS="/var/lib/pi-ambient-synth/firstboot-done /run/pi-ambient-synth/firstboot-done"

boot_log() {
  local line="$1"
  for bootroot in /boot/firmware /boot; do
    [[ -d "$bootroot" ]] || continue
    mkdir -p "$bootroot/pi-ambient-synth/boot-logs" 2>/dev/null || true
    echo "$line" >>"$bootroot/pi-ambient-synth/boot-logs/$LOG_NAME" 2>/dev/null || true
  done
  echo "$line" >>"/tmp/$LOG_NAME" 2>/dev/null || true
}

snapshot() {
  local ts
  ts="$(date -Iseconds)"
  boot_log "=== $ts network-debug ==="
  boot_log "--- iw dev wlan0 link ---"
  iw dev wlan0 link 2>&1 | while read -r l; do boot_log "$l"; done
  boot_log "--- ip addr (wlan0) ---"
  ip -4 addr show wlan0 2>&1 | while read -r l; do boot_log "$l"; done
  boot_log "--- rfkill ---"
  rfkill list 2>&1 | while read -r l; do boot_log "$l"; done
  boot_log "--- dmesg brcmfmac (last 20) ---"
  dmesg 2>/dev/null | grep -i brcmfmac | tail -20 | while read -r l; do boot_log "$l"; done
  boot_log "--- journal wpa (last 50) ---"
  journalctl -u wpa_supplicant -n 50 --no-pager 2>&1 | while read -r l; do boot_log "$l"; done
  journalctl -u NetworkManager -n 30 --no-pager 2>&1 | while read -r l; do boot_log "$l"; done
  sync 2>/dev/null || true
}

done_marker() {
  local m
  for m in $DONE_MARKERS; do
    [[ -f "$m" ]] && return 0
  done
  return 1
}

boot_log "network-debug loop start interval=${INTERVAL}s"
while ! done_marker; do
  snapshot
  sleep "$INTERVAL"
done
boot_log "network-debug loop end (firstboot done)"
