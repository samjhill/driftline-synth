#!/usr/bin/env bash
# Canonical first boot — systemd-owned state machine (not cloud-init).
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/lib"
RUN_DIR=/run/pi-ambient-synth
DONE_MARKER=/var/lib/pi-ambient-synth/firstboot-done
DONE_RUN="$RUN_DIR/firstboot-done"
NET_DEBUG_PID=""

# shellcheck source=scripts/lib/pi_install_user.sh
source "$LIB/pi_install_user.sh"
# shellcheck source=scripts/lib/firstboot_status.sh
source "$LIB/firstboot_status.sh"
# shellcheck source=scripts/lib/mask_network_wait.sh
source "$LIB/mask_network_wait.sh"
# shellcheck source=scripts/lib/wifi_state.sh
source "$LIB/wifi_state.sh"
# shellcheck source=scripts/lib/wifi_debug_bootfs.sh
source "$LIB/wifi_debug_bootfs.sh"
# shellcheck source=scripts/lib/eink_firstboot_log.sh
source "$LIB/eink_firstboot_log.sh"
# shellcheck source=scripts/lib/eink_exclusive.sh
source "$LIB/eink_exclusive.sh"
# shellcheck source=scripts/lib/firstboot_safe_mode.sh
source "$LIB/firstboot_safe_mode.sh"

PI_USER="$(pi_install_user)"
INSTALL_DIR="${INSTALL_DIR:-$(pi_install_dir)}"
BOOT_TREE="$(find_boot_tree 2>/dev/null || echo "")"
WIFI_WAIT_SEC="${WIFI_WAIT_SEC:-90}"
SSH_HINT="${PI_USER}@raspberrypi.local"
EINK_LOG="$(firstboot_eink_log_path)"

firstboot_state() {
  firstboot_status "${1:-STATE}" "${2:-}"
}

cleanup() {
  [[ -n "$NET_DEBUG_PID" ]] && kill "$NET_DEBUG_PID" 2>/dev/null || true
  firstboot_eink_sync_to_bootfs
}

finish_ok() {
  firstboot_state "FIRSTBOOT_DONE"
  mkdir -p "$(dirname "$DONE_MARKER")" "$RUN_DIR" 2>/dev/null || true
  date -Iseconds >"$DONE_MARKER" 2>/dev/null || true
  date -Iseconds >"$DONE_RUN" 2>/dev/null || true
  echo 0 > /var/lib/pi-ambient-synth/firstboot-fail-count 2>/dev/null || true
  cleanup
  exit 0
}

finish_fail() {
  local rc="${1:-1}"
  local fails
  fails="$(firstboot_record_failure)"
  firstboot_state "FIRSTBOOT_FAIL" "rc=$rc fail_count=$fails" "fail"
  cleanup
  if [[ "$fails" -ge 3 ]]; then
    firstboot_state "SAFE_MODE" "disabling firstboot after $fails failures" "warn"
    firstboot_enter_safe_mode
  fi
  exit "$rc"
}

trap cleanup EXIT

[[ -f "$DONE_MARKER" ]] && exit 0
[[ -f /etc/pi-ambient-synth/firstboot-disabled ]] && exit 0

firstboot_log_init
firstboot_state "BOOT"
firstboot_state "FIRSTBOOT_START"

mask_network_wait_online
systemctl stop pi-ambient-synth-firstboot-heavy.service 2>/dev/null || true
systemctl mask pi-ambient-synth-firstboot-heavy.service 2>/dev/null || true

if [[ -x "$SCRIPT_DIR/firstboot-network-debug.sh" ]]; then
  bash "$SCRIPT_DIR/firstboot-network-debug.sh" &
  NET_DEBUG_PID=$!
fi

# --- POST (known-good minimal test from boot tree, before rsync) ---
firstboot_state "POST_START"
EINK_LOG="$(firstboot_eink_log_path)"
if ! eink_acquire_exclusive "$EINK_LOG"; then
  firstboot_state "POST_EXCLUSIVE" "flock busy" "warn"
fi
if ! eink_wait_spidev "$EINK_LOG" 90 5; then
  firstboot_state "POST_SPI" "spidev missing" "warn"
fi

_post_rc=127
_post_tree=""
for d in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth "$INSTALL_DIR"; do
  [[ -x "$d/scripts/eink_official_minimal_test.py" ]] || continue
  _post_tree="$d"
  firstboot_eink_run_minimal_test "$d" || _post_rc=$?
  break
done
if [[ -z "$_post_tree" ]]; then
  firstboot_state "POST_DONE" "minimal test script missing rc=127" "fail"
