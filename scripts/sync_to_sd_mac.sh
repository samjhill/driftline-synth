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
DEPLOY_SOURCE="${DEPLOY_SOURCE:-github}"
AUTO_PULL="${AUTO_PULL:-1}"
GITHUB_REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
GITHUB_BRANCH="${GITHUB_BRANCH:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
ENABLE_SERVICES="${ENABLE_SERVICES:-1}"
DEPLOY_SHA="${DEPLOY_SHA:-latest}"
SECRETS_DIR="$ROOT/deploy/secrets"

DEPLOY_SHA_FULL=""
if [[ "$DEPLOY_SHA" == "latest" ]]; then
  DEPLOY_SHA_FULL="(resolved on Pi from GitHub)"
elif [[ -n "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" ]]; then
  DEPLOY_SHA_FULL="$(git -C "$ROOT" rev-parse HEAD)"
fi

echo "==> Syncing to $DEST"
echo "    DEPLOY_SOURCE=$DEPLOY_SOURCE  AUTO_PULL=$AUTO_PULL  SHA=$DEPLOY_SHA"

mkdir -p "$DEST/deploy"
rsync -a --delete \
  --exclude '.venv' \
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

chmod +x "$DEST/scripts/pi-deploy-sync.sh" "$DEST/scripts/boot_display.sh" "$DEST/install.sh" 2>/dev/null || true

sync
echo ""
echo "Done. Boot partition ready."
echo "  deploy SHA : $DEPLOY_SHA"
echo "  On Pi boot : cloud-init install, then GitHub pull every 60s"
echo "  Push to $GITHUB_REPO → Pi auto-deploys within ~1 min"
if [[ "$DEPLOY_SOURCE" == "boot" ]]; then
  echo "  boot mode: Pi uses SD copy only (set DEPLOY_SOURCE=github for auto-pull)"
fi
