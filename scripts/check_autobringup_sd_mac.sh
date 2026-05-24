#!/usr/bin/env bash
# Pre-boot validation for autonomous bring-up SD.
# Usage: ./scripts/check_autobringup_sd_mac.sh [/Volumes/bootfs]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0
BOOT=""

fail() { echo "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { echo "OK:   $*"; }

resolve_boot() {
  BOOT="${1:-}"
  for v in /Volumes/bootfs /Volumes/boot; do
    [[ -z "$BOOT" && -d "$v" ]] && BOOT="$v"
  done
  [[ -d "$BOOT" ]] || { echo "ERROR: SD boot volume not mounted"; exit 1; }
}

grep_file_must_not() {
  local f="$1" pat="$2" label="$3"
  if grep -qE "$pat" "$f" 2>/dev/null; then
    fail "$label"
  else
    pass "$label (absent)"
  fi
}

resolve_boot "${1:-}"
TREE="$BOOT/pi-ambient-synth"
REF="$ROOT/deploy/user-data.autobringup"

echo "=============================================="
echo " Autobringup SD validation — $BOOT"
echo "=============================================="

[[ -f "$TREE/scripts/pi_ambient_autobringup.sh" ]] && pass "pi_ambient_autobringup.sh" || fail "missing pi_ambient_autobringup.sh"
[[ -x "$TREE/scripts/pi_ambient_autobringup.sh" ]] && pass "autobringup executable" || fail "pi_ambient_autobringup.sh not executable"
[[ -f "$TREE/systemd/pi-ambient-autobringup.service" ]] && pass "pi-ambient-autobringup.service" || fail "missing autobringup unit"
[[ -x "$TREE/scripts/install_autobringup_on_pi.sh" ]] && pass "install_autobringup_on_pi.sh" || fail "missing install_autobringup_on_pi.sh"
[[ -x "$TREE/scripts/validate_autobringup_on_pi.sh" ]] && pass "validate_autobringup_on_pi.sh" || fail "missing validate_autobringup_on_pi.sh"
[[ -f "$TREE/scripts/eink_official_minimal_test.py" ]] && pass "eink_official_minimal_test.py" || fail "missing official e-ink test"
[[ -f "$TREE/scripts/pi_boot_sentinel.sh" ]] && pass "pi_boot_sentinel.sh" || fail "missing boot sentinel script"

if diff -q "$REF" "$BOOT/user-data" >/dev/null 2>&1; then
  pass "user-data matches deploy/user-data.autobringup (SSH only)"
else
  if grep -qE 'install_firstboot_unit|install_autobringup_unit' "$BOOT/user-data" 2>/dev/null; then
    fail "user-data still installs via cloud-init — re-run ./scripts/build_autobringup_sd_mac.sh $BOOT"
  else
    pass "user-data has no cloud-init bring-up install (re-sync recommended)"
  fi
fi
grep_file_must_not "$BOOT/user-data" 'apt-get|packages:' \
  "user-data must not apt install"
grep_file_must_not "$BOOT/user-data" 'supercollider|jackd2|ghostroll|pi-deploy-sync' \
  "user-data must not enable SC/JACK/GhostRoll/bootstrap"

if grep -qE '/home/(pi|sam)/' "$TREE/systemd/pi-ambient-autobringup.service" 2>/dev/null; then
  fail "autobringup unit hardcodes /home/pi or /home/sam"
else
  pass "autobringup unit has no hardcoded home paths"
fi

if grep -qE '/home/(pi|sam)/' "$TREE/scripts/pi_ambient_autobringup.sh" 2>/dev/null; then
  fail "autobringup script hardcodes /home/pi or /home/sam (use detect user)"
else
  pass "autobringup script uses dynamic user detect"
fi

if [[ -f "$TREE/deploy/deploy.conf" ]] && grep -qE '^AUDIO_MODE=fluidsynth' "$TREE/deploy/deploy.conf"; then
  pass "AUDIO_MODE=fluidsynth in deploy.conf"
elif grep -qE '^AUDIO_MODE=fluidsynth' "$TREE/deploy/pi-audio-mode-fluidsynth.conf" 2>/dev/null; then
  fail "deploy.conf missing on SD — re-run ./scripts/build_autobringup_sd_mac.sh $BOOT"
else
  fail "deploy.conf must set AUDIO_MODE=fluidsynth"
fi

APT="$TREE/deploy/pi-v1-apt.list"
if [[ -f "$APT" ]]; then
  _bad_apt=0
  while IFS= read -r pkg; do
    [[ "$pkg" =~ ^# ]] && continue
    [[ -z "${pkg// }" ]] && continue
    if echo "$pkg" | grep -qiE 'supercollider|jackd2|jackd|ghostroll|xvfb|qt5'; then
      fail "pi-v1-apt.list contains forbidden package: $pkg"
      _bad_apt=1
    fi
  done <"$APT"
  [[ $_bad_apt -eq 0 ]] && pass "pi-v1-apt.list excludes SC/JACK/GhostRoll"
fi

export PATH="/opt/homebrew/Cellar/e2tools/0.1.2/bin:/opt/homebrew/bin:${PATH:-}"
_sentinel_root=no
_sentinel_cmd=no
grep -q 'pi_boot_sentinel' "$BOOT/cmdline.txt" 2>/dev/null && _sentinel_cmd=yes && pass "boot sentinel cmdline fallback"
if command -v e2ls >/dev/null 2>&1; then
  DISK="$(diskutil info "$BOOT" 2>/dev/null | awk '/Device Node/ {print $3; exit}')"
  if [[ "$DISK" =~ ^/dev/disk[0-9]+s[0-9]+$ ]]; then
    n="${DISK#\/dev\/disk}"; n="${n%s*}"
    RD="/dev/rdisk${n}s2"
    if e2ls "$RD:/etc/systemd/system/pi-ambient-boot-sentinel.service" >/dev/null 2>&1; then
      _sentinel_root=yes
      pass "boot sentinel on root FS"
    elif [[ "$_sentinel_cmd" != yes ]]; then
      fail "no boot sentinel on root or cmdline — run install_boot_sentinel_rootfs or build with sync"
    fi
    if [[ -f "$BOOT/pi-ambient-autobringup-root-installed.txt" ]]; then
      pass "autobringup root install marker on bootfs ($(head -1 "$BOOT/pi-ambient-autobringup-root-installed.txt" 2>/dev/null))"
    elif e2ls "$RD:/etc/systemd/system/pi-ambient-autobringup.service" >/dev/null 2>&1 \
      && e2ls "$RD:/etc/systemd/system/multi-user.target.wants/pi-ambient-autobringup.service" >/dev/null 2>&1; then
      pass "pi-ambient-autobringup.service on root FS (e2ls, phase 2 factory)"
    elif [[ -f "$TREE/scripts/install_autobringup_on_pi.sh" ]]; then
      pass "phase 1: autobringup on boot tree — install on Pi after SSH (not Mac rootfs)"
    else
      fail "missing install_autobringup_on_pi.sh on boot tree"
    fi
  fi
else
  [[ "$_sentinel_cmd" == yes ]] || fail "e2tools missing; cannot verify root sentinel"
fi

[[ -f "$BOOT/ssh" ]] && pass "ssh enable file" || fail "missing ssh file on boot"
[[ -f "$BOOT/network-config" ]] && pass "network-config on boot" || fail "missing network-config"

echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  echo "RESULT: FAILED ($FAILURES)"
  echo "Fix: sudo ./scripts/fix_autobringup_sd_boot.sh $BOOT"
  echo "  or: sudo ./scripts/wipe_cloud_init_mac.sh && ./scripts/build_autobringup_sd_mac.sh $BOOT"
  exit 1
fi
echo "RESULT: ALL CHECKS PASSED — phase 1 SD ready"
echo "  1. Boot → pi-boot-sentinel.txt + SSH"
echo "  2. On Pi: sudo .../install_autobringup_on_pi.sh && reboot"
echo "  3. Validate: validate_autobringup_on_pi.sh or read_autobringup_report_mac.sh"
exit 0
