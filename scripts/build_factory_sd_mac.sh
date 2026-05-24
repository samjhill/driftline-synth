#!/usr/bin/env bash
# Factory SD: boot sentinel + FluidSynth V1, offline wheels, systemd-first firstboot.
# Usage: sudo ./scripts/wipe_cloud_init_mac.sh && ./scripts/build_factory_sd_mac.sh [/Volumes/bootfs]
# Requires sudo during sync to install pi-ambient-boot-sentinel.service on root FS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export BUNDLE_OFFLINE=1
export BUNDLE_V1=1
export FACTORY_SD=1
export DEFAULT_AUDIO_MODE=fluidsynth
export ENABLE_SERVICES=1
export AUTO_PULL=0
export DEPLOY_SOURCE=boot
export WIPE_CLOUD_INIT=1

echo "==> Factory SD prep (FluidSynth V1, minimal first boot)"
exec "$ROOT/scripts/sync_to_sd_mac.sh" "${1:-}"
