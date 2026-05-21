#!/usr/bin/env bash
# Emergency on-Pi fix when auto-deploy is stuck (bad SHA capture) and SC has no OSC engine.
# Run on the Pi: bash ~/pi-ambient-synth/scripts/pi_hotfix_deploy_and_audio.sh
# Or before recover exists on main:
#   curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/pi_hotfix_deploy_and_audio.sh | bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
LOG="/var/log/pi-ambient-synth-hotfix.log"

log() { echo "$(date -Iseconds) [hotfix] $*" | tee -a "$LOG"; }

log "Stopping deploy timer"
sudo systemctl stop pi-ambient-synth-deploy.timer 2>/dev/null || true

ann="$INSTALL_DIR/scripts/announce_network.py"
if [[ -f "$ann" ]] && ! grep -q 'file=sys.stderr' "$ann"; then
  log "Patching announce_network.py (stdout was breaking deploy SHA)"
  sudo sed -i \
    's/print(f"Network: \(ip\).*monitor {url}")/print(f"Network: {ip}  ({host}.local)  monitor {url}", file=sys.stderr)/' \
    "$ann" 2>/dev/null || python3 - <<'PY' "$ann"
import sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
old = 'print(f"Network: {ip}  ({host}.local)  monitor {url}")'
new = 'print(f"Network: {ip}  ({host}.local)  monitor {url}", file=sys.stderr)'
if old in t and "file=sys.stderr" not in t:
    p.write_text(t.replace(old, new, 1))
    print("patched", p)
PY
fi

deploy="$INSTALL_DIR/scripts/pi-deploy-sync.sh"
if [[ -f "$deploy" ]]; then
  if ! grep -q 'tee -a.*>&2' "$deploy" 2>/dev/null; then
    log "WARN: pi-deploy-sync.sh may still log to stdout — run recover_pi_from_github.sh"
  fi
  if grep -q 'wait_for_network || log "WARN: network not ready"' "$deploy" \
    && grep -A2 'resolve_target_sha()' "$deploy" | grep -q 'wait_for_network'; then
    log "WARN: old resolve_target_sha still calls wait_for_network — run recover"
  fi
fi

log "Killing orphan scsynth and restarting SuperCollider"
pkill -x scsynth 2>/dev/null || true
rm -f /var/lib/pi-ambient-synth/sc-engine-ready 2>/dev/null || true
sudo systemctl restart supercollider.service
sleep 20

log "Restarting synth controller"
sudo systemctl restart pi-ambient-synth.service

log "Checks:"
echo "  deploy log stderr fix: grep '>&2' $deploy | head -1"
echo "  announce stderr fix:   grep 'stderr' $ann | head -1"
echo "  SC ready marker:       ls -la /var/lib/pi-ambient-synth/sc-engine-ready 2>/dev/null || echo MISSING"
echo "  SC journal:"
sudo journalctl -u supercollider -n 40 --no-pager | grep -E 'engine script|listening on OSC|Engine synths|ERROR|scsynth running' || true
echo "  Full recover (recommended): curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/recover_pi_from_github.sh | bash"
