#!/usr/bin/env bash
# Autonomous bring-up — rootfs systemd service only (not cmdline sentinel).
set -uo pipefail

MARKER="/var/lib/pi-ambient-synth/autobringup-done"
HB_FLAG="/run/pi-ambient-synth/autobringup-heartbeat"
HB_PID=""

_ab_boot_log_early() {
  local msg="$1"
  local ok="${2:-ok}"
  for br in /boot/firmware /boot; do
    [[ -d "$br" ]] || continue
    mkdir -p "$br/pi-ambient-synth/boot-logs" 2>/dev/null || true
    echo "$(date -Iseconds) [$ok] $msg" >>"$br/pi-ambient-synth/boot-logs/autobringup.log" 2>/dev/null || true
    echo "$(date -Iseconds) [$ok] AUTBRINGUP $msg" >>"$br/pi-ambient-firstboot-status.txt" 2>/dev/null || true
  done
  sync 2>/dev/null || true
}

# First lines before any sourcing — proves systemd launched the service.
_ab_first_log() {
  for br in /boot/firmware /boot; do
    [[ -d "$br" ]] || continue
    mkdir -p "$br/pi-ambient-synth/boot-logs" 2>/dev/null || true
    echo "$(date -Iseconds) AUTOBRINGUP_START pid=$$" >>"$br/pi-ambient-firstboot-status.txt" 2>/dev/null || true
    echo "$(date -Iseconds) AUTOBRINGUP_START pid=$$" >>"$br/pi-ambient-synth/boot-logs/autobringup.log" 2>/dev/null || true
  done
  sync 2>/dev/null || true
}
_ab_first_log

_ab_heartbeat_loop() {
  while [[ -f "$HB_FLAG" ]]; do
    _ab_boot_log_early "AUTOBRINGUP_HEARTBEAT"
    sleep 10
  done
}

_ab_heartbeat_start() {
  mkdir -p /run/pi-ambient-synth 2>/dev/null || true
  touch "$HB_FLAG"
  _ab_heartbeat_loop &
  HB_PID=$!
}

_ab_heartbeat_stop() {
  rm -f "$HB_FLAG" 2>/dev/null || true
  [[ -n "$HB_PID" ]] && wait "$HB_PID" 2>/dev/null || true
}
APT_TIMEOUT="${APT_TIMEOUT:-600}"
PIP_TIMEOUT="${PIP_TIMEOUT:-300}"
WIFI_WAIT_SEC="${WIFI_WAIT_SEC:-120}"

BOOT_TREE=""
INSTALL_DIR=""
PI_USER=""
INSTALL_HOME=""

_ab_tree() {
  if [[ -n "$BOOT_TREE" ]]; then
    echo "$BOOT_TREE"
    return 0
  fi
  # shellcheck source=scripts/lib/firstboot_status.sh
  for lib in /boot/firmware/pi-ambient-synth/scripts/lib/firstboot_status.sh \
    /boot/pi-ambient-synth/scripts/lib/firstboot_status.sh; do
    if [[ -f "$lib" ]]; then
      # shellcheck disable=SC1090
      source "$lib"
      BOOT_TREE="$(find_boot_tree || true)"
      break
    fi
  done
  echo "$BOOT_TREE"
}

_ab_source_libs() {
  local tree="$(_ab_tree)"
  [[ -n "$tree" ]] || return 1
  BOOT_TREE="$tree"
  # shellcheck disable=SC1091
  source "$tree/scripts/lib/autobringup_status.sh"
  # shellcheck disable=SC1091
  source "$tree/scripts/lib/autobringup_user.sh"
  # shellcheck disable=SC1091
  source "$tree/scripts/lib/eink_exclusive.sh"
  export AUTBRINGUP_INSTALL_DIR="$tree"
  return 0
}

stage_systemd_forensics() {
  autobringup_status "SYSTEMD_FORENSICS" "start"
  autobringup_capture autobringup systemctl --version
  autobringup_capture autobringup systemctl get-default
  autobringup_capture autobringup systemctl show -p ActiveState,SubState,UnitFileState,LoadState \
    pi-ambient-autobringup.service
  autobringup_capture autobringup systemctl status pi-ambient-autobringup.service --no-pager
  autobringup_capture autobringup mount
  autobringup_capture autobringup journalctl -b -u pi-ambient-autobringup.service -n 200 --no-pager
  autobringup_status "SYSTEMD_FORENSICS" "done" "ok" "USER_DETECT"
}

