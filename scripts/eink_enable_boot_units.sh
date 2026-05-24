#!/usr/bin/env bash
# Deprecated wrapper — single owner: pi-ambient-synth-eink.service
set -euo pipefail
ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
exec bash "$ROOT/scripts/eink_install_systemd.sh"
