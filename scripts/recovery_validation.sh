#!/usr/bin/env bash
# Recovery acceptance checks (run on Pi after install_recovery_mode.sh).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/pi_install_user.sh
source "$ROOT/scripts/lib/pi_install_user.sh"

PI_USER="$(pi_install_user)"
PY="$ROOT/.venv/bin/python"
FAILED_STAGE=""
MON_PORT=8080

fail_stage() {
  FAILED_STAGE="$1"
  echo "FAILED_STAGE: $FAILED_STAGE"
  exit 1
}

if [[ "$(uname -s)" != "Linux" ]]; then
  fail_stage "not_linux"
fi

echo "=============================================="
echo " Recovery validation"
echo "=============================================="

if [[ ! -x "$PY" ]]; then
  fail_stage "venv_missing"
fi
echo "OK: venv"

if ! aplay -l 2>/dev/null | grep -qE 'card [0-9]+:'; then
  fail_stage "alsa_no_card"
fi
echo "OK: ALSA card present"

if ! aplay -D plughw:0,0 /dev/zero -d 1 -t raw -f S16_LE -r 8000 2>/dev/null; then
  fail_stage "alsa_plughw_open"
fi
echo "OK: plughw:0,0 opens"

if ! command -v fluidsynth >/dev/null 2>&1; then
  fail_stage "fluidsynth_binary_missing"
fi
echo "OK: fluidsynth package"

if ! systemctl is-enabled pi-ambient-synth-midi.service >/dev/null 2>&1; then
  fail_stage "midi_unit_not_enabled"
fi
if ! systemctl is-active --quiet pi-ambient-synth-midi.service; then
  fail_stage "midi_unit_not_active"
fi
echo "OK: pi-ambient-synth-midi active"

if ! systemctl is-active --quiet pi-ambient-synth-monitor.service; then
  fail_stage "monitor_unit_not_active"
fi
echo "OK: pi-ambient-synth-monitor active"

_jlog="$(journalctl -u pi-ambient-synth-midi.service -b --no-pager 2>/dev/null || true)"
if ! echo "$_jlog" | grep -qiE 'fluidsynth|AUDIO_MODE=fluidsynth'; then
  fail_stage "midi_not_fluidsynth_backend"
fi
echo "OK: MIDI bridge logs show FluidSynth path"

_midi_out="$(
  sudo -u "$PI_USER" env HOME="/home/$PI_USER" "$PY" "$ROOT/scripts/list_midi_devices.py" 2>/dev/null || true
)"
if echo "$_midi_out" | grep -qiE 'keystep|arturia'; then
  echo "OK: KeyStep/Arturia MIDI port visible"
elif echo "$_midi_out" | grep -q 'MIDI Input Ports'; then
  echo "WARN: no KeyStep/Arturia in list (plug data USB cable)"
else
  fail_stage "midi_list_failed"
fi

echo "==> noteon path (brief ALSA test; midi service paused)..."
_sudo() { [[ "$(id -u)" -eq 0 ]] && "$@" || sudo "$@"; }
_sudo systemctl stop pi-ambient-synth-midi.service 2>/dev/null || true
sleep 1
if ! sudo -u "$PI_USER" env HOME="/home/$PI_USER" INSTALL_ROOT="$ROOT" "$PY" -c "
import sys, time
from pathlib import Path
ROOT = Path('$ROOT')
sys.path.insert(0, str(ROOT / 'src'))
from config_loader import load_config
from fluidsynth_engine import FluidSynthEngine
config = load_config()
eng = FluidSynthEngine(config)
eng.start()
eng.note_on(60, 100)
time.sleep(0.4)
eng.note_off(60)
eng.stop()
print('noteon_ok')
"; then
  _sudo systemctl start pi-ambient-synth-midi.service 2>/dev/null || true
  fail_stage "noteon_test"
fi
_sudo systemctl start pi-ambient-synth-midi.service
sleep 1
echo "OK: FluidSynth noteon test"

_p="$("$PY" -c "
import yaml
from pathlib import Path
c = yaml.safe_load(Path('$ROOT/config/default.yaml').read_text())
print(int((c.get('monitor') or {}).get('port', 8080)))
" 2>/dev/null || echo 8080)"
[[ -n "$_p" ]] && MON_PORT="$_p"

if ! curl -sf --max-time 5 "http://127.0.0.1:${MON_PORT}/api/status" >/dev/null; then
  if ! curl -sf --max-time 5 "http://127.0.0.1:${MON_PORT}/" >/dev/null; then
    fail_stage "monitor_http"
  fi
fi
echo "OK: monitor HTTP on port $MON_PORT"

if systemctl is-active --quiet supercollider.service 2>/dev/null; then
  fail_stage "supercollider_still_active"
fi
if systemctl is-active --quiet pi-ambient-autobringup.service 2>/dev/null; then
  fail_stage "autobringup_still_active"
fi
if systemctl is-active --quiet pi-ambient-synth-eink.service 2>/dev/null; then
  fail_stage "eink_still_active"
fi
echo "OK: legacy SC/autobringup/e-ink not active"

echo ""
echo "RECOVERY_OK"
exit 0
