#!/usr/bin/env bash
# Download Pi aarch64 wheels (via Docker). See bundle_pi_offline.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/scripts/bundle_pi_offline.sh"
