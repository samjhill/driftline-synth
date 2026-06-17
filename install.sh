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

chmod +x "$ROOT/scripts/ensure_waveshare_vendor.sh" "$ROOT/scripts/boot_display.sh" \
  "$ROOT/scripts/run_sclang_engine.sh" 2>/dev/null || true

# Avoid debconf dialogs (jackd2, etc.) over SSH — installs must be fully non-interactive.
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(
  -o Dpkg::Options::="--force-confdef"
  -o Dpkg::Options::="--force-confold"
)
preseed_debconf() {
  if command -v debconf-set-selections &>/dev/null; then
    sudo debconf-set-selections <<'EOF' 2>/dev/null || true
jackd2 jackd/tweak_rt_limits boolean false
jackd2 jackd/start_rt boolean false
EOF
  fi
}

if $QUICK && [[ -f "$DEPS_STAMP" ]]; then
  echo "==> Skipping apt (--quick, deps already installed)"
else
  fb_eink install "System packages" "apt update" "may take 10+ min"
  echo "==> Installing system packages (non-interactive)..."
  preseed_debconf
  sudo apt-get update -qq
  fb_eink install "Installing" "supercollider" "audio engine"
  sudo apt-get install -y "${APT_OPTS[@]}" \
    python3-venv python3-pip python3-dev \
    python3-pil python3-yaml python3-gpiozero python3-lgpio \
    supercollider \
    git libasound2-dev \
    curl \
    libjack-jackd2-dev jackd2 \
    python3-spidev python3-rpi.gpio \
    spi-tools
  date -Iseconds > "$DEPS_STAMP"
fi

echo "==> Waveshare e-ink driver..."
if "$ROOT/scripts/ensure_waveshare_vendor.sh"; then
  fb_eink install "Display" "E-ink driver" "ready"
else
  echo "WARN: Waveshare driver install failed — e-ink may stay on old image until fixed"
fi

if command -v raspi-config &>/dev/null; then
  fb_eink install "Hardware" "SPI for e-ink" ""
  echo "==> Enabling SPI (non-interactive)..."
  sudo raspi-config nonint do_spi 0 || true
fi

fb_eink install "Python" "virtualenv" "pip packages"
WHEELS="$ROOT/vendor/wheels"
PREBUILT_VENV=false
if [[ -x "$ROOT/.venv/bin/python" ]] && [[ -f "$ROOT/.venv/.prebuilt_stamp" ]]; then
  PREBUILT_VENV=true
  echo "==> Using pre-built .venv from SD (offline)"
fi

if ! $PREBUILT_VENV; then
echo "==> Creating Python virtual environment..."
# system-site-packages: use apt python3-lgpio for gpiozero / e-ink (no pip swig build).
python3 -m venv --system-site-packages "$ROOT/.venv"
  "$ROOT/.venv/bin/pip" install --upgrade pip -q
fi

if [[ -d "$WHEELS" ]] && compgen -G "$WHEELS/*.whl" >/dev/null; then
  echo "==> Installing from bundled wheels (offline)..."
  if ! $PREBUILT_VENV; then
    "$ROOT/.venv/bin/pip" install -q --no-index --find-links "$WHEELS" \
      -r "$ROOT/requirements-bundle.txt" 2>/dev/null || \
    "$ROOT/.venv/bin/pip" install -q --find-links "$WHEELS" \
      -r "$ROOT/requirements-bundle.txt"
  fi
  "$ROOT/.venv/bin/pip" install -q --no-index --find-links "$WHEELS" \
    -r "$ROOT/requirements-pi.txt" 2>/dev/null || \
  "$ROOT/.venv/bin/pip" install -q --find-links "$WHEELS" \
    -r "$ROOT/requirements-pi.txt" || true
else
  echo "==> Installing from PyPI (no vendor/wheels on SD)..."
  "$ROOT/.venv/bin/pip" install -r "$ROOT/requirements.txt" || {
    echo "Note: spidev/RPi.GPIO may fail off-Pi — retry on Raspberry Pi"
    "$ROOT/.venv/bin/pip" install mido python-rtmidi python-osc PyYAML Pillow numpy gpiozero || true
  }
fi

mkdir -p "$ROOT/state"

echo "==> State directory ($MARKER_DIR)..."
sudo mkdir -p "$MARKER_DIR"
sudo chown pi:pi "$MARKER_DIR"
sudo chmod 775 "$MARKER_DIR"

echo "==> GPIO access for e-ink (Pi 4/5)..."
sudo usermod -aG gpio,spi,i2c,dialout pi 2>/dev/null || sudo usermod -aG gpio,spi pi

fb_eink install "Services" "systemd units" "auto-start"
echo "==> Installing systemd unit files..."
sudo cp "$ROOT/systemd/supercollider.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-deploy.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-deploy.timer" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-boot-display.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-audio-display.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-monitor.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-network-announce.service" /etc/systemd/system/
chmod +x "$ROOT/scripts/boot_display.sh" "$ROOT/scripts/announce_network.sh"
sudo systemctl daemon-reload
sudo systemctl enable pi-ambient-synth-deploy.timer
sudo systemctl enable pi-ambient-synth-boot-display.service
sudo systemctl enable pi-ambient-synth-audio-display.service
sudo systemctl enable pi-ambient-synth-monitor.service
sudo systemctl enable pi-ambient-synth-network-announce.service

if $ENABLE_SERVICES; then
  fb_eink synth "Enabling" "synth + deploy" "almost done"
  echo "==> Enabling services..."
  sudo systemctl enable supercollider.service pi-ambient-synth.service
  sudo systemctl enable pi-ambient-synth-monitor.service
  echo "Services enabled. Start with: sudo systemctl start supercollider pi-ambient-synth pi-ambient-synth-monitor"
else
  echo "Systemd units installed but NOT enabled."
  echo "Run: ./install.sh --enable-services"
fi

fb_eink ready "Install complete" "Pi Ambient Synth" ""
if [[ -x "$ROOT/scripts/announce_network.sh" ]]; then
  INSTALL_DIR="$ROOT" "$ROOT/scripts/announce_network.sh" || true
fi
echo ""
echo "Install complete."
echo "  Test MIDI:  $ROOT/.venv/bin/python $ROOT/scripts/list_midi_devices.py"
echo "  Dev run:    $ROOT/scripts/run_dev.sh --no-eink"
echo "  Visual:     $ROOT/.venv/bin/python $ROOT/src/main.py --generate-visual /tmp/patch.png"
