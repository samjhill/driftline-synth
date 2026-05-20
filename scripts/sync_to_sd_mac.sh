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
DEPLOY_SOURCE="${DEPLOY_SOURCE:-boot}"
GITHUB_REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
GITHUB_BRANCH="${GITHUB_BRANCH:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
ENABLE_SERVICES="${ENABLE_SERVICES:-1}"
SECRETS_DIR="$ROOT/deploy/secrets"

if [[ -n "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" ]]; then
  DEPLOY_SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
  DEPLOY_SHA_FULL="$(git -C "$ROOT" rev-parse HEAD)"
else
  DEPLOY_SHA="local-$(date +%Y%m%d%H%M%S)"
  DEPLOY_SHA_FULL="$DEPLOY_SHA"
fi

echo "==> Syncing to $DEST"
echo "    DEPLOY_SOURCE=$DEPLOY_SOURCE  SHA=$DEPLOY_SHA ($DEPLOY_SHA_FULL)"

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
DEPLOY_SHA=$DEPLOY_SHA
DEPLOY_SHA_FULL=$DEPLOY_SHA_FULL
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
if ! grep -q '^dtparam=spi=on' "$BOOT_VOL/config.txt" 2>/dev/null; then
  echo 'dtparam=spi=on' >> "$BOOT_VOL/config.txt"
fi

chmod +x "$DEST/scripts/pi-deploy-sync.sh" "$DEST/install.sh" 2>/dev/null || true

sync
echo ""
echo "Done. Boot partition ready."
echo "  deploy SHA : $DEPLOY_SHA"
echo "  On Pi boot : auto-install via cloud-init + 90s update timer"
echo "  Re-sync    : run this script again after edits, then reboot Pi (or wait ~90s)"
if [[ "$DEPLOY_SOURCE" == "github" && -n "$GITHUB_REPO" ]]; then
  echo "  GitHub mode: Pi will curl github.com/$GITHUB_REPO/archive/<sha>.tar.gz"
  echo "  Push commit $DEPLOY_SHA_FULL then set DEPLOY_SHA on SD or in deploy.conf"
fi
