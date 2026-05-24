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
# First boot installs from the SD copy (reliable offline); timer pulls GitHub once online.
DEPLOY_SOURCE="${DEPLOY_SOURCE:-boot}"
AUTO_PULL="${AUTO_PULL:-1}"
if [[ -z "${DEPLOY_SHA:-}" ]]; then
  DEPLOY_SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo boot-sd)"
fi
GITHUB_REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
GITHUB_BRANCH="${GITHUB_BRANCH:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
ENABLE_SERVICES="${ENABLE_SERVICES:-1}"
BUNDLE_OFFLINE="${BUNDLE_OFFLINE:-1}"
# Pi 3 + KeyStep production stack (override: DEFAULT_AUDIO_MODE=ambient)
DEFAULT_AUDIO_MODE="${DEFAULT_AUDIO_MODE:-fluidsynth}"
FACTORY_BOOT="${FACTORY_BOOT:-1}"
BUNDLE_V1="${BUNDLE_V1:-$([[ "$DEFAULT_AUDIO_MODE" == "fluidsynth" ]] && echo 1 || echo 0)}"
export BUNDLE_V1 DEFAULT_AUDIO_MODE
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
AUDIO_MODE=$DEFAULT_AUDIO_MODE
FACTORY_BOOT=$FACTORY_BOOT
EOF

USER_DATA_SRC="${USER_DATA_FILE:-$ROOT/deploy/user-data}"
if [[ "${AUTBRINGUP:-0}" == "1" && -f "$ROOT/deploy/user-data.autobringup" ]]; then
  USER_DATA_SRC="$ROOT/deploy/user-data.autobringup"
fi
cp "$USER_DATA_SRC" "$BOOT_VOL/user-data"
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
echo "# pi-ambient-firstboot-status (Mac sync $(date -Iseconds)) — SD not booted yet" > "$BOOT_VOL/pi-ambient-firstboot-status.txt"
if [[ "${AUTBRINGUP:-0}" == "1" ]]; then
  cat > "$BOOT_VOL/DRIFTLINE_BRINGUP_REPORT.txt" <<EOF
DRIFTLINE SYNTH — BRING-UP REPORT (not generated yet)
Mac sync: $(date -Iseconds)

Phase 1 (prove architecture on Pi):
  1. Boot until pi-boot-sentinel.txt + SSH work
  2. On Pi: sudo /boot/firmware/pi-ambient-synth/scripts/install_autobringup_on_pi.sh
  3. Reboot; validate with validate_autobringup_on_pi.sh or read_autobringup_report_mac.sh
EOF
fi

if [[ "${WIPE_CLOUD_INIT:-1}" == "1" ]] && [[ -x "$ROOT/scripts/wipe_cloud_init_mac.sh" ]]; then
  echo "==> Resetting cloud-init cache on SD root (forces first-boot runcmd)..."
  if "$ROOT/scripts/wipe_cloud_init_mac.sh" 2>/dev/null; then
    echo "    cloud-init cache cleared"
  else
    echo "    WARN: could not wipe root FS (run in Terminal: sudo ./scripts/wipe_cloud_init_mac.sh)"
  fi
fi

# WiFi: only from gitignored local secrets (never from the repo tree)
copy_network_config() {
  local src="$1" dst="$2"
  awk '!/^#cloud-config[[:space:]]*$/ { print }' "$src" >"$dst"
  if head -1 "$dst" | grep -q '^#cloud-config'; then
    echo "ERROR: network-config still contains #cloud-config header" >&2
    exit 1
  fi
}

if [[ -f "$SECRETS_DIR/network-config.local" ]]; then
  copy_network_config "$SECRETS_DIR/network-config.local" "$BOOT_VOL/network-config"
  echo "    WiFi: network-config.local → SD (stripped #cloud-config if present)"
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

# Legacy flash_sd_mac.sh cmdline hook runs full install.sh before cloud-init — remove it.
if [[ -f "$BOOT_VOL/cmdline.txt" ]] && grep -q 'pi-ambient-synth-firstboot' "$BOOT_VOL/cmdline.txt" 2>/dev/null; then
  echo "    WARN: stripping legacy cmdline systemd.run (blocks fast boot)"
  sed -i.bak 's/ systemd\.run=[^ ]*//g; s/ systemd\.run_success_action=[^ ]*//g; s/ systemd\.unit=kernel-command-line\.service//g' \
    "$BOOT_VOL/cmdline.txt" 2>/dev/null || true
fi

