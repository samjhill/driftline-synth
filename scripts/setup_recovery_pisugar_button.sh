#!/usr/bin/env bash
# Recovery: enable PiSugar single-tap → patch reseed (no e-ink).
# Safe to run repeatedly. Requires pisugar-server (see RECOVERY.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/pi_install_user.sh
source "$ROOT/scripts/lib/pi_install_user.sh"

PI_USER="$(pi_install_user)"
PY="$ROOT/.venv/bin/python"

log() { echo "$(date -Iseconds) [recovery-pisugar] $*"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: run on the Raspberry Pi." >&2
  exit 1
fi

if [[ ! -x "$PY" ]]; then
  log "ERROR: venv missing — run ./scripts/install_recovery_mode.sh first"
  exit 1
fi

log "Enable PiSugar reseed in config (e-ink display off)..."
sudo -u "$PI_USER" env HOME="/home/$PI_USER" "$PY" -c "
from pathlib import Path
import yaml
p = Path('$ROOT/config/default.yaml')
data = yaml.safe_load(p.read_text())
data.setdefault('pisugar', {})['enabled'] = True
data['pisugar']['reseed_on_button'] = True
data['pisugar']['show_on_display'] = False
p.write_text(yaml.dump(data, default_flow_style=False, sort_keys=False))
print('    pisugar.enabled=true, reseed_on_button=true, show_on_display=false')
"

if ! systemctl is-active --quiet pisugar-server 2>/dev/null; then
  log "SKIP: pisugar-server not active"
  echo ""
  echo "PiSugar button reseed needs PiSugar Power Manager. On the Pi:"
  echo "  ./scripts/install_pisugar_server.sh"
  echo "  # then pick your board model when prompted"
  echo "  ./scripts/setup_recovery_pisugar_button.sh"
  exit 0
fi

if [[ ! -S /tmp/pisugar-server.sock ]]; then
  log "SKIP: /tmp/pisugar-server.sock missing (restart pisugar-server?)"
  exit 0
fi

INSTALL_DIR="$ROOT" bash "$ROOT/scripts/pi_setup_pisugar_reseed_button.sh"
log "Done — single tap on PiSugar button queues a new patch"
