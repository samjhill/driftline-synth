# shellcheck shell=bash
# Disable GhostRoll systemd units so the Waveshare HAT is free for Pi Ambient Synth.
# Source from other scripts: source "$(dirname "$0")/lib_disable_ghostroll.sh"

disable_ghostroll_autostart() {
  local units=() u
  while read -r u _; do
    [[ "$u" == ghostroll* ]] || continue
    [[ "$u" =~ \.(service|timer|socket|path)$ ]] || continue
    units+=("$u")
  done < <(systemctl list-unit-files --no-pager --no-legend 2>/dev/null || true)

  if [[ ${#units[@]} -eq 0 ]]; then
    echo "==> No GhostRoll systemd units found"
    return 0
  fi

  echo "==> Disabling GhostRoll autostart (${#units[@]} units)..."
  for u in "${units[@]}"; do
    sudo systemctl stop "$u" 2>/dev/null || true
    sudo systemctl disable "$u" 2>/dev/null || true
    sudo systemctl mask "$u" 2>/dev/null || true
    echo "    $u: stopped, disabled, masked"
  done

  sudo pkill -f ghostroll-eink-waveshare 2>/dev/null || true
  sudo pkill -f '/usr/local/bin/ghostroll' 2>/dev/null || true
  sudo pkill -f '/usr/local/sbin/ghostroll' 2>/dev/null || true

  mkdir -p /var/lib/pi-ambient-synth 2>/dev/null || true
  date -Iseconds | sudo tee /var/lib/pi-ambient-synth/ghostroll-disabled >/dev/null 2>&1 || true
}
