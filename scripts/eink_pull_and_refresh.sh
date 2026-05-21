#!/usr/bin/env bash
# Pull latest code and refresh the e-ink (releases GPIO from synth briefly).
# Works with git clones and rsync/deploy installs (no .git required).
#
#   curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/eink_pull_and_refresh.sh | bash
#
# Optional args: phase title [subtitle] [detail]
#   curl -fsSL .../eink_pull_and_refresh.sh | bash -s -- network "192.168.1.64"
#
# Env:
#   SKIP_SYNC=1     — only refresh the display (no code update)
#   QUICK_SYNC=1    — default; GitHub tarball rsync without full install.sh
#   FULL_SYNC=1     — run scripts/pi-deploy-sync.sh sync when available
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
GITHUB_REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
PHASE="${1:-ready}"
TITLE="${2:-Updated}"
DETAIL="${4:-}"

deploy_label() {
  if [[ -f "$INSTALL_DIR/.deploy_sha" ]]; then
    head -c 7 "$INSTALL_DIR/.deploy_sha"
    return
  fi
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || true
    return
  fi
  echo ""
}

SUBTITLE="${3:-$(deploy_label)}"

pull_from_git() {
  echo "==> git pull ($GITHUB_BRANCH)"
  git -C "$INSTALL_DIR" pull --ff-only origin "$GITHUB_BRANCH"
}

pull_from_github_tarball() {
  echo "==> GitHub sync (${GITHUB_REPO}@${GITHUB_BRANCH}, no .git on Pi)"
  local json sha tmp extracted
  json="$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/commits/${GITHUB_BRANCH}")"
  sha="$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])")"
  short="${sha:0:7}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL "https://github.com/${GITHUB_REPO}/archive/${sha}.tar.gz" -o "$tmp/src.tar.gz"
  mkdir -p "$tmp/extract"
  tar -xzf "$tmp/src.tar.gz" -C "$tmp/extract"
  extracted="$(find "$tmp/extract" -maxdepth 1 -type d ! -path "$tmp/extract" | head -1)"
  if [[ -z "$extracted" || ! -f "$extracted/install.sh" ]]; then
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
  echo "$sha" >"$INSTALL_DIR/.deploy_sha"
  SUBTITLE="${3:-$short}"
  echo "==> Synced $short into $INSTALL_DIR"
}

pull_latest() {
  if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "ERROR: install dir missing: $INSTALL_DIR" >&2
    exit 1
  fi
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    pull_from_git
    return
  fi
  if [[ "${FULL_SYNC:-0}" == "1" && -x "$INSTALL_DIR/scripts/pi-deploy-sync.sh" ]]; then
    echo "==> pi-deploy-sync.sh sync"
    bash "$INSTALL_DIR/scripts/pi-deploy-sync.sh" sync
    return
  fi
  pull_from_github_tarball
}

if [[ "${SKIP_SYNC:-0}" != "1" ]]; then
  pull_latest
fi

if [[ ! -x "$INSTALL_DIR/scripts/boot_display.sh" ]]; then
  echo "ERROR: boot_display.sh not found under $INSTALL_DIR" >&2
  exit 1
fi

sudo systemctl stop pi-ambient-synth 2>/dev/null || true
EINK_FORCE=1 "$INSTALL_DIR/scripts/boot_display.sh" "$PHASE" "$TITLE" "$SUBTITLE" "$DETAIL"
echo "--- /var/log/pi-ambient-synth-eink.log (last 12 lines) ---"
tail -12 /var/log/pi-ambient-synth-eink.log 2>/dev/null || true
sudo systemctl start pi-ambient-synth 2>/dev/null || true