else
  firstboot_state "POST_DONE" "rc=${_post_rc} tree=${_post_tree}"
fi

# --- SPI + rsync ---
firstboot_state "RSYNC_START"
_spi_rc=0
if command -v raspi-config >/dev/null; then
  raspi-config nonint do_spi 0 || _spi_rc=$?
fi
pi_write_install_env
sudo mkdir -p "$INSTALL_DIR" "$RUN_DIR"
sudo chown "$PI_USER:$PI_USER" "$INSTALL_DIR" 2>/dev/null || true

[[ -z "$BOOT_TREE" ]] && BOOT_TREE="$(find_boot_tree 2>/dev/null || true)"
_rsync_rc=0
if [[ -n "$BOOT_TREE" ]]; then
  rsync -a --exclude '.git' --exclude 'state' --exclude '__pycache__' \
    "$BOOT_TREE/" "$INSTALL_DIR/" || _rsync_rc=$?
  sudo chown -R "$PI_USER:$PI_USER" "$INSTALL_DIR" 2>/dev/null || true
else
  _rsync_rc=2
fi
firstboot_state "RSYNC_DONE" "rc=${_rsync_rc}"

for u in pi-ambient-synth-firstboot-heavy.service \
  pi-ambient-synth-deploy.service pi-ambient-synth-deploy.timer; do
  [[ -f "$INSTALL_DIR/systemd/$u" ]] && \
    cp "$INSTALL_DIR/systemd/$u" /etc/systemd/system/ 2>/dev/null || true
done
[[ -f "$INSTALL_DIR/systemd/pi-ambient-firstboot.service" ]] && \
  cp "$INSTALL_DIR/systemd/pi-ambient-firstboot.service" /etc/systemd/system/ 2>/dev/null || true
sudo systemctl daemon-reload 2>/dev/null || true

# --- SSH (verify only — cloud-init / image should have enabled already) ---
firstboot_state "SSH_READY" "check"
_ssh_rc=0
sudo systemctl enable ssh 2>/dev/null || sudo systemctl enable sshd 2>/dev/null || true
sudo systemctl start ssh 2>/dev/null || sudo systemctl start sshd 2>/dev/null || _ssh_rc=$?
_ssh_listen=no
wifi_ssh_listening && _ssh_listen=yes
firstboot_state "SSH_READY" "listen=${_ssh_listen} enable_rc=${_ssh_rc} hint=${SSH_HINT}"

# --- WiFi wait ---
firstboot_state "WIFI_WAIT" "0/${WIFI_WAIT_SEC}"
_wlan_ip=no
for _i in $(seq 1 "$WIFI_WAIT_SEC"); do
  wifi_wlan_has_ipv4 && _wlan_ip=yes
  if [[ "$_wlan_ip" == yes ]]; then
    firstboot_state "WIFI_OK" "ip=$(wifi_wlan_ipv4 2>/dev/null || echo ?)"
    break
  fi
  if ((_i % 5 == 0)); then
    _assoc=no
    wifi_wlan_associated && _assoc=yes
    firstboot_state "WIFI_WAIT" "${_i}/${WIFI_WAIT_SEC} assoc=${_assoc}"
  fi
  sleep 1
done
if [[ "$_wlan_ip" != yes ]]; then
  firstboot_state "WIFI_OK" "no_ipv4 (continuing)" "warn"
fi
write_wifi_debug_bootfs >/dev/null 2>&1 || true

# --- Heavy ---
firstboot_state "HEAVY_START"
sudo systemctl unmask pi-ambient-synth-firstboot-heavy.service 2>/dev/null || true
sudo systemctl enable pi-ambient-synth-firstboot-heavy.service 2>/dev/null || true
sudo systemctl start pi-ambient-synth-firstboot-heavy.service 2>/dev/null || true

_heavy_wait=0
while [[ _heavy_wait -lt 3600 ]]; do
  [[ -f /run/pi-ambient-synth/firstboot-heavy-done ]] && break
  [[ -f /var/lib/pi-ambient-synth/firstboot-heavy-done ]] && break
  sleep 5
  _heavy_wait=$((_heavy_wait + 5))
  if ((_heavy_wait % 60 == 0)); then
    firstboot_state "HEAVY_START" "waiting ${_heavy_wait}s"
  fi
done
if [[ -f /run/pi-ambient-synth/firstboot-heavy-done ]] || \
   [[ -f /var/lib/pi-ambient-synth/firstboot-heavy-done ]]; then
  firstboot_state "HEAVY_DONE"
else
  firstboot_state "HEAVY_DONE" "timeout or still running" "warn"
fi

finish_ok
