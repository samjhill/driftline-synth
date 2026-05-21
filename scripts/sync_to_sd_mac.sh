#!/usr/bin/env bash
# Sync project to SD boot partition + write deploy SHA for Pi auto-install/update.
# Usage:
#   ./scripts/sync_to_sd_mac.sh                    # auto-detect /Volumes/bootfs
#   ./scripts/sync_to_sd_mac.sh /Volumes/bootfs
#   DEPLOY_SOURCE=github GITHUB_REPO=you/driftline-synth ./scripts/sync_to_sd_mac.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOT_VOL="${1:-}"

if [[ -z "$BOOT_VOL" ]]; then
  for v in /Volumes/bootfs /Volumes/boot; do
    if [[ -d "$v" ]]; then
      BOOT_VOL="$v"
      break
    fi
  done
fi

if [[ -z "$BOOT_VOL" ]] || [[ ! -d "$BOOT_VOL" ]]; then
  echo "ERROR: SD boot volume not found. Mount card or pass path: $0 /Volumes/bootfs"
  exit 1
fi

DEST="$BOOT_VOL/pi-ambient-synth"
# First boot installs from the SD copy (reliable offline); timer can pull GitHub once online.
DEPLOY_SOURCE="${DEPLOY_SOURCE:-boot}"
AUTO_PULL="${AUTO_PULL:-1}"
DEPLOY_SHA="${DEPLOY_SHA:-boot-sd}"
GITHUB_REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
GITHUB_BRANCH="${GITHUB_BRANCH:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
ENABLE_SERVICES="${ENABLE_SERVICES:-1}"
BUNDLE_OFFLINE="${BUNDLE_OFFLINE:-1}"
SECRETS_DIR="$ROOT/deploy/secrets"

DEPLOY_SHA_FULL=""
if [[ "$DEPLOY_SHA" == "latest" ]]; then
  DEPLOY_SHA_FULL="(resolved on Pi from GitHub)"
elif [[ -n "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" ]]; then
  DEPLOY_SHA_FULL="$(git -C "$ROOT" rev-parse HEAD)"
fi

# Bundle Waveshare driver on the SD so e-ink works before GitHub/network install.
if [[ -x "$ROOT/scripts/ensure_waveshare_vendor.sh" ]]; then
  echo "==> Bundling Waveshare e-ink driver into project..."
  bash "$ROOT/scripts/ensure_waveshare_vendor.sh" || echo "    WARN: Waveshare bundle failed (Pi may fetch via git later)"
fi

RSYNC_EXCLUDE_VENV=(--exclude '.venv')
if [[ "$BUNDLE_OFFLINE" == "1" ]]; then
  if [[ -x "$ROOT/scripts/bundle_pi_offline.sh" ]]; then
    echo "==> Bundling Pi Python wheels for offline install..."
    bash "$ROOT/scripts/bundle_pi_offline.sh" || echo "    WARN: wheel bundle failed — Pi will pip from PyPI"
  fi
  if [[ -x "$ROOT/.venv/bin/python" ]] && [[ -f "$ROOT/.venv/.prebuilt_stamp" ]]; then
    RSYNC_EXCLUDE_VENV=()
    echo "    Including pre-built .venv on SD ($(du -sh "$ROOT/.venv" | cut -f1))"
  fi
fi

echo "==> Syncing to $DEST"
echo "    DEPLOY_SOURCE=$DEPLOY_SOURCE  AUTO_PULL=$AUTO_PULL  SHA=$DEPLOY_SHA"

mkdir -p "$DEST/deploy"
rsync -a --delete \
  "${RSYNC_EXCLUDE_VENV[@]}" \
  --exclude '.git' \
  --exclude 'state' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  --exclude '.install_deps_stamp' \
  "$ROOT/" "$DEST/"

cat > "$DEST/deploy/deploy.conf" << EOF
# Written by sync_to_sd_mac.sh — $(date -Iseconds)
DEPLOY_SOURCE=$DEPLOY_SOURCE
AUTO_PULL=$AUTO_PULL
DEPLOY_SHA=$DEPLOY_SHA
GITHUB_REPO=$GITHUB_REPO
GITHUB_BRANCH=$GITHUB_BRANCH
ENABLE_SERVICES=$ENABLE_SERVICES
EOF

