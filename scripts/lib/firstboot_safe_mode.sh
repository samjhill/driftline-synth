# shellcheck shell=bash

firstboot_record_failure() {
  local f=/var/lib/pi-ambient-synth/firstboot-fail-count
  mkdir -p /var/lib/pi-ambient-synth 2>/dev/null || true
  local n=0
  [[ -f "$f" ]] && n="$(cat "$f" 2>/dev/null || echo 0)"
  n=$((n + 1))
  echo "$n" >"$f"
  echo "$n"
}

firstboot_enter_safe_mode() {
  mkdir -p /etc/pi-ambient-synth 2>/dev/null || true
  date -Iseconds > /etc/pi-ambient-synth/firstboot-disabled 2>/dev/null || true
  systemctl disable pi-ambient-firstboot.service 2>/dev/null || true
  systemctl stop pi-ambient-firstboot.service 2>/dev/null || true
  local tree
  tree="$(find_boot_tree 2>/dev/null || echo /boot/firmware/pi-ambient-synth)"
  if [[ -x "$tree/scripts/eink_official_minimal_test.py" ]]; then
    (
      cd "$tree" && HOME=/home/pi GPIOZERO_PIN_FACTORY=lgpio \
        python3 -c "
import sys
sys.path.insert(0, 'vendor/waveshare')
# Best-effort: run minimal test once; panel may show B/W flashes
import subprocess
subprocess.run([sys.executable, 'scripts/eink_official_minimal_test.py', 'epd2in13_V4'], timeout=120)
" 2>/dev/null
    ) || true
  fi
}
