#!/usr/bin/env bash
# Install PiSugar Power Manager (pisugar-server) for button + battery API.
# Run on the Pi. Model selection is interactive (dpkg-reconfigure).
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: run on the Raspberry Pi." >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "==> Download PiSugar Power Manager installer..."
wget -q -O "$TMP" https://cdn.pisugar.com/release/pisugar-power-manager.sh
bash "$TMP" -c release

echo ""
echo "==> Board model (skip if socket already works after install)..."
if [[ -t 0 ]] && [[ -t 1 ]]; then
  dpkg-reconfigure pisugar-server || true
else
  echo "    non-interactive — using postinst default (reconfigure later if battery reads wrong)"
fi

systemctl enable --now pisugar-server
sleep 1

if [[ -S /tmp/pisugar-server.sock ]]; then
  echo "OK: pisugar-server active, socket present"
  bash "$(dirname "$0")/lib/pisugar_query.sh" get model 2>/dev/null || true
else
  echo "WARN: socket missing — check: systemctl status pisugar-server"
  exit 1
fi

echo ""
echo "==> Detect PiSugar board model on I2C..."
bash "$(dirname "$0")/detect_pisugar_model.sh" || {
  echo "WARN: auto-detect failed — run manually: sudo PISUGAR_MODEL='PiSugar 2 Pro' ./scripts/detect_pisugar_model.sh"
}

echo ""
echo "Next (from pi-ambient-synth): ./scripts/setup_recovery_pisugar_button.sh"
