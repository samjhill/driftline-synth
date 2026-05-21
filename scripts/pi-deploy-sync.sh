#!/usr/bin/env bash
# Deploy pi-ambient-synth from GitHub (auto-pull) or boot partition.
# Usage: pi-deploy-sync.sh [bootstrap|sync|check]
set -euo pipefail

MODE="${1:-sync}"
LOG_TAG="pi-deploy-sync"
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="/var/lib/pi-ambient-synth"
PERSIST_CONF="/etc/pi-ambient-synth/deploy.conf"
LOG_FILE="/var/log/pi-ambient-synth-deploy.log"
DEPLOY_CONF_NAME="deploy/deploy.conf"
EINK_STATUS_FILE="$MARKER_DIR/last_eink_status"

log() { echo "$(date -Iseconds) [$LOG_TAG] $*" | tee -a "$LOG_FILE"; }

eink_status() {
  local phase="$1" title="$2" subtitle="${3:-}" detail="${4:-}"
  local key="${phase}|${title}|${subtitle}|${detail}"
  local boot_disp

  mkdir -p "$MARKER_DIR"
  if [[ "${EINK_FORCE:-0}" != "1" && -f "$EINK_STATUS_FILE" ]] && [[ "$(cat "$EINK_STATUS_FILE")" == "$key" ]]; then
    return 0
  fi
  echo "$key" > "$EINK_STATUS_FILE"

  for boot_disp in \
    "$INSTALL_DIR/scripts/boot_display.sh" \
    /boot/firmware/pi-ambient-synth/scripts/boot_display.sh \
    /boot/pi-ambient-synth/scripts/boot_display.sh; do
    if [[ -x "$boot_disp" ]]; then
      if [[ "${INSTALL_FIRST_BOOT:-0}" == "1" || "$MODE" == "bootstrap" ]]; then
        export FIRST_BOOT_TRACK=1
        export FIRST_BOOT_TOTAL="${FIRST_BOOT_TOTAL:-12}"
        "$boot_disp" "$phase" "$title" "$subtitle" "$detail" || true
        return 0
      fi
      break
    fi
  done

  local script py
  script="$INSTALL_DIR/scripts/show_status.py"
  if [[ ! -f "$script" ]]; then
    local b
    for b in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
      if [[ -f "$b/scripts/show_status.py" ]]; then
        script="$b/scripts/show_status.py"
        break
      fi
    done
  fi
  [[ -f "$script" ]] || return 0

  py="$INSTALL_DIR/.venv/bin/python"
  [[ -x "$py" ]] || py="$(command -v python3 || echo python3)"

  sudo -u pi env PYTHONPATH="$INSTALL_DIR/src" HOME=/home/pi \
    "$py" "$script" "$phase" "$title" "$subtitle" "$detail" 2>/dev/null \
    || true
}

eink_restore_patch() {
  local script py
  script="$INSTALL_DIR/scripts/show_status.py"
  [[ -f "$script" ]] || return 0
  py="$INSTALL_DIR/.venv/bin/python"
  [[ -x "$py" ]] || py="$(command -v python3)"
  sudo -u pi "$py" "$script" --restore-patch 2>/dev/null || true
  rm -f "$EINK_STATUS_FILE"
}

find_boot_tree() {
  for base in /boot/firmware/pi-ambient-synth /boot/pi-ambient-synth; do
    if [[ -f "$base/$DEPLOY_CONF_NAME" ]]; then
      echo "$base"
      return 0
    fi
  done
  return 1
}

load_deploy_conf() {
  BOOT_TREE=""
  if [[ -f "$PERSIST_CONF" ]]; then
    # shellcheck disable=SC1090
    source "$PERSIST_CONF"
    log "Loaded config: $PERSIST_CONF"
  fi
  local boot_base
  if boot_base="$(find_boot_tree)"; then
    # shellcheck disable=SC1090
    source "$boot_base/$DEPLOY_CONF_NAME"
    BOOT_TREE="$boot_base"
    log "Loaded config: $boot_base/$DEPLOY_CONF_NAME"
  elif [[ -f "$INSTALL_DIR/$DEPLOY_CONF_NAME" ]]; then
    # shellcheck disable=SC1090
    source "$INSTALL_DIR/$DEPLOY_CONF_NAME"
    log "Loaded config: $INSTALL_DIR/$DEPLOY_CONF_NAME"
  elif [[ ! -f "$PERSIST_CONF" ]]; then
    return 1
  fi
  return 0
}

