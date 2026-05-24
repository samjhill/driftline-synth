#!/usr/bin/env bash
# Factory SD for autonomous bring-up (one report after unattended boot).
# Usage: sudo ./scripts/wipe_cloud_init_mac.sh && ./scripts/build_autobringup_sd_mac.sh [/Volumes/bootfs]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export BUNDLE_OFFLINE=1
export BUNDLE_V1=1
export FACTORY_SD=1
export AUTBRINGUP=1
export DEFAULT_AUDIO_MODE=fluidsynth
export ENABLE_SERVICES=1
export AUTO_PULL=0
export DEPLOY_SOURCE=boot
export WIPE_CLOUD_INIT=1
export USER_DATA_FILE="$ROOT/deploy/user-data.autobringup"

echo "==> Autobringup SD (phase 1: sentinel + SSH; install unit on Pi after boot)"
"$ROOT/scripts/sync_to_sd_mac.sh" "${1:-}"
BOOT="${1:-/Volumes/bootfs}"
[[ -d "$BOOT" ]] || for v in /Volumes/bootfs /Volumes/boot; do [[ -d "$v" ]] && BOOT="$v" && break; done
if [[ -d "$BOOT" ]]; then
  cp "$ROOT/deploy/user-data.autobringup" "$BOOT/user-data"
  echo "    user-data ← deploy/user-data.autobringup"
fi
