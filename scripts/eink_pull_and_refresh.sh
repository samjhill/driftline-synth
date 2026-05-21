#!/usr/bin/env bash
# Pull latest main and refresh the e-ink (releases GPIO from synth briefly).
#   curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/eink_pull_and_refresh.sh | bash
# Optional args: phase title [subtitle] [detail]
#   curl -fsSL .../eink_pull_and_refresh.sh | bash -s -- network "192.168.1.50"
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
PHASE="${1:-ready}"
TITLE="${2:-Updated}"
SUBTITLE="${3:-$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo "")}"
DETAIL="${4:-}"

cd "$INSTALL_DIR"
git pull --ff-only origin main

sudo systemctl stop pi-ambient-synth 2>/dev/null || true
EINK_FORCE=1 "$INSTALL_DIR/scripts/boot_display.sh" "$PHASE" "$TITLE" "$SUBTITLE" "$DETAIL"
echo "--- /var/log/pi-ambient-synth-eink.log (last 12 lines) ---"
tail -12 /var/log/pi-ambient-synth-eink.log 2>/dev/null || true
sudo systemctl start pi-ambient-synth 2>/dev/null || true
