#!/usr/bin/env bash
# One-shot recovery: pull latest main from GitHub, install, fix systemd, restart.
# Run on the Pi (works even when boot deploy loop left old code):
#   curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/recover_pi_from_github.sh | bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
BRANCH="${GITHUB_BRANCH:-main}"
LOG="/var/log/pi-ambient-synth-recover.log"

log() { echo "$(date -Iseconds) [recover] $*" | tee -a "$LOG"; }

if [[ "$(id -un)" != "pi" && "$(id -un)" != "root" ]]; then
  echo "Run as pi or root (e.g. curl ... | sudo -u pi bash)"
  exit 1
fi

sudo mkdir -p "$(dirname "$LOG")" /etc/pi-ambient-synth "$MARKER_DIR" "$INSTALL_DIR"
sudo touch "$LOG"
sudo chown pi:pi "$LOG" 2>/dev/null || true

log "Stopping deploy timer (boot rsync loop)"
sudo systemctl stop pi-ambient-synth-deploy.timer 2>/dev/null || true
sudo systemctl stop pi-ambient-synth-deploy.service 2>/dev/null || true

log "Resolving GitHub commit (${REPO}@${BRANCH})"
json="$(curl -fsSL "https://api.github.com/repos/${REPO}/commits/${BRANCH}")"
sha="$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])")"
short="${sha:0:7}"
log "Fetching ${short}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
curl -fsSL "https://github.com/${REPO}/archive/${sha}.tar.gz" -o "$tmpdir/src.tar.gz"
mkdir -p "$tmpdir/extract"
tar -xzf "$tmpdir/src.tar.gz" -C "$tmpdir/extract"
extracted="$(find "$tmpdir/extract" -maxdepth 1 -type d ! -path "$tmpdir/extract" | head -1)"

rsync -a --delete \
  --exclude '.venv' \
  --exclude '.git' \
  --exclude 'state' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  --exclude '.deploy_sha' \
  "$extracted/" "$INSTALL_DIR/"
sudo chown -R pi:pi "$INSTALL_DIR"

sudo tee /etc/pi-ambient-synth/deploy.conf >/dev/null <<EOF
# Written by recover_pi_from_github.sh
DEPLOY_SOURCE=github
AUTO_PULL=1
DEPLOY_SHA=latest
GITHUB_REPO=${REPO}
GITHUB_BRANCH=${BRANCH}
ENABLE_SERVICES=1
EOF
log "Wrote /etc/pi-ambient-synth/deploy.conf"

log "Running install.sh --enable-services --quick"
sudo -u pi env MARKER_DIR="$MARKER_DIR" bash -lc "cd '$INSTALL_DIR' && ./install.sh --enable-services --quick"

echo "$sha" | sudo tee "$INSTALL_DIR/.deploy_sha" >/dev/null
echo "$sha" | sudo tee "$MARKER_DIR/last_deploy_sha" >/dev/null
date -Iseconds | sudo tee "$MARKER_DIR/last_deploy_at" >/dev/null
sudo chown pi:pi "$INSTALL_DIR/.deploy_sha" "$MARKER_DIR/last_deploy_sha" "$MARKER_DIR/last_deploy_at"

sudo usermod -aG adm,audio,gpio,spi,dialout pi 2>/dev/null || true
sudo modprobe snd-seq 2>/dev/null || true
if [[ -x "$INSTALL_DIR/scripts/setup_pi_audio.sh" ]]; then
  bash "$INSTALL_DIR/scripts/setup_pi_audio.sh" || log "WARN: setup_pi_audio failed"
fi

log "Restarting services"
sudo systemctl daemon-reload
sudo systemctl restart supercollider.service 2>/dev/null || sudo systemctl start supercollider.service
sleep 4
sudo systemctl restart pi-ambient-synth.service
sudo systemctl restart pi-ambient-synth-monitor.service
sudo systemctl enable --now pi-ambient-synth-deploy.timer 2>/dev/null || true

log "Done ($short). Check:"
echo "  systemctl cat supercollider.service | grep ExecStart"
echo "  sudo journalctl -u supercollider -n 20 --no-pager"
echo "  curl -s http://127.0.0.1:8080/api/status | python3 -c \"import sys,json; d=json.load(sys.stdin); print(d.get('deploy_sha'), d.get('midi',{}).get('label'))\""