chmod +x "$DEST/scripts/pi_boot_sentinel.sh" "$DEST/scripts/pi-deploy-sync.sh" "$DEST/scripts/boot_display.sh" \
  "$DEST/scripts/ensure_waveshare_vendor.sh" "$DEST/scripts/bundle_pi_offline.sh" \
  "$DEST/scripts/announce_network.sh" "$DEST/install.sh" \
  "$DEST/scripts/pi_ambient_autobringup.sh" "$DEST/scripts/install_autobringup_unit.sh" \
  "$DEST/scripts/install_autobringup_on_pi.sh" "$DEST/scripts/validate_autobringup_on_pi.sh" \
  "$DEST/scripts/pi_ambient_firstboot.sh" "$DEST/scripts/install_firstboot_unit.sh" \
  "$DEST/scripts/firstboot-network-debug.sh" \
  "$DEST/scripts/firstboot-light.sh" "$DEST/scripts/firstboot-heavy.sh" \
  "$DEST/scripts/install-v1-heavy.sh" "$DEST/scripts/eink_early_progress.py" \
  "$DEST/scripts/build_factory_sd_mac.sh" "$DEST/scripts/eink_boot_early.sh" \
  "$DEST/scripts/lib/mask_network_wait.sh" "$DEST/scripts/lib/wifi_state.sh" \
  "$DEST/scripts/lib/wifi_debug_bootfs.sh" "$DEST/scripts/lib/eink_firstboot_log.sh" \
  "$DEST/scripts/lib/eink_exclusive.sh" \
  "$DEST/scripts/eink_display.py" \
  "$DEST/scripts/eink_firstboot_validation_mode.sh" \
  "$DEST/scripts/eink_known_good_direct_test.sh" \
  "$DEST/scripts/eink_official_minimal_test.py" \
  "$DEST/src/eink_official_driver.py" 2>/dev/null || true

sync

_SENTINEL_OK=0
echo ""
echo "==> Boot sentinel (proves Pi reached Linux)..."
if [[ -x "$ROOT/scripts/install_boot_sentinel_rootfs.sh" ]]; then
  if sudo -n "$ROOT/scripts/install_boot_sentinel_rootfs.sh" "$BOOT_VOL" 2>/dev/null \
    || sudo "$ROOT/scripts/install_boot_sentinel_rootfs.sh" "$BOOT_VOL" 2>/dev/null; then
    echo "    Root FS: pi-ambient-boot-sentinel.service enabled (basic.target)"
    _SENTINEL_OK=1
  else
    echo "    Root FS install needs admin (passwordless sudo failed)."
    echo "    Run: sudo $ROOT/scripts/install_boot_sentinel_rootfs.sh $BOOT_VOL"
    echo "    Or double-click: scripts/INSTALL_BOOT_SENTINEL.command"
  fi
fi
if [[ "$_SENTINEL_OK" != 1 ]] && [[ -x "$ROOT/scripts/install_boot_sentinel_cmdline.sh" ]]; then
  echo "    Applying cmdline fallback (systemd.run pi_boot_sentinel.sh)..."
  bash "$ROOT/scripts/install_boot_sentinel_cmdline.sh" "$BOOT_VOL"
  _SENTINEL_OK=1
fi
if [[ "${FACTORY_SD:-0}" == 1 && "$_SENTINEL_OK" != 1 ]]; then
  echo "ERROR: factory SD requires boot sentinel (root or cmdline)." >&2
  exit 1
fi

if [[ "${AUTBRINGUP:-0}" == 1 ]]; then
  echo "==> Autobringup (phase 1: install on Pi after SSH — not Mac rootfs)"
  echo "    On Pi: sudo /boot/firmware/pi-ambient-synth/scripts/install_autobringup_on_pi.sh"
  echo "    See docs/autobringup.md"
  if [[ "${AUTBRINGUP_ROOTFS:-0}" == 1 && -x "$ROOT/scripts/install_autobringup_rootfs.sh" ]]; then
    echo "    AUTBRINGUP_ROOTFS=1: attempting offline root install (optional, often flaky)..."
    if sudo -n "$ROOT/scripts/install_autobringup_rootfs.sh" "$BOOT_VOL" 2>/dev/null \
      || sudo "$ROOT/scripts/install_autobringup_rootfs.sh" "$BOOT_VOL" 2>/dev/null; then
      echo "    autobringup unit on SD root (e2tools/debugfs)"
    else
      echo "    WARN: Mac rootfs autobringup install failed — use Pi install path above." >&2
    fi
  fi
fi

echo ""
echo "Done. Boot partition ready."
echo "  deploy SHA : $DEPLOY_SHA"
echo "  Boot proof  : $BOOT_VOL/pi-boot-sentinel.txt (must appear after 3–5 min — see docs/boot-sentinel.md)"
echo "  After sentinel: cloud-init → pi-ambient-firstboot.service"
echo "  Status log  : $BOOT_VOL/pi-ambient-firstboot-status.txt"
echo "  Factory    : ./scripts/build_factory_sd_mac.sh $BOOT_VOL"
echo "  Autobringup: ./scripts/build_autobringup_sd_mac.sh $BOOT_VOL"
echo "  Push to $GITHUB_REPO → Pi auto-deploys within ~1 min"
if [[ "$DEPLOY_SOURCE" == "boot" ]]; then
  echo "  boot mode: Pi uses SD copy only (set DEPLOY_SOURCE=github for auto-pull)"
fi
