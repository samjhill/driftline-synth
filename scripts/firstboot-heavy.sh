#!/usr/bin/env bash
# Background first boot: minimal apt, offline venv, FluidSynth + e-ink services.
set -uo pipefail

if [[ -f /etc/pi-ambient-synth/install.env ]]; then
  # shellcheck disable=SC1091
  source /etc/pi-ambient-synth/install.env
fi
PI_USER="${PI_USER:-pi}"
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER="/run/pi-ambient-synth/firstboot-heavy-done"
APT_TIMEOUT="${APT_TIMEOUT:-600}"
PIP_TIMEOUT="${PIP_TIMEOUT:-300}"

# shellcheck source=scripts/lib/firstboot_status.sh
source "$INSTALL_DIR/scripts/lib/firstboot_status.sh"

eink_progress() {
  [[ -d "$INSTALL_DIR" ]] || return 0
  local logfile
  logfile="$(find_boot_tree 2>/dev/null)/boot-logs/firstboot-eink.log"
  [[ -d "$(dirname "$logfile")" ]] || logfile="/var/log/pi-ambient-synth-eink.log"
  local py="$INSTALL_DIR/scripts/eink_display.py"
  local errf
  errf="$(mktemp /tmp/heavy-eink-err.XXXXXX)"
  local rc=0
  {
    echo "=== $(date -Iseconds) HEAVY ==="
    echo "driver: src/eink_official_driver.py command: $*"
  } >>"$logfile"
  PYTHONPATH="$INSTALL_DIR/vendor/waveshare:${PYTHONPATH:-}" \
    python3 "$py" progress "$@" >>"$logfile" 2>"$errf" || rc=$?
  echo "exit code: $rc" >>"$logfile"
  [[ -s "$errf" ]] && cat "$errf" >>"$logfile"
  rm -f "$errf"
  return "$rc"
}

run_apt() {
  local list="$INSTALL_DIR/deploy/pi-v1-apt.list"
  [[ -f "$list" ]] || return 1
  mapfile -t pkgs < <(grep -v '^#' "$list" | grep -v '^[[:space:]]*$' || true)
  [[ ${#pkgs[@]} -gt 0 ]] || return 0
  export DEBIAN_FRONTEND=noninteractive
  timeout "$APT_TIMEOUT" sudo apt-get update -qq || true
  timeout "$APT_TIMEOUT" sudo apt-get install -y -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" "${pkgs[@]}" || return 1
}

if [[ -f "$MARKER" ]]; then
  exit 0
fi

firstboot_log_init
firstboot_status "HEAVY" "start"
firstboot_status "HEAVY_START" ""

if [[ ! -d "$INSTALL_DIR/scripts" ]]; then
  firstboot_status "HEAVY" "missing $INSTALL_DIR — wait for light stage" "fail"
  exit 1
fi

# Internet only needed for apt (offline wheels on SD may skip). Not required for SSH/light.
# shellcheck source=scripts/lib/wifi_state.sh
source "$INSTALL_DIR/scripts/lib/wifi_state.sh" 2>/dev/null || true
_heavy_inet=no
for i in $(seq 1 120); do
  if wifi_internet_reachable 2>/dev/null; then
    _heavy_inet=yes
    firstboot_status "HEAVY" "internet reachable"
    break
  fi
  sleep 2
done
firstboot_status "HEAVY" "internet=$_heavy_inet (apt may use SD wheels if no)"

# PIL/gpio for e-ink service after apt (early BOOT used bootcmd + vendor only).
eink_progress "INSTALL" "APT" || true
firstboot_status "HEAVY" "apt start"
if ! run_apt; then
  firstboot_status "HEAVY" "apt failed (continuing)" "warn"
  eink_progress "INSTALL" "FAILED" || true
else
  firstboot_status "HEAVY" "apt done" "ok"
fi

eink_progress "INSTALL" "PYTHON" || true
firstboot_status "HEAVY" "venv start"
if ! sudo -u "${PI_USER:-pi}" env INSTALL_DIR="$INSTALL_DIR" bash "$INSTALL_DIR/scripts/install-v1-heavy.sh"; then
  firstboot_status "HEAVY" "venv/install failed" "fail"
  eink_progress "INSTALL" "FAILED" || true
else
  firstboot_status "HEAVY" "venv done" "ok"
fi

eink_progress "SYNTH" "START" || true
firstboot_status "HEAVY" "fluidsynth enable"
if [[ -x "$INSTALL_DIR/scripts/pi_enable_fluidsynth_engine.sh" ]]; then
  if ! bash "$INSTALL_DIR/scripts/pi_enable_fluidsynth_engine.sh"; then
    firstboot_status "HEAVY" "fluidsynth enable failed" "warn"
    eink_progress "AUDIO" "FAIL" || true
  fi
fi

if [[ -x "$INSTALL_DIR/scripts/eink_install_systemd.sh" ]]; then
  bash "$INSTALL_DIR/scripts/eink_install_systemd.sh" || true
fi

# Imager user may be sam, not pi — patch systemd units.
if [[ -n "${PI_USER:-}" ]] && [[ "$PI_USER" != "pi" ]]; then
  sudo mkdir -p /etc/systemd/system/pi-ambient-synth-midi.service.d \
    /etc/systemd/system/pi-ambient-synth.service.d \
    /etc/systemd/system/pi-ambient-synth-monitor.service.d
  sudo tee /etc/systemd/system/pi-ambient-synth-midi.service.d/install-user.conf >/dev/null <<EOF
[Service]
User=$PI_USER
Group=$PI_USER
WorkingDirectory=$INSTALL_DIR
Environment=HOME=/home/$PI_USER
ExecStart=$INSTALL_DIR/.venv/bin/python $INSTALL_DIR/scripts/pi_midi_bridge.py
EOF
  for u in pi-ambient-synth pi-ambient-synth-monitor; do
    sudo tee "/etc/systemd/system/${u}.service.d/install-user.conf" >/dev/null <<EOF
[Service]
User=$PI_USER
Group=$PI_USER
WorkingDirectory=$INSTALL_DIR
Environment=HOME=/home/$PI_USER
EOF
  done
  sudo sed -i "s|/home/pi/pi-ambient-synth|$INSTALL_DIR|g" /etc/systemd/system/pi-ambient-synth-eink.service 2>/dev/null || true
  sudo systemctl daemon-reload
fi

sudo systemctl enable pi-ambient-synth-deploy.timer 2>/dev/null || true
sudo systemctl start pi-ambient-synth-deploy.timer 2>/dev/null || true

eink_progress "AUDIO" "OK" || true
firstboot_status "HEAVY" "audio ready" "ok"
eink_progress "EINK" "READY" || true

mkdir -p /run/pi-ambient-synth /var/lib/pi-ambient-synth 2>/dev/null || true
date -Iseconds >"$MARKER" 2>/dev/null || true
date -Iseconds >"/var/lib/pi-ambient-synth/firstboot-heavy-done" 2>/dev/null || true
firstboot_status "HEAVY_DONE" ""
firstboot_status "HEAVY" "done" "ok"
exit 0
