#!/usr/bin/env bash
# Fetch latest audio/restart fixes from main and restart synth services + test beep.
#   curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/recover_pi_audio.sh | bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
BASE="${GITHUB_RAW_BASE:-https://raw.githubusercontent.com/samjhill/driftline-synth/main}"

log() { echo "$(date -Iseconds) [recover-audio] $*"; }

fetch() {
  local rel="$1"
  local dest="$INSTALL_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  curl -fsSL --connect-timeout 20 --max-time 120 "$BASE/$rel" -o "$dest"
}

log "sync audio stack scripts from $BASE"
fetch scripts/lib/audio_stack.sh
fetch scripts/restart_synth_services.sh
fetch scripts/start_scsynth_alsa.sh
fetch scripts/run_sclang_engine.sh
fetch systemd/supercollider.service
fetch systemd/pi-ambient-synth.service
fetch src/main.py
fetch src/midi_controller.py
fetch synth/pi_bind_port.scd
fetch synth/ambient_engine.scd
chmod +x "$INSTALL_DIR/scripts/restart_synth_services.sh" \
  "$INSTALL_DIR/scripts/start_scsynth_alsa.sh" \
  "$INSTALL_DIR/scripts/run_sclang_engine.sh" 2>/dev/null || true

log "restart supercollider + pi-ambient-synth"
INSTALL_DIR="$INSTALL_DIR" "$INSTALL_DIR/scripts/restart_synth_services.sh"

log "OSC test beep"
if [[ -x "$INSTALL_DIR/.venv/bin/python" && -f "$INSTALL_DIR/scripts/test_osc.py" ]]; then
  "$INSTALL_DIR/.venv/bin/python" "$INSTALL_DIR/scripts/test_osc.py" || true
else
  log "skip test_osc (venv or script missing)"
fi

log "done — check: systemctl is-active supercollider pi-ambient-synth"
systemctl is-active supercollider.service pi-ambient-synth.service 2>/dev/null || true
echo "--- supercollider (test_beep / errors) ---"
journalctl -u supercollider -n 25 --no-pager 2>/dev/null | grep -iE 'test_beep|Engine synths|listening|ERROR|linearRamp|jack playback' || true
if command -v jack_lsp >/dev/null; then
  echo "--- jack connections ---"
  jack_lsp 2>/dev/null | head -20 || true
fi