stage_user_detect() {
  autobringup_status "USER_DETECT" "start"
  PI_USER="$(autobringup_detect_user)"
  INSTALL_HOME="/home/${PI_USER}"
  INSTALL_DIR="${INSTALL_HOME}/pi-ambient-synth"
  autobringup_write_install_env "$PI_USER"
  autobringup_set detected_user "$PI_USER"
  autobringup_set install_dir "$INSTALL_DIR"
  autobringup_status "USER_DETECT" "user=$PI_USER dir=$INSTALL_DIR" "ok" "NETWORK_DIAG"
}

stage_rsync() {
  autobringup_status "RSYNC" "start"
  if [[ ! -d "$BOOT_TREE" ]]; then
    autobringup_status "RSYNC" "no boot tree" "fail" "fix SD sync on Mac"
    return 1
  fi
  sudo mkdir -p "$INSTALL_DIR"
  sudo rsync -a --delete \
    --exclude '.venv' --exclude '.git' --exclude 'state' \
    "$BOOT_TREE/" "$INSTALL_DIR/" 2>/dev/null || rsync -a "$BOOT_TREE/" "$INSTALL_DIR/" 2>/dev/null || true
  sudo chown -R "$PI_USER:$PI_USER" "$INSTALL_DIR" 2>/dev/null || true
  autobringup_status "RSYNC" "boot tree → $INSTALL_DIR" "ok" "BOOTFS_WRITE_TEST"
}

stage_network_diag() {
  autobringup_status "NETWORK_DIAG" "start (max ${WIFI_WAIT_SEC}s)"
  autobringup_capture network ip addr show
  autobringup_capture network iw dev wlan0 link
  autobringup_capture network rfkill list
  autobringup_capture network journalctl -u NetworkManager -b -n 100 --no-pager
  autobringup_capture network journalctl -u wpa_supplicant -b -n 100 --no-pager
  autobringup_capture network bash -c 'dmesg | grep -i brcm | tail -80'
  local ip="" ok=warn
  local n=0
  while ((n < WIFI_WAIT_SEC)); do
    ip="$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | head -1 || true)"
    [[ -n "$ip" ]] && ok=pass && break
    sleep 1
    n=$((n + 1))
  done
  autobringup_set wifi_ip "${ip:-none}"
  autobringup_set wifi_ok "$ok"
  autobringup_status "NETWORK_DIAG" "wlan0_ip=${ip:-none}" "$ok" "SSH_ENABLE"
}

stage_ssh_enable() {
  autobringup_status "SSH_ENABLE" "start"
  sudo systemctl enable ssh 2>/dev/null || sudo systemctl enable sshd 2>/dev/null || true
  sudo systemctl start ssh 2>/dev/null || sudo systemctl start sshd 2>/dev/null || true
  local active=fail
  systemctl is-active ssh &>/dev/null && active=pass
  systemctl is-active sshd &>/dev/null && active=pass
  local ip
  ip="$(autobringup_get wifi_ip none)"
  local ssh_mdns="ssh ${PI_USER}@raspberrypi.local"
  local ssh_ip=""
  [[ "$ip" != none && -n "$ip" ]] && ssh_ip="ssh ${PI_USER}@${ip%/*}"
  autobringup_set ssh_cmd_mdns "$ssh_mdns"
  autobringup_set ssh_cmd_ip "$ssh_ip"
  autobringup_set ssh_active "$active"
  autobringup_capture autobringup systemctl status ssh --no-pager
  autobringup_status "SSH_ENABLE" "active=$active try: $ssh_mdns ${ssh_ip:+( $ssh_ip )}" "$active" "EINK_ISOLATED_TEST"
}

