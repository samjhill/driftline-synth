#!/usr/bin/env bash
# Stop GitHub auto-deploy on the Pi (timer + AUTO_PULL). Use deploy_to_pi.sh from Mac instead.
set -euo pipefail

sudo mkdir -p /etc/pi-ambient-synth

if [[ -f /etc/pi-ambient-synth/deploy.conf ]]; then
  tmp="$(mktemp)"
  grep -v '^AUTO_PULL=' /etc/pi-ambient-synth/deploy.conf >"$tmp" || true
  echo 'AUTO_PULL=0' >>"$tmp"
  sudo cp "$tmp" /etc/pi-ambient-synth/deploy.conf
  rm -f "$tmp"
else
  sudo tee /etc/pi-ambient-synth/deploy.conf >/dev/null <<'EOF'
# Manual deploy — timer disabled (disable_github_auto_pull.sh)
DEPLOY_SOURCE=github
AUTO_PULL=0
DEPLOY_SHA=manual
GITHUB_REPO=samjhill/driftline-synth
GITHUB_BRANCH=main
ENABLE_SERVICES=1
EOF
fi

echo "Stopping deploy timer and any in-flight deploy..."
sudo systemctl stop pi-ambient-synth-deploy.service 2>/dev/null || true
sudo systemctl stop pi-ambient-synth-deploy.timer 2>/dev/null || true
sudo systemctl disable pi-ambient-synth-deploy.timer 2>/dev/null || true

echo "Deploy timer: $(systemctl is-enabled pi-ambient-synth-deploy.timer 2>&1 || echo disabled)"
echo "AUTO_PULL=$(grep '^AUTO_PULL=' /etc/pi-ambient-synth/deploy.conf || echo 'AUTO_PULL=?')"
echo "Manual deploy from Mac: ./scripts/deploy_to_pi.sh"
