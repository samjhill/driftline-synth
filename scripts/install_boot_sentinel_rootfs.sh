#!/usr/bin/env bash
# Install pi-ambient-boot-sentinel.service into SD root FS (no cloud-init).
# Usage: sudo ./scripts/install_boot_sentinel_rootfs.sh [/Volumes/bootfs]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOT_VOL="${1:-}"
UNIT_NAME="pi-ambient-boot-sentinel.service"
UNIT_SRC="$ROOT/systemd/$UNIT_NAME"

export PATH="/opt/homebrew/Cellar/e2tools/0.1.2/bin:/opt/homebrew/opt/e2fsprogs/sbin:/opt/homebrew/bin:$PATH"
DEBUGFS="${DEBUGFS:-$(command -v debugfs 2>/dev/null || true)}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run with sudo (raw SD root partition access)" >&2
  exit 1
fi

for cmd in e2cp e2mkdir e2ln e2ls e2rm; do
  command -v "$cmd" >/dev/null || {
    echo "ERROR: $cmd not found (brew install e2tools)" >&2
    exit 1
  }
done

if [[ -z "$BOOT_VOL" ]]; then
  for v in /Volumes/bootfs /Volumes/boot; do
    [[ -d "$v" ]] && BOOT_VOL="$v" && break
  done
fi

DISK=""
if [[ -n "$BOOT_VOL" ]]; then
  BOOT_DEV="$(diskutil info "$BOOT_VOL" 2>/dev/null | awk '/Device Node/ {print $3; exit}')"
  if [[ "$BOOT_DEV" =~ ^/dev/disk[0-9]+s[0-9]+$ ]]; then
    DISK_NUM="${BOOT_DEV#\/dev\/disk}"
    DISK_NUM="${DISK_NUM%s*}"
    DISK="disk${DISK_NUM}s2"
  fi
fi
if [[ -z "$DISK" ]]; then
  DISK="$(diskutil list external 2>/dev/null | awk '/Linux/ {print $NF; exit}')"
fi
[[ -n "$DISK" ]] || { echo "ERROR: no Linux root partition on SD" >&2; exit 1; }

DEV="/dev/r${DISK#*/}"
[[ -f "$UNIT_SRC" ]] || { echo "ERROR: missing $UNIT_SRC" >&2; exit 1; }

echo "Installing boot sentinel on $DEV (root FS)..."

if ! e2ls "$DEV:/etc/systemd/system" >/dev/null 2>&1; then
  echo "ERROR: cannot read $DEV:/etc/systemd/system" >&2
  echo "  • Eject bootfs in Finder (only one volume mounted is OK)" >&2
  echo "  • System Settings → Privacy → Full Disk Access → enable Terminal/iTerm" >&2
  echo "  • Or use cmdline fallback: ./scripts/install_boot_sentinel_cmdline.sh $BOOT_VOL" >&2
  exit 1
fi

_install_e2tools() {
  local dest_dir="/etc/systemd/system"
  local wants="/etc/systemd/system/basic.target.wants"
  e2rm "$DEV:$dest_dir/$UNIT_NAME" 2>/dev/null || true
  # Destination must be a directory (not a full file path) for reliable e2cp on ext4.
  if ! e2cp -v -O 0 -G 0 -P 644 "$UNIT_SRC" "$DEV:$dest_dir/"; then
    return 1
  fi
  e2mkdir "$DEV:$wants" 2>/dev/null || true
  e2rm "$DEV:$wants/$UNIT_NAME" 2>/dev/null || true
  e2ln -s "../$UNIT_NAME" "$DEV:$wants/$UNIT_NAME"
  return 0
}

_install_debugfs() {
  [[ -n "$DEBUGFS" ]] || {
    echo "ERROR: debugfs not found (brew install e2fsprogs)" >&2
    return 1
  }
  local unit_path="/etc/systemd/system/$UNIT_NAME"
  local wants="/etc/systemd/system/basic.target.wants"
  local link_path="$wants/$UNIT_NAME"

  if e2ls "$DEV:$unit_path" >/dev/null 2>&1 && e2ls "$DEV:$link_path" >/dev/null 2>&1; then
    echo "    (debugfs: unit + enable symlink already present)"
    return 0
  fi

  local dbg_out
  dbg_out="$("$DEBUGFS" -w "$DEV" <<EOF 2>&1 || true
rm $unit_path
write $UNIT_SRC $unit_path
mkdir $wants
rm $link_path
symlink $unit_path $link_path
quit
EOF
)"
  # Ignore benign re-run noise; surface real failures.
  if ! e2ls "$DEV:$unit_path" >/dev/null 2>&1; then
    echo "$dbg_out" | grep -vE '^(debugfs 1\.|ext2fs_close:)' >&2 || true
    return 1
  fi
  if e2ls "$DEV:$link_path" >/dev/null 2>&1; then
    if echo "$dbg_out" | grep -q 'Ext2 file already exists'; then
      echo "    (debugfs: symlink already existed — OK)"
    fi
    return 0
  fi
  echo "$dbg_out" | grep -vE '^(debugfs 1\.|ext2fs_close:)' >&2 || true
  return 1
}

if _install_e2tools; then
  echo "    (e2tools)"
elif _install_debugfs; then
  echo "    (debugfs — e2cp failed on this ext4 volume)"
else
  echo "" >&2
  echo "ERROR: could not install unit on root FS (e2cp and debugfs failed)." >&2
  echo "Use cmdline fallback (still proves Linux boot):" >&2
  echo "  ./scripts/install_boot_sentinel_cmdline.sh ${BOOT_VOL:-/Volumes/bootfs}" >&2
  exit 1
fi

if ! e2ls "$DEV:/etc/systemd/system/$UNIT_NAME" >/dev/null 2>&1; then
  echo "ERROR: install reported OK but unit not visible on $DEV" >&2
  exit 1
fi

WANTS_LINK="/etc/systemd/system/basic.target.wants/$UNIT_NAME"
if e2ls "$DEV:$WANTS_LINK" >/dev/null 2>&1; then
  echo "OK:   enabled at $WANTS_LINK"
else
  echo "WARN: unit file present but $WANTS_LINK missing — cmdline sentinel still works if configured"
fi

e2rm "$DEV:/var/lib/pi-ambient-synth/boot-sentinel-done" 2>/dev/null || true

echo "OK: $UNIT_NAME on root FS (WantedBy=basic.target)"
echo "    Boot script on FAT: pi-ambient-synth/scripts/pi_boot_sentinel.sh"
echo "    After Pi boot, read: ${BOOT_VOL:-/Volumes/bootfs}/pi-boot-sentinel.txt"