cp "$ROOT/deploy/user-data" "$BOOT_VOL/user-data"
touch "$BOOT_VOL/ssh"

# New instance_id so cloud-init re-runs user-data/runcmd (rewrite file — sed on FAT is unreliable).
INSTANCE_ID="${INSTANCE_ID:-driftline-$(date +%Y%m%d-%H%M%S)}"
if [[ -f "$BOOT_VOL/meta-data" ]]; then
  awk -v id="$INSTANCE_ID" '
    /^instance_id:/ { print "instance_id: " id; next }
    { print }
  ' "$BOOT_VOL/meta-data" > "$BOOT_VOL/meta-data.new"
  mv "$BOOT_VOL/meta-data.new" "$BOOT_VOL/meta-data"
  echo "    cloud-init instance_id → $INSTANCE_ID (forces first-boot runcmd)"
fi
mkdir -p "$DEST/boot-logs"

if [[ "${WIPE_CLOUD_INIT:-1}" == "1" ]] && [[ -x "$ROOT/scripts/wipe_cloud_init_mac.sh" ]]; then
  echo "==> Resetting cloud-init cache on SD root (forces first-boot runcmd)..."
  if "$ROOT/scripts/wipe_cloud_init_mac.sh" 2>/dev/null; then
    echo "    cloud-init cache cleared"
  else
    echo "    WARN: could not wipe root FS (run in Terminal: sudo ./scripts/wipe_cloud_init_mac.sh)"
  fi
fi

# WiFi: only from gitignored local secrets (never from the repo tree)
if [[ -f "$SECRETS_DIR/network-config.local" ]]; then
  cp "$SECRETS_DIR/network-config.local" "$BOOT_VOL/network-config"
  echo "    WiFi: network-config.local → SD (not in git)"
elif [[ -f "$BOOT_VOL/network-config" ]]; then
  echo "    WiFi: leaving existing SD network-config"
else
  echo "    WiFi: skipped (create deploy/secrets/network-config.local from .example)"
fi
if [[ -f "$SECRETS_DIR/wpa_supplicant.conf.local" ]]; then
  cp "$SECRETS_DIR/wpa_supplicant.conf.local" "$BOOT_VOL/wpa_supplicant.conf"
fi
if [[ -f "$SECRETS_DIR/github_token" ]]; then
  mkdir -p "$DEST/deploy/secrets"
  cp "$SECRETS_DIR/github_token" "$DEST/deploy/secrets/github_token"
  echo "    GitHub token copied to SD (gitignored)"
fi
if ! grep -q '^dtparam=spi=on' "$BOOT_VOL/config.txt" 2>/dev/null; then
  echo 'dtparam=spi=on' >> "$BOOT_VOL/config.txt"
fi
if ! grep -q '^country=' "$BOOT_VOL/config.txt" 2>/dev/null; then
  echo 'country=US' >> "$BOOT_VOL/config.txt"
  echo "    WiFi country=US added to config.txt"
fi

chmod +x "$DEST/scripts/pi-deploy-sync.sh" "$DEST/scripts/boot_display.sh" \
  "$DEST/scripts/ensure_waveshare_vendor.sh" "$DEST/scripts/bundle_pi_offline.sh" \
  "$DEST/scripts/announce_network.sh" "$DEST/install.sh" 2>/dev/null || true

sync
echo ""
echo "Done. Boot partition ready."
echo "  deploy SHA : $DEPLOY_SHA"
echo "  On Pi boot : cloud-init install, then GitHub pull every 60s"
echo "  Push to $GITHUB_REPO → Pi auto-deploys within ~1 min"
if [[ "$DEPLOY_SOURCE" == "boot" ]]; then
  echo "  boot mode: Pi uses SD copy only (set DEPLOY_SOURCE=github for auto-pull)"
fi
