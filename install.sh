#!/usr/bin/env bash
# Pi Ambient Synth — Raspberry Pi install script
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENABLE_SERVICES=false
QUICK=false
DEPS_STAMP="$ROOT/.install_deps_stamp"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
BOOT_DISPLAY="$ROOT/scripts/boot_display.sh"

fb_eink() {
  [[ "${INSTALL_FIRST_BOOT:-0}" == "1" ]] || return 0
  [[ -x "$BOOT_DISPLAY" ]] || return 0
  export FIRST_BOOT_TRACK=1
  export FIRST_BOOT_TOTAL="${FIRST_BOOT_TOTAL:-12}"
  export MARKER_DIR
  "$BOOT_DISPLAY" "$@" || true
}

for arg in "$@"; do
  case "$arg" in
    --enable-services) ENABLE_SERVICES=true ;;
    --quick) QUICK=true ;;
    -h|--help)
      echo "Usage: ./install.sh [--enable-services] [--quick]"
      echo "  --enable-services  Copy and enable systemd units"
      echo "  --quick            Skip apt if dependencies were installed before"
      exit 0
      ;;
  esac
done

if $QUICK && [[ -f "$DEPS_STAMP" ]]; then
  echo "==> Skipping apt (--quick, deps already installed)"
else
  fb_eink install "System packages" "apt update" "may take 10+ min"
  echo "==> Installing system packages..."
  sudo apt-get update -qq
  fb_eink install "Installing" "supercollider" "audio engine"
  sudo apt-get install -y \
    python3-venv python3-pip python3-dev \
    python3-pil python3-yaml \
    supercollider \
    git libasound2-dev \
    curl \
    libjack-jackd2-dev jackd2 \
    python3-spidev python3-rpi.gpio \
    spi-tools
  date -Iseconds > "$DEPS_STAMP"
fi

if command -v raspi-config &>/dev/null; then
  fb_eink install "Hardware" "SPI for e-ink" ""
  echo "==> Enabling SPI (non-interactive)..."
  sudo raspi-config nonint do_spi 0 || true
fi

fb_eink install "Python" "virtualenv" "pip packages"
echo "==> Creating Python virtual environment..."
python3 -m venv "$ROOT/.venv"
"$ROOT/.venv/bin/pip" install --upgrade pip
"$ROOT/.venv/bin/pip" install -r "$ROOT/requirements.txt" || {
  echo "Note: spidev/RPi.GPIO may fail off-Pi — retry on Raspberry Pi"
  "$ROOT/.venv/bin/pip" install mido python-rtmidi python-osc PyYAML Pillow numpy || true
}

mkdir -p "$ROOT/state"

fb_eink install "Services" "systemd units" "auto-start"
echo "==> Installing systemd unit files..."
sudo cp "$ROOT/systemd/supercollider.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-deploy.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-deploy.timer" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-boot-display.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-audio-display.service" /etc/systemd/system/
chmod +x "$ROOT/scripts/boot_display.sh"
sudo systemctl daemon-reload
sudo systemctl enable pi-ambient-synth-deploy.timer
sudo systemctl enable pi-ambient-synth-boot-display.service
sudo systemctl enable pi-ambient-synth-audio-display.service

if $ENABLE_SERVICES; then
  fb_eink synth "Enabling" "synth + deploy" "almost done"
  echo "==> Enabling services..."
  sudo systemctl enable supercollider.service pi-ambient-synth.service
  echo "Services enabled. Start with: sudo systemctl start supercollider pi-ambient-synth"
else
  echo "Systemd units installed but NOT enabled."
  echo "Run: ./install.sh --enable-services"
fi

fb_eink ready "Install complete" "Pi Ambient Synth" ""
echo ""
echo "Install complete."
echo "  Test MIDI:  $ROOT/.venv/bin/python $ROOT/scripts/list_midi_devices.py"
echo "  Dev run:    $ROOT/scripts/run_dev.sh --no-eink"
echo "  Visual:     $ROOT/.venv/bin/python $ROOT/src/main.py --generate-visual /tmp/patch.png"
