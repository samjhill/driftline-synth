#!/usr/bin/env bash
# Quick fix boot partition + root unit without full rsync.
# Usage: sudo ./scripts/fix_autobringup_sd_boot.sh [/Volumes/bootfs]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOT="${1:-/Volumes/bootfs}"
[[ -d "$BOOT" ]] || { echo "ERROR: $BOOT not mounted" >&2; exit 1; }

cp "$ROOT/deploy/user-data.autobringup" "$BOOT/user-data"
mkdir -p "$BOOT/pi-ambient-synth/deploy"
if [[ ! -f "$BOOT/pi-ambient-synth/deploy/deploy.conf" ]]; then
  cat >"$BOOT/pi-ambient-synth/deploy/deploy.conf" <<EOF
DEPLOY_SOURCE=boot
AUTO_PULL=0
DEPLOY_SHA=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo boot-sd)
GITHUB_REPO=samjhill/driftline-synth
GITHUB_BRANCH=main
ENABLE_SERVICES=1
AUDIO_MODE=fluidsynth
FACTORY_BOOT=1
EOF
fi
echo "==> user-data + deploy.conf on bootfs"
if ! sudo "$ROOT/scripts/install_autobringup_rootfs.sh" "$BOOT"; then
  echo ""
  echo "Mac rootfs install failed. Paste docs/chatgpt_handoff_autobringup.md into ChatGPT,"
  echo "or after Pi SSH works run the Pi-side commands printed above."
  exit 1
fi
"$ROOT/scripts/check_autobringup_sd_mac.sh" "$BOOT"
