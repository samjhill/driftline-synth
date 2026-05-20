#!/usr/bin/env bash
# Sync pi-ambient-synth from boot partition or GitHub, run install when SHA changes.
# Usage: pi-deploy-sync.sh [bootstrap|sync|check]
set -euo pipefail

MODE="${1:-sync}"
LOG_TAG="pi-deploy-sync"
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="/var/lib/pi-ambient-synth"
LOG_FILE="/var/log/pi-ambient-synth-deploy.log"
DEPLOY_CONF_NAME="deploy/deploy.conf"

log() { echo "$(date -Iseconds) [$LOG_TAG] $*" | tee -a "$LOG_FILE"; }

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
  local base="$1"
  # shellcheck disable=SC1090
  source "$base/$DEPLOY_CONF_NAME"
  BOOT_TREE="$base"
}

installed_sha() {
  [[ -f "$INSTALL_DIR/.deploy_sha" ]] && cat "$INSTALL_DIR/.deploy_sha" || echo ""
}

write_installed_sha() {
  local sha="$1"
  mkdir -p "$MARKER_DIR" "$INSTALL_DIR"
  echo "$sha" > "$INSTALL_DIR/.deploy_sha"
  echo "$sha" > "$MARKER_DIR/last_deploy_sha"
  date -Iseconds > "$MARKER_DIR/last_deploy_at"
}

ensure_pi_user() {
  if ! id -u pi &>/dev/null; then
    useradd -m -s /bin/bash pi 2>/dev/null || true
  fi
  mkdir -p "$INSTALL_DIR"
  chown -R pi:pi /home/pi 2>/dev/null || true
}

rsync_from_boot() {
  local src="$1"
  log "Rsync from boot: $src -> $INSTALL_DIR"
  rsync -a --delete \
    --exclude '.venv' \
    --exclude '.git' \
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
  sudo -u pi bash -lc "cd '$INSTALL_DIR' && ./install.sh ${enable_flag[*]:-} ${quick_flag[*]:-}"
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

restart_app_if_running() {
  if systemctl is-enabled pi-ambient-synth.service &>/dev/null; then
    log "Restarting synth services"
    sudo systemctl restart supercollider.service 2>/dev/null || true
    sleep 2
    sudo systemctl restart pi-ambient-synth.service 2>/dev/null || true
  fi
}

wait_for_network() {
  local i
  for i in {1..60}; do
    if ping -c1 -W1 8.8.8.8 &>/dev/null || ping -c1 -W1 1.1.1.1 &>/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

do_deploy() {
  local target_sha current_sha boot_base

  ensure_pi_user
  sudo mkdir -p "$(dirname "$LOG_FILE")"
  sudo touch "$LOG_FILE"
  sudo chown pi:pi "$LOG_FILE" 2>/dev/null || true

  if ! boot_base="$(find_boot_tree)"; then
    log "ERROR: No boot tree with $DEPLOY_CONF_NAME found"
    return 1
  fi

  load_deploy_conf "$boot_base"
  target_sha="${DEPLOY_SHA:-unknown}"
  current_sha="$(installed_sha)"

  log "Mode=$MODE source=${DEPLOY_SOURCE:-boot} target=$target_sha installed=$current_sha"

  if [[ "$target_sha" == "$current_sha" && "$MODE" == "check" ]]; then
    log "Already up to date"
    return 0
  fi

  if [[ "$target_sha" == "$current_sha" && "$MODE" != "bootstrap" ]]; then
    log "SHA unchanged — skip"
    return 0
  fi

  case "${DEPLOY_SOURCE:-boot}" in
    github)
      if [[ -z "${GITHUB_REPO:-}" ]]; then
        log "ERROR: GITHUB_REPO required for github source"
        return 1
      fi
      wait_for_network || log "WARN: network slow; trying GitHub anyway"
      fetch_github "$GITHUB_REPO" "$target_sha"
      ;;
    boot|*)
      rsync_from_boot "$boot_base"
      ;;
  esac

  run_install
  install_systemd_units
  write_installed_sha "$target_sha"
  restart_app_if_running
  log "Deploy complete: $target_sha"
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
