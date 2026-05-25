#!/usr/bin/env bash
# Enable Waveshare e-ink on recovery stack (ingest / GhostRoll known-good pattern).
# Usage: cd ~/pi-ambient-synth && sudo ./scripts/enable_recovery_eink.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/pi_install_user.sh
source "$ROOT/scripts/lib/pi_install_user.sh"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: run on the Raspberry Pi." >&2
  exit 1
fi

PI_USER="$(pi_install_user)"
PY="$ROOT/.venv/bin/python"

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo INSTALL_DIR="$ROOT" PI_USER="$PI_USER" bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(
  -o Dpkg::Options::="--force-confdef"
  -o Dpkg::Options::="--force-confold"
)

echo "=============================================="
echo " Recovery + e-ink (ingest-style PNG watch)"
echo " User: $PI_USER  Dir: $ROOT"
echo "=============================================="

echo "==> Apt: SPI + Pillow + GPIO (system python for panel driver)..."
apt-get update -qq
apt-get install -y "${APT_OPTS[@]}" \
  python3-pil python3-spidev python3-rpi.gpio git

if command -v raspi-config >/dev/null 2>&1; then
  echo "==> Enable SPI..."
  raspi-config nonint do_spi 0 || true
  modprobe spi_bcm2835 2>/dev/null || true
  modprobe spidev 2>/dev/null || true
fi

echo "==> Install stock Waveshare e-Paper library (ingest pattern)..."
bash "$ROOT/scripts/install_waveshare_epd.sh"

echo "==> Venv Pillow (status PNG rendering from app code)..."
if [[ -x "$PY" ]]; then
  sudo -u "$PI_USER" "$PY" -m pip install -q --upgrade pip
  sudo -u "$PI_USER" "$PY" -m pip install -q -r "$ROOT/requirements-pi-v1.txt" 2>/dev/null || \
    sudo -u "$PI_USER" "$PY" -m pip install -q Pillow PyYAML
fi

echo "==> Config: e-ink on (250x122 PNG, no sigils)..."
sudo -u "$PI_USER" env HOME="/home/$PI_USER" "$PY" -c "
from pathlib import Path
import yaml
p = Path('$ROOT/config/default.yaml')
data = yaml.safe_load(p.read_text())
e = data.setdefault('eink', {})
e['enabled'] = True
e['update_on_reseed'] = True
e['skip_numpy_sigil'] = True
e['show_playing_note'] = False
e['width'] = 250
e['height'] = 122
e['status_image_path'] = '/var/lib/pi-ambient-synth/eink-status.png'
p.write_text(yaml.dump(data, default_flow_style=False, sort_keys=False))
"

mkdir -p /etc/pi-ambient-synth /var/lib/pi-ambient-synth
cp "$ROOT/deploy/pi-eink.env" /etc/pi-ambient-synth/eink.env
chown root:root /etc/pi-ambient-synth/eink.env
chmod 644 /etc/pi-ambient-synth/eink.env
chown "$PI_USER:$PI_USER" /var/lib/pi-ambient-synth

echo "==> Stop legacy queue-based e-ink holders..."
bash "$ROOT/scripts/eink_stop_competing_services.sh" 2>/dev/null || true
systemctl stop pi-ambient-synth-eink.service 2>/dev/null || true
pkill -f eink_service.py 2>/dev/null || true
pkill -f pi_eink_waveshare 2>/dev/null || true
sleep 2

echo "==> Boot status PNG..."
sudo -u "$PI_USER" env HOME="/home/$PI_USER" PYTHONPATH="$ROOT/src" "$PY" -c "
from config_loader import load_config
from eink_status_png import write_status_png
write_status_png(load_config(), phase='boot', title='Pi Ambient Synth', subtitle='Audio ready', detail='')
print('    wrote /var/lib/pi-ambient-synth/eink-status.png')
"

echo "==> systemd: pi-ambient-synth-eink.service (root, stock driver)..."
systemctl unmask pi-ambient-synth-eink.service 2>/dev/null || true
cp "$ROOT/systemd/pi-ambient-synth-eink.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable pi-ambient-synth-eink.service
systemctl restart pi-ambient-synth-eink.service

systemctl restart pi-ambient-synth-midi.service

sleep 3
echo ""
echo "--- Services ---"
systemctl is-active pi-ambient-synth-midi.service pi-ambient-synth-eink.service 2>/dev/null || true
echo ""
echo "--- Panel driver ---"
python3 -c 'from waveshare_epd import epd2in13_V4; print("waveshare_epd OK")' 2>&1 || true
echo ""
echo "Test: .venv/bin/python scripts/eink_enqueue.py patch --from-state"
echo "      journalctl -u pi-ambient-synth-eink -f"
echo "Validate: ./scripts/validate_recovery_eink.sh"
