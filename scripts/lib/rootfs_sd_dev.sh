# shellcheck shell=bash
# Resolve SD Linux root block device from boot volume (Mac).

rootfs_sd_resolve_dev() {
  local boot_vol="${1:-}"
  local disk="" boot_dev

  if [[ -z "$boot_vol" ]]; then
    for v in /Volumes/bootfs /Volumes/boot; do
      [[ -d "$v" ]] && boot_vol="$v" && break
    done
  fi
  if [[ -n "$boot_vol" ]]; then
    boot_dev="$(diskutil info "$boot_vol" 2>/dev/null | awk '/Device Node/ {print $3; exit}')"
    if [[ "$boot_dev" =~ ^/dev/disk[0-9]+s[0-9]+$ ]]; then
      disk="${boot_dev#\/dev\/disk}"
      disk="${disk%s*}"
      echo "/dev/rdisk${disk}s2"
      return 0
    fi
  fi
  disk="$(diskutil list external 2>/dev/null | awk '/Linux/ {print $NF; exit}')"
  if [[ -n "$disk" ]]; then
    echo "/dev/r${disk#*/}"
    return 0
  fi
  return 1
}
