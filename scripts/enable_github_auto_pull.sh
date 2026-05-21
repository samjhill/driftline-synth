#!/usr/bin/env bash
# Switch a running Pi from boot-SD-only deploys to GitHub auto-pull (latest main).
# Run on the Pi: bash /home/pi/pi-ambient-synth/scripts/enable_github_auto_pull.sh
set -euo pipefail

REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
BRANCH="${GITHUB_BRANCH:-main}"

sudo mkdir -p /etc/pi-ambient-synth
sudo tee /etc/pi-ambient-synth/deploy.conf >/dev/null <<EOF
# Enabled by enable_github_auto_pull.sh — pulls from GitHub on deploy timer
DEPLOY_SOURCE=github
AUTO_PULL=1
DEPLOY_SHA=latest
GITHUB_REPO=${REPO}
GITHUB_BRANCH=${BRANCH}
ENABLE_SERVICES=1
EOF

echo "Wrote /etc/pi-ambient-synth/deploy.conf (GitHub ${REPO}@${BRANCH})"
if systemctl is-enabled pi-ambient-synth-deploy.timer &>/dev/null; then
  sudo systemctl start pi-ambient-synth-deploy.service
  echo "Triggered deploy now; monitor should update within ~1–2 min."
else
  echo "Run: sudo systemctl enable --now pi-ambient-synth-deploy.timer"
fi
