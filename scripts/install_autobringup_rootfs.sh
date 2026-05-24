#!/usr/bin/env bash
# Phase 2 optional: install pi-ambient-autobringup.service on SD ext4 root from macOS.
# Phase 1: use install_autobringup_on_pi.sh on the Pi after SSH (preferred).
# Usage: sudo ./scripts/install_autobringup_rootfs.sh [/Volumes/bootfs]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOT_VOL="${1:-}"
UNIT_NAME="pi-ambient-autobringup.service"
UNIT_SRC="$ROOT/systemd/$UNIT_NAME"
UNIT_ABS="/etc/systemd/system/$UNIT_NAME"
WANTS_ABS="/etc/systemd/system/multi-user.target.wants"
LINK_ABS="$WANTS_ABS/$UNIT_NAME"

export PATH="/opt/homebrew/Cellar/e2tools/0.1.2/bin:/opt/homebrew/opt/e2fsprogs/sbin:/opt/homebrew/bin:$PATH"
DEBUGFS="${DEBUGFS:-$(command -v debugfs 2>/dev/null || true)}"

# shellcheck source=scripts/lib/rootfs_sd_dev.sh
source "$ROOT/scripts/lib/rootfs_sd_dev.sh"

[[ "$(id -u)" -eq 0 ]] || { echo "ERROR: run with sudo" >&2; exit 1; }
for cmd in e2cp e2mkdir e2ln e2ls e2rm; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found (brew install e2tools)" >&2; exit 1; }
done
[[ -n "$DEBUGFS" ]] || { echo "ERROR: debugfs required (brew install e2fsprogs)" >&2; exit 1; }
[[ -f "$UNIT_SRC" ]] || { echo "ERROR: missing $UNIT_SRC" >&2; exit 1; }

DEV="$(rootfs_sd_resolve_dev "$BOOT_VOL")" || { echo "ERROR: no Linux root on SD" >&2; exit 1; }

echo "Installing $UNIT_NAME on $DEV ..."

_dbg_cmd() {
  "$DEBUGFS" -R "$1" "$DEV" 2>&1 | grep -vE '^(debugfs 1\.|ext2fs_close:)' || true
}

_dbg_script() {
  "$DEBUGFS" -w "$DEV" 2>&1 | grep -vE '^(debugfs 1\.|ext2fs_close:)' || true
}

_wants_lists_unit() {
  _dbg_cmd "ls -l $WANTS_ABS" | grep -Fq "$UNIT_NAME"
}

_unit_ok() {
  e2ls "$DEV:$UNIT_ABS" >/dev/null 2>&1 && return 0
  _dbg_cmd "ls -l $UNIT_ABS" | grep -Fq "$UNIT_NAME" && return 0
  return 1
}

_link_ok() {
  e2ls "$DEV:$LINK_ABS" >/dev/null 2>&1 && return 0
  _wants_lists_unit && return 0
  return 1
}

_install_unit_debugfs() {
  if _unit_ok; then
    return 0
  fi
  echo "    writing $UNIT_ABS (debugfs)..."
  local out
  out="$(_dbg_script <<EOF
rm $UNIT_ABS
write $UNIT_SRC $UNIT_ABS
ls -l $UNIT_ABS
quit
EOF
)"
  echo "$out" | sed 's/^/      /' || true
  _unit_ok
}

_install_link_e2ln() {
  e2mkdir "$DEV:$WANTS_ABS" 2>/dev/null || true
  e2rm "$DEV:$LINK_ABS" 2>/dev/null || true
  if e2ln -s "../$UNIT_NAME" "$DEV:$LINK_ABS" 2>/dev/null; then
    echo "    enable symlink (e2ln)"
    return 0
  fi
  return 1
}

# debugfs: use cd into wants — full-path rm/symlink often fails on Trixie ext4 from macOS.
_install_link_debugfs() {
  echo "    enable symlink (debugfs, cd into wants)..."
  local out
  out="$(_dbg_script <<EOF
cd $WANTS_ABS
ls -l
rm $UNIT_NAME
unlink $UNIT_NAME
symlink $UNIT_ABS $UNIT_NAME
ls -l $UNIT_NAME
quit
EOF
)"
  echo "$out" | sed 's/^/      /' || true
  if _link_ok; then
    return 0
  fi
  # Stale dentry: symlink exists for debugfs but wrong for e2ls — try e2ln after forced rm.
  e2rm "$DEV:$LINK_ABS" 2>/dev/null || true
  _install_link_e2ln || _link_ok
}

_install_e2tools() {
  e2rm "$DEV:$UNIT_ABS" 2>/dev/null || true
  if ! e2cp -v -O 0 -G 0 -P 644 "$UNIT_SRC" "$DEV:/etc/systemd/system/"; then
    return 1
  fi
  _install_link_e2ln
}

if _unit_ok && _link_ok; then
  echo "    (already installed)"
elif _install_e2tools && _unit_ok && _link_ok; then
  echo "    (e2tools)"
elif _install_unit_debugfs && _install_link_e2ln && _link_ok; then
  echo "    (debugfs unit + e2ln link)"
elif _install_unit_debugfs && _install_link_debugfs && _link_ok; then
  echo "    (debugfs unit + debugfs link)"
else
  echo "ERROR: could not install unit on root FS." >&2
  echo "  unit OK: $(_unit_ok && echo yes || echo no)" >&2
  echo "  link OK: $(_link_ok && echo yes || echo no)" >&2
  echo "  debugfs unit file:" >&2
  _dbg_cmd "ls -l $UNIT_ABS" | sed 's/^/    /' >&2 || true
  echo "  debugfs wants dir:" >&2
  _dbg_cmd "ls -l $WANTS_ABS" | sed 's/^/    /' >&2 || true
  echo "" >&2
  echo "Workaround: install on the Pi once SSH works:" >&2
  echo "  sudo cp /boot/firmware/pi-ambient-synth/systemd/$UNIT_NAME /etc/systemd/system/" >&2
  echo "  sudo systemctl enable $UNIT_NAME" >&2
  exit 1
fi

e2rm "$DEV:/var/lib/pi-ambient-synth/autobringup-done" 2>/dev/null || true
for v in /Volumes/bootfs /Volumes/boot "${BOOT_VOL:-}"; do
  [[ -d "$v" ]] || continue
  date -Iseconds >"$v/pi-ambient-autobringup-root-installed.txt"
  sync "$v" 2>/dev/null || true
  break
done

echo "OK: $UNIT_NAME installed and enabled (multi-user.target)"
echo "    Unit: $UNIT_ABS"
echo "    Link: $LINK_ABS"
exit 0
