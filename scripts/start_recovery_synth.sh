#!/usr/bin/env bash
# Start / restart recovery stack and print status (run on Pi).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/pi_install_user.sh
source "$ROOT/scripts/lib/pi_install_user.sh"

PI_USER="$(pi_install_user)"
PY="$ROOT/.venv/bin/python"
MON_PORT=8080
if [[ -f "$ROOT/config/default.yaml" ]]; then
  _p="$("$PY" -c "
import yaml
from pathlib import Path
c = yaml.safe_load(Path('$ROOT/config/default.yaml').read_text())
print(int((c.get('monitor') or {}).get('port', 8080)))
" 2>/dev/null || echo 8080)"
  [[ -n "$_p" ]] && MON_PORT="$_p"
fi

_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

echo "==> Recovery synth — start"
_sudo systemctl restart pi-ambient-synth-midi.service pi-ambient-synth-monitor.service
bash "$ROOT/scripts/setup_recovery_pisugar_button.sh" || true
sleep 2

echo ""
echo "--- ALSA ---"
aplay -l 2>/dev/null | head -8 || echo "(aplay -l failed)"
if aplay -D plughw:0,0 /dev/zero -d 1 -t raw -f S16_LE -r 8000 2>/dev/null; then
  echo "    plughw:0,0: open OK"
else
  echo "    WARN: plughw:0,0 test failed (headphones may still work)"
fi

echo ""
echo "--- Audio mode ---"
if [[ -f /etc/pi-ambient-synth/audio-mode.conf ]]; then
  cat /etc/pi-ambient-synth/audio-mode.conf
else
  echo "    (no /etc/pi-ambient-synth/audio-mode.conf)"
fi

echo ""
echo "--- Services ---"
systemctl is-active pi-ambient-synth-midi.service pi-ambient-synth-monitor.service 2>/dev/null || true
systemctl is-enabled pi-ambient-synth-midi.service pi-ambient-synth-monitor.service 2>/dev/null || true

echo ""
echo "--- MIDI devices ---"
if [[ -x "$PY" ]]; then
  sudo -u "$PI_USER" env HOME="/home/$PI_USER" "$PY" "$ROOT/scripts/list_midi_devices.py" 2>/dev/null || true
else
  echo "    venv missing — run install_recovery_mode.sh"
fi

_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo ""
echo "--- Monitor ---"
echo "    http://${_ip:-<pi-ip>}:$MON_PORT/"
echo "    http://raspberrypi.local:$MON_PORT/  (if mDNS works)"

echo ""
echo "Play KeyStep (data USB). If you plugged in **after** boot and hear nothing:

```bash
sudo systemctl restart pi-ambient-synth-midi.service
```

Reseed: PiSugar single tap, Shift+Play, or monitor **New patch** button."
echo "Validate: ./scripts/recovery_validation.sh"