persist_deploy_conf() {
  sudo mkdir -p /etc/pi-ambient-synth
  # Boot SD deploy.conf must not undo GitHub auto-pull written after first bootstrap.
  if [[ -f "$PERSIST_CONF" ]]; then
    # shellcheck disable=SC1090
    source "$PERSIST_CONF"
    if [[ "${DEPLOY_SOURCE:-}" == "github" && "${AUTO_PULL:-0}" == "1" ]]; then
      return 0
    fi
  fi
  if [[ -n "${BOOT_TREE:-}" && -f "$BOOT_TREE/$DEPLOY_CONF_NAME" ]]; then
    sudo cp "$BOOT_TREE/$DEPLOY_CONF_NAME" "$PERSIST_CONF"
  elif [[ -f "$INSTALL_DIR/$DEPLOY_CONF_NAME" ]]; then
    sudo cp "$INSTALL_DIR/$DEPLOY_CONF_NAME" "$PERSIST_CONF"
  fi
  sudo chmod 644 "$PERSIST_CONF"
}

installed_sha() {
  [[ -f "$INSTALL_DIR/.deploy_sha" ]] && cat "$INSTALL_DIR/.deploy_sha" || echo ""
}

is_placeholder_sha() {
  case "$1" in
    "" | boot | boot-sd | latest) return 0 ;;
    *) return 1 ;;
  esac
}

write_installed_sha() {
  local sha="$1"
  mkdir -p "$MARKER_DIR" "$INSTALL_DIR"
  echo "$sha" > "$INSTALL_DIR/.deploy_sha"
  echo "$sha" > "$MARKER_DIR/last_deploy_sha"
  date -Iseconds > "$MARKER_DIR/last_deploy_at"
  chown pi:pi "$INSTALL_DIR/.deploy_sha" "$MARKER_DIR/last_deploy_sha" "$MARKER_DIR/last_deploy_at" 2>/dev/null || true
}

ensure_pi_user() {
  if ! id -u pi &>/dev/null; then
    useradd -m -s /bin/bash pi 2>/dev/null || true
  fi
  mkdir -p "$INSTALL_DIR"
  chown -R pi:pi /home/pi 2>/dev/null || true
}

github_curl() {
  local url="$1"
  local token="${GITHUB_TOKEN:-}"
  if [[ -f /boot/firmware/pi-ambient-synth/deploy/secrets/github_token ]]; then
    token="$(cat /boot/firmware/pi-ambient-synth/deploy/secrets/github_token)"
  elif [[ -f "$INSTALL_DIR/deploy/secrets/github_token" ]]; then
    token="$(cat "$INSTALL_DIR/deploy/secrets/github_token")"
  fi
  if [[ -n "$token" ]]; then
    curl -fsSL -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "$url"
  else
    curl -fsSL -H "Accept: application/vnd.github+json" "$url"
  fi
}

resolve_github_sha() {
  local repo="$1" branch="$2"
  local json sha
  json="$(github_curl "https://api.github.com/repos/${repo}/commits/${branch}")" || return 1
  sha="$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])" 2>/dev/null || true)"
  [[ -n "$sha" ]] || return 1
  echo "$sha"
}

rsync_from_boot() {
  local src="$1"
  log "Rsync from boot: $src -> $INSTALL_DIR"
  rsync -a --delete \
    --exclude '.venv' \
    --exclude '.git' \
    --exclude '.deploy_sha' \
    --exclude 'state' \
    --exclude '__pycache__' \
    --exclude '.pytest_cache' \
    "$src/" "$INSTALL_DIR/"
  chown -R pi:pi "$INSTALL_DIR"
}

fetch_github() {
  local repo="$1" sha="$2"
  local url="https://github.com/${repo}/archive/${sha}.tar.gz"
  local tmp
  tmp="$(mktemp -d)"
  log "Fetching $url"
  curl -fsSL "$url" -o "$tmp/src.tar.gz"
  rm -rf "$tmp/extract"
  mkdir -p "$tmp/extract"
  tar -xzf "$tmp/src.tar.gz" -C "$tmp/extract"
  local extracted
  extracted="$(find "$tmp/extract" -maxdepth 1 -type d ! -path "$tmp/extract" | head -1)"
  rsync -a --delete \
    --exclude '.venv' \
    --exclude 'state' \
    "$extracted/" "$INSTALL_DIR/"
  chown -R pi:pi "$INSTALL_DIR"
  rm -rf "$tmp"
}

