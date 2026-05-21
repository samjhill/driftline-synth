#!/usr/bin/env bash
# Pull latest code and refresh the e-ink (releases GPIO from synth briefly).
# No git required — Pi deploy installs use a GitHub tarball rsync.
#
#   curl -fsSL "https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/eink_pull_and_refresh.sh" | bash
# Cache-bust if GitHub serves a stale copy:
#   curl -fsSL ".../eink_pull_and_refresh.sh?t=$(date +%s)" | bash
#
# Optional args: phase title [subtitle] [detail]
# Env:
#   SKIP_SYNC=1  — only refresh the display (no code update)
#   FULL_SYNC=1  — run scripts/pi-deploy-sync.sh sync (slow; uses install.sh)
set -euo pipefail

EINK_REFRESH_VERSION=6
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
GITHUB_REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
PHASE="${1:-ready}"
TITLE="${2:-Updated}"
DETAIL="${4:-}"

# raw.githubusercontent.com often caches branch HEAD; re-run the on-disk copy if newer.
maybe_reexec_installed() {
  [[ "${EINK_REEXEC:-0}" == "1" ]] && return 0
  local inst="$INSTALL_DIR/scripts/eink_pull_and_refresh.sh"
  [[ -r "$inst" ]] || return 0
  local inst_ver
  inst_ver="$(grep -E '^EINK_REFRESH_VERSION=' "$inst" | head -1 | cut -d= -f2 | tr -cd '0-9')"
  inst_ver="${inst_ver:-0}"
  if [[ "$inst_ver" -gt "$EINK_REFRESH_VERSION" ]]; then
    echo "==> Re-running installed script v${inst_ver} (curl had v${EINK_REFRESH_VERSION})"
    export EINK_REEXEC=1
    exec env \
      SKIP_SYNC="${SKIP_SYNC:-0}" \
      FULL_SYNC="${FULL_SYNC:-0}" \
      INSTALL_DIR="$INSTALL_DIR" \
      bash "$inst" "$@"
  fi
}

maybe_reexec_installed "$@"
echo "==> eink_pull_and_refresh.sh v${EINK_REFRESH_VERSION}"

deploy_label() {
  if [[ -f "$INSTALL_DIR/.deploy_sha" ]]; then
    head -c 7 "$INSTALL_DIR/.deploy_sha" 2>/dev/null || true
    return
  fi
  echo "pi"
}

SUBTITLE="${3:-$(deploy_label)}"

pull_from_github_tarball() {
  echo "==> GitHub sync (${GITHUB_REPO}@${GITHUB_BRANCH})"
  local json sha tmp extracted short
  json="$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/commits/${GITHUB_BRANCH}")"
  sha="$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])")"
  short="${sha:0:7}"
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/${GITHUB_REPO}/archive/${sha}.tar.gz" -o "$tmp/src.tar.gz"
  mkdir -p "$tmp/extract"
  tar -xzf "$tmp/src.tar.gz" -C "$tmp/extract"
  extracted="$(find "$tmp/extract" -maxdepth 1 -type d ! -path "$tmp/extract" | head -1)"
  if [[ -z "$extracted" || ! -f "$extracted/install.sh" ]]; then
    rm -rf "$tmp"
    echo "ERROR: GitHub archive did not extract as expected" >&2
    return 1
  fi
  rsync -a \
    --exclude '.venv/' \
    --exclude '.git/' \
    --exclude 'state/' \
    --exclude '__pycache__/' \
    --exclude '.pytest_cache/' \
    "$extracted/" "$INSTALL_DIR/"
  rm -rf "$tmp"
  echo "$sha" >"$INSTALL_DIR/.deploy_sha"
  SUBTITLE="${3:-$short}"
  echo "==> Synced $short into $INSTALL_DIR"
}

pull_latest() {
  if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "ERROR: install dir missing: $INSTALL_DIR" >&2
    exit 1
  fi
  if [[ "${FULL_SYNC:-0}" == "1" && -x "$INSTALL_DIR/scripts/pi-deploy-sync.sh" ]]; then
    echo "==> pi-deploy-sync.sh sync"
    bash "$INSTALL_DIR/scripts/pi-deploy-sync.sh" sync
    return
  fi
  pull_from_github_tarball
  maybe_reexec_installed "$@"
}

if [[ "${SKIP_SYNC:-0}" != "1" ]]; then
  pull_latest
else
  echo "==> SKIP_SYNC=1 (display only)"
fi

if [[ ! -x "$INSTALL_DIR/scripts/boot_display.sh" ]]; then
  echo "ERROR: boot_display.sh not found under $INSTALL_DIR" >&2
  exit 1
fi

stop_eink_clients() {
  echo "==> Stopping services that may hold e-ink GPIO..."
  sudo systemctl stop pi-ambient-synth pi-ambient-synth-deploy.service 2>/dev/null || true
  sleep 2
}

release_eink_gpio() {
  local py="$INSTALL_DIR/.venv/bin/python"
  [[ -x "$py" ]] || py="$(command -v python3 || true)"
  [[ -n "$py" ]] || return 0
  PYTHONPATH="$INSTALL_DIR/src" "$py" - <<'PY' 2>/dev/null || true
from config_loader import load_config
from eink_display import EInkDisplay
EInkDisplay(load_config()).release()
PY
  sleep 1
}

run_boot_display() {
  local attempt rc=1
  stop_eink_clients
  for attempt in 1 2 3; do
    if EINK_FORCE=1 "$INSTALL_DIR/scripts/boot_display.sh" \
      "$PHASE" "$TITLE" "$SUBTITLE" "$DETAIL"; then
      return 0
    fi
    rc=1
    if [[ "$attempt" -lt 3 ]]; then
      echo "==> E-ink attempt $attempt failed; releasing GPIO and retrying..."
      release_eink_gpio
    fi
  done
  return "$rc"
}

if ! run_boot_display; then
  echo "WARN: e-ink update failed after 3 attempts — see log below" >&2
fi

echo "--- /var/log/pi-ambient-synth-eink.log (last 12 lines) ---"
tail -12 /var/log/pi-ambient-synth-eink.log 2>/dev/null || true
sudo systemctl start pi-ambient-synth 2>/dev/null || true
