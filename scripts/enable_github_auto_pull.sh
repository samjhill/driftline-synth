#!/usr/bin/env bash
# Switch a running Pi from boot-SD-only deploys to GitHub auto-pull (latest main).
# Prefer recover when boot loop left old code:
#   curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/recover_pi_from_github.sh | bash
# Or (if scripts are already current): bash ~/pi-ambient-synth/scripts/enable_github_auto_pull.sh
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

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="/var/lib/pi-ambient-synth"
for f in "$INSTALL_DIR/.deploy_sha" "$MARKER_DIR/last_deploy_sha"; do
  if [[ -f "$f" ]] && grep -qxE 'boot-sd|boot|latest' "$f" 2>/dev/null; then
    rm -f "$f"
    echo "Cleared placeholder deploy marker: $f"
  fi
done

if systemctl is-enabled pi-ambient-synth-deploy.timer &>/dev/null; then
  sudo systemctl start pi-ambient-synth-deploy.service
  echo "Triggered deploy now; monitor should update within ~1–2 min."
else
  echo "Run: sudo systemctl enable --now pi-ambient-synth-deploy.timer"
fi