stage_eink_isolated_test() {
  autobringup_status "EINK_ISOLATED_TEST" "start"
  local logf
  logf="$(autobringup_log_path eink)"
  if [[ -x "$INSTALL_DIR/scripts/eink_kill_legacy_holders.sh" ]]; then
    INSTALL_DIR="$INSTALL_DIR" bash "$INSTALL_DIR/scripts/eink_kill_legacy_holders.sh" >>"$logf" 2>&1 || true
  fi
  eink_acquire_exclusive "$logf" || autobringup_append_log eink "WARN: exclusive flock failed"
  eink_wait_spidev "$logf" 60 3 || autobringup_append_log eink "WARN: spidev missing"
  local drv result v4=fail v3=fail v2=fail
  for drv in epd2in13_V4 epd2in13_V3 epd2in13_V2; do
    autobringup_append_log eink "=== try $drv ==="
    if timeout 120 bash -c "
      cd '$INSTALL_DIR' && export GPIOZERO_PIN_FACTORY=lgpio HOME='$INSTALL_HOME'
      python3 scripts/eink_official_minimal_test.py $drv
    " >>"$logf" 2>&1; then
      result=pass
      autobringup_append_log eink "EINK_SENT_${drv#epd2in13_} SENT_TO_PANEL"
      case "$drv" in
        epd2in13_V4) v4=pass ;;
        epd2in13_V3) v3=pass ;;
        epd2in13_V2) v2=pass ;;
      esac
      [[ "$drv" == epd2in13_V4 ]] && break
    else
      autobringup_append_log eink "EINK_${drv#epd2in13_}_FAIL exit=$?"
    fi
  done
  autobringup_set eink_v4 "$v4"
  autobringup_set eink_v3 "$v3"
  autobringup_set eink_v2 "$v2"
  sync 2>/dev/null || true
  local ok=fail
  [[ "$v4" == pass || "$v3" == pass || "$v2" == pass ]] && ok=warn
  autobringup_status "EINK_ISOLATED_TEST" "V4=$v4 V3=$v3 V2=$v2 (SENT_TO_PANEL only)" "$ok" "AUDIO_INSTALL"
}

