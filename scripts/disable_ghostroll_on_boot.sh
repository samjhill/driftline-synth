#!/usr/bin/env bash
# Stop GhostRoll and prevent it from starting on boot (frees Waveshare e-ink for Pi Ambient Synth).
#   curl -fsSL "https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/disable_ghostroll_on_boot.sh" | bash
set -euo pipefail

LIB="$(dirname "${BASH_SOURCE[0]:-$0}")/lib_disable_ghostroll.sh"
if [[ ! -f "$LIB" ]]; then
  LIB="$(mktemp)"
  curl -fsSL "https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/lib_disable_ghostroll.sh" -o "$LIB"
  trap 'rm -f "$LIB"' EXIT
fi
# shellcheck source=lib_disable_ghostroll.sh
source "$LIB"

echo "=== Disable GhostRoll on boot ==="
disable_ghostroll_autostart

echo ""
echo "Verify (should show masked / disabled):"
systemctl list-unit-files --no-pager 2>/dev/null | grep -i ghostroll || echo "(no ghostroll units)"
