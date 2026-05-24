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
  "$ROOT/scripts/eink_prepare_boot.sh" "$ROOT/scripts/eink_enable_boot_units.sh" \
  "$ROOT/scripts/eink_service.py" "$ROOT/scripts/eink_enqueue.py" \
  "$ROOT/scripts/eink_install_systemd.sh" "$ROOT/scripts/eink_kill_legacy_holders.sh" \
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

_audio_mode=""
if [[ -f "$ROOT/deploy/deploy.conf" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/deploy/deploy.conf" 2>/dev/null || true
  _audio_mode="${AUDIO_MODE:-}"
fi
_v1_only=false
if [[ "${INSTALL_V1_ONLY:-0}" == "1" ]] || [[ "$_audio_mode" == "fluidsynth" ]]; then
  _v1_only=true
fi

if $QUICK && [[ -f "$DEPS_STAMP" ]]; then
  echo "==> Skipping apt (--quick, deps already installed)"
else
  fb_eink install "System packages" "apt update" "may take 10+ min"
  echo "==> Installing system packages (non-interactive)..."
  preseed_debconf
  sudo apt-get update -qq
  if $_v1_only && [[ -f "$ROOT/deploy/pi-v1-apt.list" ]]; then
    echo "==> FluidSynth V1 package set (no SuperCollider/JACK)..."
    mapfile -t _v1_pkgs < <(grep -v '^#' "$ROOT/deploy/pi-v1-apt.list" | grep -v '^[[:space:]]*$' || true)
    sudo apt-get install -y "${APT_OPTS[@]}" "${_v1_pkgs[@]}"
  else
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
  fi
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

_bundle_req="$ROOT/requirements-bundle.txt"
if $_v1_only && [[ -f "$ROOT/requirements-pi-v1.txt" ]]; then
  _bundle_req="$ROOT/requirements-pi-v1.txt"
fi
if [[ -d "$WHEELS" ]] && compgen -G "$WHEELS/*.whl" >/dev/null; then
  echo "==> Installing from bundled wheels (offline)..."
  if ! $PREBUILT_VENV; then
    "$ROOT/.venv/bin/pip" install -q --no-index --find-links "$WHEELS" \
      -r "$_bundle_req" 2>/dev/null || \
    "$ROOT/.venv/bin/pip" install -q --find-links "$WHEELS" \
      -r "$_bundle_req"
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

echo "==> E-ink log (/var/log/pi-ambient-synth-eink.log)..."
sudo touch /var/log/pi-ambient-synth-eink.log
sudo chown pi:pi /var/log/pi-ambient-synth-eink.log
sudo chmod 664 /var/log/pi-ambient-synth-eink.log

echo "==> GPIO access for e-ink (Pi 4/5)..."
sudo usermod -aG gpio,spi,i2c,dialout,adm,audio pi 2>/dev/null || sudo usermod -aG gpio,spi,adm,audio pi

fb_eink install "Services" "systemd units" "auto-start"
echo "==> Installing systemd unit files..."
# shellcheck source=scripts/lib/audio_stack.sh
source "$ROOT/scripts/lib/audio_stack.sh"
install_sc_systemd_units "$ROOT"
sudo mkdir -p /etc/pi-ambient-synth
_audio_mode=""
if [[ -f "$ROOT/deploy/deploy.conf" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/deploy/deploy.conf" 2>/dev/null || true
  _audio_mode="${AUDIO_MODE:-}"
fi
case "$_audio_mode" in
  fluidsynth)
    if [[ -f "$ROOT/deploy/pi-audio-mode-fluidsynth.conf" ]]; then
      sudo cp "$ROOT/deploy/pi-audio-mode-fluidsynth.conf" /etc/pi-ambient-synth/audio-mode.conf
    fi
    ;;
  flues)
    if [[ -f "$ROOT/deploy/pi-audio-mode-flues.conf" ]]; then
      sudo cp "$ROOT/deploy/pi-audio-mode-flues.conf" /etc/pi-ambient-synth/audio-mode.conf
    fi
    ;;
  direct_keys)
    if [[ -f "$ROOT/deploy/pi-audio-mode.conf" ]]; then
      sudo cp "$ROOT/deploy/pi-audio-mode.conf" /etc/pi-ambient-synth/audio-mode.conf
    fi
    ;;
  *)
    if [[ -f "$ROOT/deploy/pi-audio-mode-ambient.conf" ]]; then
      sudo cp "$ROOT/deploy/pi-audio-mode-ambient.conf" /etc/pi-ambient-synth/audio-mode.conf
    elif [[ -f "$ROOT/deploy/pi-audio-mode.conf" ]]; then
      sudo cp "$ROOT/deploy/pi-audio-mode.conf" /etc/pi-ambient-synth/audio-mode.conf
    fi
    ;;
esac
sudo cp "$ROOT/systemd/pi-ambient-synth-deploy.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-deploy.timer" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-eink.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/pi-ambient-synth-monitor.service" /etc/systemd/system/
# Legacy display units kept in repo for reference — not enabled (see eink_install_systemd.sh).
chmod +x "$ROOT/scripts/boot_display.sh" "$ROOT/scripts/announce_network.sh" \
  "$ROOT/scripts/setup_pi_audio.sh" "$ROOT/scripts/diagnose_audio.sh" 2>/dev/null || true
if [[ -x "$ROOT/scripts/setup_pi_audio.sh" ]]; then
  echo "==> Pi audio (headphone jack, no JACK)..."
  bash "$ROOT/scripts/setup_pi_audio.sh" || echo "WARN: setup_pi_audio.sh failed"
fi
sudo systemctl daemon-reload

echo "==> Disable GhostRoll autostart (Waveshare HAT → Pi Ambient Synth)..."
if [[ -f "$ROOT/scripts/lib_disable_ghostroll.sh" ]]; then
  # shellcheck source=scripts/lib_disable_ghostroll.sh
  source "$ROOT/scripts/lib_disable_ghostroll.sh"
  disable_ghostroll_autostart || true
fi

sudo systemctl enable pi-ambient-synth-deploy.timer
bash "$ROOT/scripts/eink_install_systemd.sh"
sudo systemctl enable pi-ambient-synth-monitor.service

if $ENABLE_SERVICES; then
  fb_eink synth "Enabling" "synth + deploy" "almost done"
  echo "==> Enabling services..."
  if [[ -f /etc/pi-ambient-synth/audio-mode.conf ]] \
    && grep -q 'AUDIO_MODE=fluidsynth' /etc/pi-ambient-synth/audio-mode.conf 2>/dev/null \
    && [[ -x "$ROOT/scripts/pi_enable_fluidsynth_engine.sh" ]]; then
    echo "==> FluidSynth audio mode (KeyStep → MIDI bridge → headphones)"
    bash "$ROOT/scripts/pi_enable_fluidsynth_engine.sh"
  else
    sudo systemctl enable supercollider.service pi-ambient-synth.service
    sudo systemctl enable pi-ambient-synth-monitor.service
    echo "Services enabled. Start with: sudo systemctl start supercollider pi-ambient-synth pi-ambient-synth-monitor"
  fi
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
