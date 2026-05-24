#!/usr/bin/env bash
# Install and start pi-ambient-autobringup under normal Linux systemd (run on the Pi).
# Usage:
#   sudo ./scripts/install_autobringup_on_pi.sh
#   sudo ./scripts/install_autobringup_on_pi.sh --reset   # clear done marker and re-run
set -euo pipefail

RESET=0
[[ "${1:-}" == "--reset" ]] && RESET=1

[[ "$(id -u)" -eq 0 ]] || { echo "ERROR: run as root (sudo)" >&2; exit 1; }

_boot_log() {
  local msg="$1"
  local ok="${2:-ok}"
  for b in /boot/firmware /boot; do
    [[ -d "$b" ]] || continue
    mkdir -p "$b/pi-ambient-synth/boot-logs" 2>/dev/null || true
    echo "$(date -Iseconds) [$ok] $msg" >>"$b/pi-ambient-synth/boot-logs/autobringup.log" 2>/dev/null || true
    echo "$(date -Iseconds) [$ok] INSTALL_ON_PI $msg" >>"$b/pi-ambient-firstboot-status.txt" 2>/dev/null || true
  done
  sync 2>/dev/null || true
}

UNIT_NAME="pi-ambient-autobringup.service"
UNIT_SRC=""
for d in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
  if [[ -f "$d/systemd/$UNIT_NAME" ]]; then
    UNIT_SRC="$d/systemd/$UNIT_NAME"
    break
  fi
done
[[ -n "$UNIT_SRC" ]] || {
  echo "ERROR: $UNIT_NAME not found on boot partition (sync SD from Mac first)" >&2
  exit 1
}

if [[ "$RESET" == 1 ]]; then
  rm -f /var/lib/pi-ambient-synth/autobringup-done
  _boot_log "autobringup-done marker cleared (--reset)"
fi

cp "$UNIT_SRC" "/etc/systemd/system/$UNIT_NAME"
chmod 644 "/etc/systemd/system/$UNIT_NAME"

systemctl disable pi-ambient-firstboot.service 2>/dev/null || true
systemctl stop pi-ambient-firstboot.service 2>/dev/null || true
mkdir -p /etc/pi-ambient-synth
touch /etc/pi-ambient-synth/firstboot-disabled

systemctl daemon-reload
systemctl enable "$UNIT_NAME"
systemctl start "$UNIT_NAME"

_boot_log "installed $UNIT_SRC → /etc/systemd/system/; enable --now"

echo "OK: $UNIT_NAME installed and started"
systemctl --no-pager status "$UNIT_NAME" || true
echo ""
echo "After one full run (~10–15 min), validate:"
echo "  sudo ./scripts/validate_autobringup_on_pi.sh"
echo "Or power off and read SD on Mac:"
echo "  ./scripts/read_autobringup_report_mac.sh /Volumes/bootfs"
