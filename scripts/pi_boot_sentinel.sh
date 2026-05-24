#!/usr/bin/env bash
# Cmdline sentinel ONLY: boot proof, bootfs probe, autobringup unit status (read-only).
# Does not install or enable autobringup — use install_autobringup_on_pi.sh after SSH.
set +e

STAMP="$(date -Iseconds 2>/dev/null || date)"
UNAME="$(uname -a 2>/dev/null || echo uname-failed)"
UNIT_NAME="pi-ambient-autobringup.service"
UNIT_PATH="/etc/systemd/system/$UNIT_NAME"
WANTS_PATH="/etc/systemd/system/multi-user.target.wants/$UNIT_NAME"

_sentinel_append() {
  local line="$1"
  for d in /boot/firmware /boot; do
    [[ -d "$d" ]] || continue
    echo "$line" >>"$d/pi-boot-sentinel.txt" 2>/dev/null || true
  done
}

_sentinel_append "=== $STAMP sentinel ==="
_sentinel_append "$UNAME"

# Bootfs writable probe
BOOTFS_OK=no
PROBE="sentinel-probe-$$"
for d in /boot/firmware /boot; do
  [[ -d "$d" ]] || continue
  if echo "probe $STAMP" >"$d/$PROBE" 2>/dev/null && grep -q probe "$d/$PROBE" 2>/dev/null; then
    rm -f "$d/$PROBE" 2>/dev/null
    BOOTFS_OK=yes
    _sentinel_append "bootfs writable: $d"
  else
    _sentinel_append "bootfs NOT writable: $d"
  fi
done

_sentinel_append "--- mount (boot-related) ---"
mount 2>/dev/null | grep -E 'boot|firmware' | while read -r line; do
  _sentinel_append "$line"
done

# Autobringup unit on rootfs (normal lifecycle — not started from here)
SCRIPT=""
for d in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
  if [[ -x "$d/scripts/pi_ambient_autobringup.sh" ]]; then
    SCRIPT="$d/scripts/pi_ambient_autobringup.sh"
    break
  fi
done

if [[ -f "$UNIT_PATH" ]]; then
  _sentinel_append "autobringup unit: present ($UNIT_PATH)"
else
  _sentinel_append "autobringup unit: MISSING (install on Pi: sudo .../install_autobringup_on_pi.sh)"
fi

if [[ -L "$WANTS_PATH" ]] || [[ -e "$WANTS_PATH" ]]; then
  _sentinel_append "autobringup enabled: yes ($WANTS_PATH)"
else
  _sentinel_append "autobringup enabled: no (expected until install_autobringup_on_pi.sh)"
fi

if [[ -n "$SCRIPT" ]]; then
  _sentinel_append "autobringup script: executable $SCRIPT"
else
  _sentinel_append "autobringup script: MISSING on boot partition"
fi

if command -v systemctl >/dev/null 2>&1 && [[ -f "$UNIT_PATH" ]]; then
  st="$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || echo unknown)"
  ac="$(systemctl is-active "$UNIT_NAME" 2>/dev/null || echo unknown)"
  _sentinel_append "autobringup systemctl: enabled=$st active=$ac (starts at multi-user)"
fi

_sentinel_append "--- cmdline ---"
for d in /boot/firmware /boot; do
  [[ -f "$d/cmdline.txt" ]] && cat "$d/cmdline.txt" 2>/dev/null | head -1 | while read -r line; do
    _sentinel_append "$line"
  done && break
done

mkdir -p /var/lib/pi-ambient-synth 2>/dev/null || true
date -Iseconds > /var/lib/pi-ambient-synth/boot-sentinel-done 2>/dev/null || true
sync 2>/dev/null || true

if [[ "$BOOTFS_OK" != yes ]]; then
  echo "pi_boot_sentinel: bootfs not writable" >&2
  exit 1
fi
exit 0
