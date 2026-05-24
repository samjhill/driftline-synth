#!/usr/bin/env bash
# Isolated validation — strict BUSY, known-good minimal test only.
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
export EINK_VALIDATE_BUSY=1
export INSTALL_DIR="$ROOT"

echo "==> Strict validation (EINK_VALIDATE_BUSY=1)"
exec "$(dirname "$0")/eink_known_good_direct_test.sh" "$@"
