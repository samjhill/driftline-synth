# shellcheck shell=bash
# Autonomous bring-up logging — all artifacts on bootfs for Mac forensics.

AUTBRINGUP_LOG_DIR="/var/log/pi-ambient-synth"
AUTBRINGUP_STATE="/run/pi-ambient-synth/autobringup-state.env"

autobringup_boot_roots() {
  printf '%s\n' /boot/firmware /boot
}

autobringup_tree() {
  for d in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
    if [[ -d "$d/scripts" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

autobringup_log_init() {
  sudo mkdir -p "$AUTBRINGUP_LOG_DIR" /var/lib/pi-ambient-synth /run/pi-ambient-synth 2>/dev/null || true
  : >"$AUTBRINGUP_STATE" 2>/dev/null || true
  chmod 666 "$AUTBRINGUP_STATE" 2>/dev/null || true
}

autobringup_set() {
  local key="$1" val="$2"
  val="${val//$'\n'/ }"
  if grep -q "^${key}=" "$AUTBRINGUP_STATE" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$AUTBRINGUP_STATE" 2>/dev/null || true
  else
    echo "${key}=${val}" >>"$AUTBRINGUP_STATE"
  fi
}

autobringup_get() {
  local key="$1" default="${2:-}"
  local line
  line="$(grep "^${key}=" "$AUTBRINGUP_STATE" 2>/dev/null | tail -1 || true)"
  if [[ -n "$line" ]]; then
    echo "${line#*=}"
  else
    echo "$default"
  fi
}

autobringup_log_path() {
  local which="${1:-autobringup}"
  local tree
  tree="$(autobringup_tree)"
  if [[ -n "$tree" ]]; then
    echo "$tree/boot-logs/${which}.log"
    return 0
  fi
  echo "$AUTBRINGUP_LOG_DIR/${which}.log"
}

autobringup_append_log() {
  local which="$1"
  local msg="$2"
  local path
  path="$(autobringup_log_path "$which")"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  echo "$(date -Iseconds) $msg" >>"$path" 2>/dev/null || true
  echo "$(date -Iseconds) $msg" | sudo tee -a "$AUTBRINGUP_LOG_DIR/${which}.log" >/dev/null 2>&1 || true
}

autobringup_status() {
  local phase="${1:-INFO}"
  local msg="${2:-}"
  local ok="${3:-ok}"
  local next="${4:-}"
  local line
  line="$(date -Iseconds) [$ok] $phase ${msg}"
  [[ -n "$next" ]] && line+=" | next: $next"
  echo "$line" | sudo tee -a "$AUTBRINGUP_LOG_DIR/autobringup.log" >/dev/null 2>&1 || true
  autobringup_append_log autobringup "$line"
  while IFS= read -r bootroot; do
    [[ -d "$bootroot" ]] || continue
    echo "$line" >>"$bootroot/pi-ambient-firstboot-status.txt" 2>/dev/null || true
    mkdir -p "$bootroot/pi-ambient-synth/boot-logs" 2>/dev/null || true
    echo "$line" >>"$bootroot/pi-ambient-synth/boot-logs/autobringup.log" 2>/dev/null || true
  done < <(autobringup_boot_roots)
  autobringup_set "last_phase" "$phase"
  autobringup_set "last_status" "$ok"
  sync 2>/dev/null || true
}

autobringup_capture() {
  local logname="$1"
  shift
  local path
  path="$(autobringup_log_path "$logname")"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  {
    echo "=== $(date -Iseconds) $* ==="
    "$@" 2>&1 || true
  } >>"$path" 2>/dev/null || true
  sync "$(dirname "$path")" 2>/dev/null || sync 2>/dev/null || true
}
