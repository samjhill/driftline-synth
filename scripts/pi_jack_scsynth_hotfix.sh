#!/usr/bin/env bash
# Deprecated wrapper — use pi_verify.sh (one entry, internal retries).
#   curl -fsSL .../main/scripts/pi_verify.sh | bash
#   ./scripts/run_pi_verify.sh
set -euo pipefail
case "${1:-}" in
  fetch-only|fetch) set -- sync ;;
  audio-only|audio) set -- audio ;;
  smoke-only|smoke) set -- all ;;
  services-only|services) set -- services ;;
esac
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
REF="${GITHUB_REF:-main}"
BASE="https://raw.githubusercontent.com/${REPO}/${REF}"
mkdir -p "$INSTALL_DIR/scripts"
curl -fsSL "${BASE}/scripts/pi_verify.sh" -o "$INSTALL_DIR/scripts/pi_verify.sh"
chmod +x "$INSTALL_DIR/scripts/pi_verify.sh"
export GITHUB_REF="$REF"
exec "$INSTALL_DIR/scripts/pi_verify.sh" "${1:-all}"
