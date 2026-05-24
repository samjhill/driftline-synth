# shellcheck shell=bash
# Append first-boot progress to log + boot partition (readable from Mac when SD inserted).

firstboot_log_init() {
  sudo mkdir -p /var/log /var/lib/pi-ambient-synth /run/pi-ambient-synth 2>/dev/null || true
  sudo touch /var/log/pi-ambient-synth-firstboot.log 2>/dev/null || true
  sudo chmod 666 /var/log/pi-ambient-synth-firstboot.log 2>/dev/null || true
}

firstboot_status() {
  local phase="${1:-INFO}"
  local msg="${2:-}"
  local ok="${3:-ok}"
  local line
  line="$(date -Iseconds) [$ok] $phase ${msg}"
  echo "$line" | sudo tee -a /var/log/pi-ambient-synth-firstboot.log >/dev/null 2>&1 || true
  for bootroot in /boot/firmware /boot; do
    if [[ -d "$bootroot" ]]; then
      echo "$line" >>"$bootroot/pi-ambient-firstboot-status.txt" 2>/dev/null || true
      mkdir -p "$bootroot/pi-ambient-synth/boot-logs" 2>/dev/null || true
      echo "$line" >>"$bootroot/pi-ambient-synth/boot-logs/firstboot-status.txt" 2>/dev/null || true
    fi
  done
}

find_boot_tree() {
  for d in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
    if [[ -d "$d/scripts" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}
