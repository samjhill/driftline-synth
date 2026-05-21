#!/usr/bin/env bash
# Fix ownership after a bad rsync (root-owned files → pi cannot deploy).
set -euo pipefail

INSTALL_DIR="/home/pi/pi-ambient-synth"

if [[ ! -d "$INSTALL_DIR" ]]; then
  echo "ERROR: $INSTALL_DIR missing" >&2
  exit 1
fi

echo "==> chown -R pi:pi $INSTALL_DIR"
sudo chown -R pi:pi "$INSTALL_DIR"
sudo chmod -R u+rwX "$INSTALL_DIR"
echo "==> Done. Retry deploy:"
echo "    sudo systemctl start pi-ambient-synth-deploy.service"
