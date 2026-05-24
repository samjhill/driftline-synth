# shellcheck shell=bash
# Log e-ink to /tmp (always works) and copy to bootfs for Mac forensics.

firstboot_eink_log_path() {
  echo "/tmp/firstboot-eink.log"
}

firstboot_eink_bootfs_log_path() {
  for d in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
    if [[ -d "$d/scripts" ]]; then
      echo "$d/boot-logs/firstboot-eink.log"
      return 0
    fi
  done
  echo ""
}

firstboot_eink_sync_to_bootfs() {
  local bootlog
  bootlog="$(firstboot_eink_bootfs_log_path)"
  [[ -n "$bootlog" ]] || return 0
  mkdir -p "$(dirname "$bootlog")" 2>/dev/null || true
  if [[ -f /tmp/firstboot-eink.log ]]; then
    cp -f /tmp/firstboot-eink.log "$bootlog" 2>/dev/null || true
    sync "$bootlog" 2>/dev/null || sync
  fi
}

# Run exact known-good minimal test from install dir (not bootfs, not wrapper).
firstboot_eink_run_minimal_test() {
  local install_dir="${1:?install dir}"
  local logfile
  logfile="$(firstboot_eink_log_path)"
  : >"$logfile"

  local minimal="$install_dir/scripts/eink_official_minimal_test.py"
  local errf
  errf="$(mktemp /tmp/firstboot-eink-err.XXXXXX 2>/dev/null || echo /tmp/firstboot-eink-err.$$)"
  local rc=0

  {
    echo "=== $(date -Iseconds) ==="
    echo "path: known-good eink_official_minimal_test.py (standalone)"
    echo "cwd: $install_dir"
    echo "command: cd $install_dir && python3 scripts/eink_official_minimal_test.py epd2in13_V4"
    echo "spidev: $([[ -e /dev/spidev0.0 ]] && echo present || echo missing)"
    echo "uid: $(id -u) user: $(id -un 2>/dev/null || echo ?)"
  } >>"$logfile"
  sync "$logfile" 2>/dev/null || true

  _run_minimal() {
    cd "$install_dir" || return 127
    export HOME="${HOME:-/home/pi}"
    export GPIOZERO_PIN_FACTORY=lgpio
    unset EINK_VALIDATE_BUSY
    python3 scripts/eink_official_minimal_test.py epd2in13_V4
  }

  if [[ "$(id -u)" -eq 0 ]]; then
    timeout 120 _run_minimal >>"$logfile" 2>"$errf" || rc=$?
  else
    timeout 120 sudo -E env HOME="${HOME:-/home/pi}" GPIOZERO_PIN_FACTORY=lgpio \
      bash -c "cd '$install_dir' && python3 scripts/eink_official_minimal_test.py epd2in13_V4" \
      >>"$logfile" 2>"$errf" || rc=$?
  fi
  [[ "$rc" -eq 124 ]] && echo "FAIL: minimal test timeout 120s" >>"$logfile"

  {
    echo "exit code: $rc"
    echo "stderr:"
    if [[ -s "$errf" ]]; then
      cat "$errf"
    else
      echo "(empty)"
    fi
  } >>"$logfile"
  rm -f "$errf"
  sync "$logfile" 2>/dev/null || true
  firstboot_eink_sync_to_bootfs
  return "$rc"
}