run_install() {
  local enable_flag=() quick_flag=()
  if [[ "${ENABLE_SERVICES:-0}" == "1" ]]; then
    enable_flag=(--enable-services)
  fi
  if [[ -f "$INSTALL_DIR/.install_deps_stamp" ]]; then
    quick_flag=(--quick)
  fi
  log "Running install.sh ${enable_flag[*]:-} ${quick_flag[*]:-}"
  if [[ "${INSTALL_FIRST_BOOT:-0}" == "1" || "$MODE" == "bootstrap" ]]; then
    export INSTALL_FIRST_BOOT=1
    export FIRST_BOOT_TRACK=1
    export FIRST_BOOT_TOTAL="${FIRST_BOOT_TOTAL:-12}"
    eink_status install "Installing" "system packages" "apt (slow)"
  fi
  sudo -u pi env INSTALL_FIRST_BOOT="${INSTALL_FIRST_BOOT:-0}" \
    FIRST_BOOT_TRACK="${FIRST_BOOT_TRACK:-0}" \
    FIRST_BOOT_TOTAL="${FIRST_BOOT_TOTAL:-12}" \
    MARKER_DIR="$MARKER_DIR" \
    bash -lc "cd '$INSTALL_DIR' && ./install.sh ${enable_flag[*]:-} ${quick_flag[*]:-}"
}

install_systemd_units() {
  if [[ ! -f "$INSTALL_DIR/systemd/pi-ambient-synth-deploy.service" ]]; then
    return 0
  fi
  sudo cp "$INSTALL_DIR/systemd/pi-ambient-synth-deploy.service" /etc/systemd/system/
  sudo cp "$INSTALL_DIR/systemd/pi-ambient-synth-deploy.timer" /etc/systemd/system/ 2>/dev/null || true
  sudo cp "$INSTALL_DIR/systemd/supercollider.service" /etc/systemd/system/ 2>/dev/null || true
  sudo cp "$INSTALL_DIR/systemd/pi-ambient-synth.service" /etc/systemd/system/ 2>/dev/null || true
  sudo systemctl daemon-reload
  sudo systemctl enable pi-ambient-synth-deploy.timer 2>/dev/null || true
  if [[ "${ENABLE_SERVICES:-0}" == "1" ]]; then
    sudo systemctl enable supercollider.service pi-ambient-synth.service 2>/dev/null || true
  fi
}

restart_services() {
  if [[ "${ENABLE_SERVICES:-0}" != "1" ]]; then
    return 0
  fi
  log "Restarting synth services"
  sudo systemctl restart supercollider.service 2>/dev/null || sudo systemctl start supercollider.service 2>/dev/null || true
  sleep 2
  sudo systemctl restart pi-ambient-synth.service 2>/dev/null || sudo systemctl start pi-ambient-synth.service 2>/dev/null || true
  sudo systemctl restart pi-ambient-synth-monitor.service 2>/dev/null || sudo systemctl start pi-ambient-synth-monitor.service 2>/dev/null || true
}

announce_network() {
  local ann
  for ann in \
    "$INSTALL_DIR/scripts/announce_network.sh" \
    /boot/firmware/pi-ambient-synth/scripts/announce_network.sh \
    /boot/pi-ambient-synth/scripts/announce_network.sh; do
    if [[ -x "$ann" ]]; then
      INSTALL_DIR="$INSTALL_DIR" "$ann" || true
      if [[ -f "$MARKER_DIR/network.json" ]]; then
        log "Network: $(python3 -c "import json; d=json.load(open('$MARKER_DIR/network.json')); print(d.get('primary_ip','?'), d.get('monitor_url',''))" 2>/dev/null || echo 'see network.json')"
      fi
      return 0
    fi
  done
  return 0
}

wait_for_network() {
  local i
  for i in {1..60}; do
    if ping -c1 -W1 8.8.8.8 &>/dev/null || ping -c1 -W1 1.1.1.1 &>/dev/null; then
      announce_network
      return 0
    fi
    sleep 2
  done
  return 1
}

resolve_target_sha() {
  local configured="${DEPLOY_SHA:-}"
  if [[ "${DEPLOY_SOURCE:-github}" == "boot" ]]; then
    echo "${configured:-boot-sd}"
    return 0
  fi
  if [[ "${AUTO_PULL:-0}" == "1" ]] || [[ "$configured" == "latest" ]] || [[ -z "$configured" ]]; then
    if [[ "${DEPLOY_SOURCE:-github}" != "github" ]]; then
      echo "$configured"
      return 0
    fi
    if [[ -z "${GITHUB_REPO:-}" ]]; then
      log "ERROR: AUTO_PULL requires GITHUB_REPO"
      return 1
    fi
    wait_for_network || log "WARN: network not ready"
    resolve_github_sha "${GITHUB_REPO}" "${GITHUB_BRANCH:-main}"
    return 0
  fi
  echo "$configured"
}

