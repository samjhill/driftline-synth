# shellcheck shell=bash
# Safe project deploy — source from pi-deploy-sync.sh / recover_pi_from_github.sh
# Never use rsync --delete on /, /home/pi, or $HOME.

DEPLOY_INSTALL_DIR="/home/pi/pi-ambient-synth"

_deploy_log() {
  echo "$(date -Iseconds) [deploy-sync] $*"
}

_validate_project_source() {
  local src="$1"
  if [[ ! -d "$src" ]]; then
    _deploy_log "ERROR: source missing: $src"
    return 1
  fi
  if [[ ! -f "$src/install.sh" || ! -f "$src/src/main.py" ]]; then
    _deploy_log "ERROR: source is not pi-ambient-synth: $src"
    return 1
  fi
  local resolved
  resolved="$(cd "$src" && pwd -P)"
  if [[ "$resolved" == "$(cd "$DEPLOY_INSTALL_DIR" 2>/dev/null && pwd -P)" ]]; then
    _deploy_log "ERROR: source and install dir are the same: $resolved"
    return 1
  fi
  return 0
}

_validate_install_dest() {
  local dest="$1"
  if [[ "$dest" != "$DEPLOY_INSTALL_DIR" ]]; then
    _deploy_log "ERROR: refusing deploy to: $dest (expected $DEPLOY_INSTALL_DIR)"
    return 1
  fi
  case "$dest" in
    / | /home | /home/pi | /home/pi/)
      _deploy_log "ERROR: refusing unsafe deploy target: $dest"
      return 1
      ;;
  esac
  return 0
}

# Staging copy + atomic rename — no rsync --delete on a live directory tree.
safe_sync_project_tree() {
  local src="$1"
  local dest="$DEPLOY_INSTALL_DIR"
  local staging backup

  _validate_project_source "$src" || return 1
  _validate_install_dest "$dest" || return 1

  _deploy_log "Deploy $src -> $dest (staging, no --delete)"

  staging="$(mktemp -d -p /home/pi pi-ambient-synth.staging.XXXXXX)"
  rsync -a \
    --exclude '.venv/' \
    --exclude '.git/' \
    --exclude 'state/' \
    --exclude '__pycache__/' \
    --exclude '.pytest_cache/' \
    "$src/" "$staging/"

  for keep in .venv state .deploy_sha; do
    if [[ -e "$dest/$keep" ]]; then
      cp -a "$dest/$keep" "$staging/" 2>/dev/null || true
    fi
  done

  chown -R pi:pi "$staging" 2>/dev/null || true

  backup=""
  if [[ -d "$dest" ]]; then
    backup="$(mktemp -d -p /home/pi pi-ambient-synth.backup.XXXXXX)"
    mv "$dest" "$backup/old"
  fi

  if ! mv "$staging" "$dest"; then
    _deploy_log "ERROR: mv staging -> dest failed"
    if [[ -n "$backup" && -d "$backup/old" ]]; then
      rm -rf "$dest" 2>/dev/null || true
      mv "$backup/old" "$dest"
    fi
    rm -rf "$staging" "$backup"
    return 1
  fi

  rm -rf "$backup" 2>/dev/null || true
  chown -R pi:pi "$dest" 2>/dev/null || true
  _deploy_log "Deploy tree ready at $dest"
  return 0
}