stage_audio_install() {
  autobringup_status "AUDIO_INSTALL" "start"
  local ok=fail
  if [[ ! -f "$INSTALL_DIR/deploy/pi-v1-apt.list" ]]; then
    autobringup_status "AUDIO_INSTALL" "missing pi-v1-apt.list" "fail" "re-sync SD"
    autobringup_set audio_install fail
    return 1
  fi
  export DEBIAN_FRONTEND=noninteractive
  mapfile -t pkgs < <(grep -v '^#' "$INSTALL_DIR/deploy/pi-v1-apt.list" | grep -v '^[[:space:]]*$' || true)
  if [[ ${#pkgs[@]} -gt 0 ]]; then
    timeout "$APT_TIMEOUT" sudo apt-get update -qq >>"$(autobringup_log_path audio)" 2>&1 || true
    if timeout "$APT_TIMEOUT" sudo apt-get install -y -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" "${pkgs[@]}" >>"$(autobringup_log_path audio)" 2>&1; then
      autobringup_append_log audio "apt install ok"
    else
      autobringup_append_log audio "apt install warn (may use SD wheels)"
    fi
  fi
  if sudo -u "$PI_USER" env INSTALL_DIR="$INSTALL_DIR" bash "$INSTALL_DIR/scripts/install-v1-heavy.sh" \
    >>"$(autobringup_log_path audio)" 2>&1; then
    autobringup_append_log audio "install-v1-heavy ok"
  else
    autobringup_append_log audio "install-v1-heavy warn"
  fi
  if bash "$INSTALL_DIR/scripts/pi_enable_fluidsynth_engine.sh" >>"$(autobringup_log_path audio)" 2>&1; then
    ok=pass
  else
    ok=warn
  fi
  local midi_st synth_st mon_st
  midi_st="$(systemctl is-active pi-ambient-synth-midi.service 2>/dev/null || echo unknown)"
  synth_st="$(systemctl is-active pi-ambient-synth.service 2>/dev/null || echo unknown)"
  mon_st="$(systemctl is-active pi-ambient-synth-monitor.service 2>/dev/null || echo unknown)"
  autobringup_set audio_install "$ok"
  autobringup_set fluidsynth_midi "$midi_st"
  autobringup_set fluidsynth_main "$synth_st"
  autobringup_set fluidsynth_monitor "$mon_st"
  autobringup_status "AUDIO_INSTALL" "midi=$midi_st synth=$synth_st" "$ok" "AUDIO_SELF_TEST"
}

stage_audio_self_test() {
  autobringup_status "AUDIO_SELF_TEST" "start"
  local ok=warn
  if [[ -x "$INSTALL_DIR/scripts/fluidsynth_headphone_demo.py" ]]; then
  if timeout 90 sudo -u "$PI_USER" env HOME="$INSTALL_HOME" INSTALL_DIR="$INSTALL_DIR" \
    bash -c "cd '$INSTALL_DIR' && .venv/bin/python scripts/fluidsynth_headphone_demo.py" \
    >>"$(autobringup_log_path audio)" 2>&1; then
    autobringup_append_log audio "AUDIO_SENT_TO_JACK (FluidSynth→ALSA demo ran — user must confirm by ear)"
    ok=warn
  else
    autobringup_append_log audio "AUDIO_SELF_TEST exit non-zero"
    ok=fail
  fi
  else
    autobringup_append_log audio "fluidsynth_headphone_demo.py missing"
    ok=fail
  fi
  autobringup_set audio_self_test "$ok"
  autobringup_status "AUDIO_SELF_TEST" "sent not verified by ear" "$ok" "KEYSTEP_DIAG"
}

stage_keystep_diag() {
  autobringup_status "KEYSTEP_DIAG" "start"
  local ok=warn found=no
  local py="$INSTALL_DIR/.venv/bin/python"
  [[ -x "$py" ]] || py="python3"
  if "$py" "$INSTALL_DIR/scripts/list_midi_devices.py" >>"$(autobringup_log_path audio)" 2>&1; then
    if grep -qiE 'keystep|arturia' "$(autobringup_log_path audio)" 2>/dev/null; then
      found=yes
      ok=pass
      autobringup_append_log audio "KEYSTEP_FOUND"
    else
      autobringup_append_log audio "KEYSTEP_MISSING (no KeyStep/Arturia in port list)"
    fi
  else
    autobringup_append_log audio "KEYSTEP_MISSING (mido/list failed)"
  fi
  autobringup_set keystep "$([[ $found == yes ]] && echo FOUND || echo MISSING)"
  autobringup_status "KEYSTEP_DIAG" "$(autobringup_get keystep MISSING)" "$ok" "APP_ENABLE"
}

stage_app_enable() {
  autobringup_status "APP_ENABLE" "start"
  sudo systemctl enable pi-ambient-synth-monitor.service 2>/dev/null || true
  sudo systemctl start pi-ambient-synth-monitor.service 2>/dev/null || true
  local eink_ok
  eink_ok="$(autobringup_get eink_v4 fail)"
  [[ "$(autobringup_get eink_v3 fail)" == pass ]] && eink_ok=pass
  [[ "$(autobringup_get eink_v2 fail)" == pass ]] && eink_ok=pass
  if [[ "$eink_ok" == pass ]] && [[ -x "$INSTALL_DIR/scripts/eink_install_systemd.sh" ]]; then
    INSTALL_DIR="$INSTALL_DIR" bash "$INSTALL_DIR/scripts/eink_install_systemd.sh" \
      >>"$(autobringup_log_path eink)" 2>&1 || true
    autobringup_status "APP_ENABLE" "e-ink queue enabled after isolated test" "ok"
  else
    sudo systemctl stop pi-ambient-synth-eink.service 2>/dev/null || true
    sudo systemctl disable pi-ambient-synth-eink.service 2>/dev/null || true
    autobringup_status "APP_ENABLE" "e-ink service skipped (isolated test did not pass)" "warn"
  fi
  sudo systemctl restart pi-ambient-synth.service 2>/dev/null || true
  autobringup_status "APP_ENABLE" "monitor on; main --no-eink; no live note display" "ok" "FINAL_REPORT"
}

stage_final_report() {
  autobringup_status "FINAL_REPORT" "writing DRIFTLINE_BRINGUP_REPORT.txt"
  local sentinel user bootfs wifi ssh_v4 ssh_v3 ssh_v2 audio ks next

  sentinel=fail
  bootfs=fail
  for d in /boot/firmware /boot; do
    [[ -f "$d/pi-boot-sentinel.txt" ]] && sentinel=pass
    grep -q 'bootfs writable:' "$d/pi-boot-sentinel.txt" 2>/dev/null && bootfs=pass
  done
  user="$(autobringup_get detected_user unknown)"
  wifi="$(autobringup_get wifi_ip none)"
  v4="$(autobringup_get eink_v4 fail)"
  v3="$(autobringup_get eink_v3 fail)"
  v2="$(autobringup_get eink_v2 fail)"
  audio="$(autobringup_get audio_install fail)"
  midi_st="$(autobringup_get fluidsynth_midi unknown)"
  ks="$(autobringup_get keystep MISSING)"

  next="Power off, insert SD in Mac: ./scripts/read_autobringup_report_mac.sh"
  if [[ "$sentinel" != pass ]]; then
    next="STOP: no Linux userspace. Try FLASH_ARCH=armhf flash, HDMI, PSU, stock Pi OS. Do not debug app."
  elif [[ "$bootfs" != pass ]]; then
    next="Bootfs not writable — check mount; re-flash SD"
  elif [[ "$wifi" == none ]]; then
    next="WiFi failed — fix network-config on Mac, re-sync, boot again. SSH may work on Ethernet."
  elif [[ "$v4" != pass && "$v3" != pass && "$v2" != pass ]]; then
    next="E-ink not sent — check SPI/HAT; run eink_official_minimal_test on Pi with HDMI"
  elif [[ "$audio" == fail ]]; then
    next="Audio install failed — read boot-logs/audio.log; run fluidsynth_headphone_demo on Pi"
  else
    next="Try: $(autobringup_get ssh_cmd_mdns) — confirm headphone audio and e-ink visually"
  fi

  local body
  body="$(cat <<EOF
DRIFTLINE SYNTH — AUTONOMOUS BRING-UP REPORT
Generated: $(date -Iseconds)
Install user: $user ($INSTALL_DIR)

━━━ SUMMARY ━━━
boot sentinel:        $sentinel
bootfs writable:        $bootfs ($(autobringup_get bootfs_path unknown))
WiFi:                   $wifi ($(autobringup_get wifi_ok warn))
SSH:                    $(autobringup_get ssh_active fail)
  try:                  $(autobringup_get ssh_cmd_mdns)
  $(autobringup_get ssh_cmd_ip)

e-ink (SENT_TO_PANEL, not log-only success):
  V4: $v4   V3: $v3   V2: $v2

audio install:          $audio
  pi-ambient-synth-midi: $(autobringup_get fluidsynth_midi)
  pi-ambient-synth:      $(autobringup_get fluidsynth_main)
  monitor:               $(autobringup_get fluidsynth_monitor)
audio self-test:        $(autobringup_get audio_self_test warn) (sent, not verified by ear)

KeyStep:                $ks

━━━ NEXT ACTION ━━━
$next

━━━ LOGS ON SD ━━━
pi-ambient-synth/boot-logs/autobringup.log
pi-ambient-synth/boot-logs/network.log
pi-ambient-synth/boot-logs/eink.log
pi-ambient-synth/boot-logs/audio.log
pi-boot-sentinel.txt
pi-ambient-firstboot-status.txt

Stack: FluidSynth V1 only (no SuperCollider/JACK/GhostRoll).
EOF
)"

  while IFS= read -r bootroot; do
    [[ -d "$bootroot" ]] || continue
    echo "$body" >"$bootroot/DRIFTLINE_BRINGUP_REPORT.txt"
    echo "$body" >"$bootroot/pi-ambient-synth/DRIFTLINE_BRINGUP_REPORT.txt" 2>/dev/null || true
  done < <(autobringup_boot_roots)
  sync 2>/dev/null || true
  autobringup_set next_action "$next"
  autobringup_status "FINAL_REPORT" "done" "ok"
}

main() {
  if [[ -f "$MARKER" ]]; then
    exit 0
  fi
  mkdir -p /run/pi-ambient-synth 2>/dev/null || true
  exec 8>/run/pi-ambient-synth/autobringup.lock
  flock -n 8 || exit 0
  if ! _ab_source_libs; then
    _ab_boot_log_early "boot tree not found" fail
    exit 1
  fi
  _ab_heartbeat_start
  trap '_ab_heartbeat_stop' EXIT

  autobringup_log_init
  autobringup_status "AUTBRINGUP" "systemd service running"

  stage_systemd_forensics
  stage_user_detect
  stage_rsync
  stage_network_diag
  stage_ssh_enable
  stage_eink_isolated_test
  stage_audio_install
  stage_audio_self_test
  stage_keystep_diag
  stage_app_enable
  stage_final_report

  _ab_heartbeat_stop
  sudo mkdir -p /var/lib/pi-ambient-synth
  date -Iseconds | sudo tee "$MARKER" >/dev/null
  sync 2>/dev/null || true
  autobringup_status "AUTBRINGUP" "complete" "ok"
}

main "$@"