do_deploy() {
  local target_sha current_sha short_sha
  local repo_label="${GITHUB_REPO:-pi-ambient-synth}"
  local branch_label="${GITHUB_BRANCH:-main}"

  ensure_pi_user
  sudo mkdir -p "$(dirname "$LOG_FILE")" /etc/pi-ambient-synth "$MARKER_DIR"
  sudo touch "$LOG_FILE"
  sudo chown pi:pi "$LOG_FILE" 2>/dev/null || true

  if [[ "$MODE" == "bootstrap" ]]; then
    EINK_FORCE=1
    export INSTALL_FIRST_BOOT=1
    export FIRST_BOOT_TRACK=1
    export FIRST_BOOT_TOTAL="${FIRST_BOOT_TOTAL:-12}"
    eink_status boot "First boot" "Pi Ambient Synth" "initial setup"
  else
    eink_status boot "Starting" "Checking for updates" ""
  fi

  if ! load_deploy_conf; then
    log "ERROR: No deploy.conf on boot, in $INSTALL_DIR, or $PERSIST_CONF"
    eink_status failed "No deploy config" "" "check boot SD"
    return 1
  fi

  repo_label="${GITHUB_REPO:-$repo_label}"
  branch_label="${GITHUB_BRANCH:-main}"
  persist_deploy_conf

  if [[ "$MODE" == "bootstrap" ]]; then
    eink_status network "Deploy setup" "loading config" ""
  fi
  eink_status checking "Checking GitHub" "$repo_label" "$branch_label"

  current_sha="$(installed_sha)"
  if ! target_sha="$(resolve_target_sha)"; then
    if [[ "$MODE" == "bootstrap" ]] && boot_base="$(find_boot_tree)"; then
      log "WARN: GitHub unreachable — first boot from SD card"
      BOOT_TREE="$boot_base"
      DEPLOY_SOURCE=boot
      target_sha="${DEPLOY_SHA:-boot-sd}"
      eink_status download "Using SD copy" "boot" "no GitHub"
    else
      eink_status failed "GitHub unreachable" "$repo_label" "network?"
      return 1
    fi
  fi
  short_sha="${target_sha:0:7}"

  log "Mode=$MODE source=${DEPLOY_SOURCE:-github} auto_pull=${AUTO_PULL:-0} remote=$short_sha installed=${current_sha:0:7}"

  if is_placeholder_sha "$current_sha" && ! is_placeholder_sha "$target_sha"; then
    write_installed_sha "$target_sha"
    current_sha="$target_sha"
    log "Healed deploy SHA marker ($short_sha)"
  fi

  if [[ "$target_sha" == "$current_sha" ]]; then
    log "Already up to date ($short_sha)"
    return 0
  fi

  eink_status download "Pulling update" "$short_sha" "$repo_label"

  case "${DEPLOY_SOURCE:-github}" in
    github)
      if [[ -z "${GITHUB_REPO:-}" ]]; then
        log "ERROR: GITHUB_REPO required"
        eink_status failed "Missing repo" "" "GITHUB_REPO"
        return 1
      fi
      if ! fetch_github "$GITHUB_REPO" "$target_sha"; then
        eink_status failed "Download failed" "$short_sha" "$repo_label"
        return 1
      fi
      ;;
    boot)
      if [[ -z "${BOOT_TREE:-}" ]]; then
        log "ERROR: boot source but no boot tree"
        eink_status failed "No boot copy" "" "sync SD on Mac"
        return 1
      fi
      eink_status download "Syncing boot" "$short_sha" "SD card"
      rsync_from_boot "$BOOT_TREE"
      ;;
    *)
      log "ERROR: unknown DEPLOY_SOURCE=${DEPLOY_SOURCE}"
      eink_status failed "Bad config" "${DEPLOY_SOURCE}" ""
      return 1
      ;;
  esac

  eink_status install "Installing" "$short_sha" "venv + packages"
  if ! run_install; then
    eink_status failed "Install failed" "$short_sha" "install.sh"
    return 1
  fi

  install_systemd_units
  write_installed_sha "$target_sha"

  eink_status restart "Restarting" "audio engine" "supercollider"
  restart_services

  eink_status ready "Update complete" "$short_sha" "$repo_label"
  log "Deploy complete: $short_sha (${GITHUB_REPO:-boot})"

  if [[ "${AUTO_PULL:-0}" == "1" && "${DEPLOY_SOURCE:-}" == "boot" && -n "${GITHUB_REPO:-}" ]]; then
    sudo mkdir -p /etc/pi-ambient-synth
    sudo tee /etc/pi-ambient-synth/deploy.conf >/dev/null <<EOF
# After SD bootstrap — timer pulls from GitHub
DEPLOY_SOURCE=github
AUTO_PULL=1
DEPLOY_SHA=latest
GITHUB_REPO=${GITHUB_REPO}
GITHUB_BRANCH=${GITHUB_BRANCH:-main}
ENABLE_SERVICES=${ENABLE_SERVICES:-1}
EOF
    log "Persisted GitHub auto-pull config for future updates"
  fi

  sleep 2
  eink_restore_patch
}

case "$MODE" in
  bootstrap|sync|check)
    do_deploy
    ;;
  *)
    echo "Usage: $0 [bootstrap|sync|check]"
    exit 1
    ;;
esac
