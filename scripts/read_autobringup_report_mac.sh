#!/usr/bin/env bash
# Read bring-up report and logs from SD bootfs (after unattended Pi boot).
# Usage: ./scripts/read_autobringup_report_mac.sh [/Volumes/bootfs]
set -uo pipefail

BOOT="${1:-}"
for v in /Volumes/bootfs /Volumes/boot; do
  [[ -z "$BOOT" && -d "$v" ]] && BOOT="$v"
done
if [[ ! -d "$BOOT" ]]; then
  echo "ERROR: boot volume not mounted. Insert SD (Pi off) or pass path." >&2
  exit 1
fi

TREE="$BOOT/pi-ambient-synth"
REPORT="$BOOT/DRIFTLINE_BRINGUP_REPORT.txt"
[[ -f "$REPORT" ]] || REPORT="$TREE/DRIFTLINE_BRINGUP_REPORT.txt"

echo "=============================================="
echo " Driftline autonomous bring-up — Mac readout"
echo " Boot: $BOOT"
echo "=============================================="

if [[ ! -f "$BOOT/pi-boot-sentinel.txt" ]]; then
  echo ""
  echo "CRITICAL: pi-boot-sentinel.txt MISSING"
  echo "  Linux userspace likely never ran on this SD."
  echo "  Next: FLASH_ARCH=armhf ./scripts/flash_sd_mac.sh diskN"
  echo "        HDMI + PSU check; verify Pi boots stock Raspberry Pi OS"
  echo "  Do NOT debug cloud-init, e-ink, or FluidSynth until sentinel exists."
  echo ""
else
  echo ""
  echo "--- pi-boot-sentinel.txt (first 15 lines) ---"
  head -15 "$BOOT/pi-boot-sentinel.txt"
fi

if [[ -f "$REPORT" ]]; then
  echo ""
  echo "--- DRIFTLINE_BRINGUP_REPORT.txt ---"
  cat "$REPORT"
else
  echo ""
  echo "MISSING: DRIFTLINE_BRINGUP_REPORT.txt"
  echo "  Pi may still be booting, autobringup not finished, or wrong SD image."
  echo "  Wait 10–15 min and re-read, or check pi-ambient-firstboot-status.txt"
fi

for log in autobringup network eink audio firstboot-eink; do
  f="$TREE/boot-logs/${log}.log"
  if [[ -f "$f" ]]; then
    echo ""
    echo "--- boot-logs/${log}.log (last 25 lines) ---"
    tail -25 "$f"
  fi
done

if [[ -f "$BOOT/pi-ambient-firstboot-status.txt" ]]; then
  echo ""
  echo "--- pi-ambient-firstboot-status.txt (last 20 lines) ---"
  tail -20 "$BOOT/pi-ambient-firstboot-status.txt"
fi

echo ""
echo "=============================================="
