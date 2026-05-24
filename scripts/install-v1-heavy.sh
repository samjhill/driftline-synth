#!/usr/bin/env bash
# FluidSynth V1: venv from SD wheels only — no SuperCollider/JACK/numpy apt.
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
DEPS_STAMP="$ROOT/.install_deps_stamp"
WHEELS="$ROOT/vendor/wheels"

sudo mkdir -p /var/lib/pi-ambient-synth
sudo chown pi:pi /var/lib/pi-ambient-synth 2>/dev/null || true
sudo usermod -aG gpio,spi,i2c,dialout,adm,audio pi 2>/dev/null || true

if [[ -x "$ROOT/scripts/ensure_waveshare_vendor.sh" ]]; then
  bash "$ROOT/scripts/ensure_waveshare_vendor.sh" || true
fi

PREBUILT=false
if [[ -x "$ROOT/.venv/bin/python" ]] && [[ -f "$ROOT/.venv/.prebuilt_stamp" ]]; then
  PREBUILT=true
  echo "==> Using pre-built .venv from SD"
fi

if ! $PREBUILT; then
  echo "==> Creating venv (system-site-packages for apt gpio/pil)..."
  python3 -m venv --system-site-packages "$ROOT/.venv"
  "$ROOT/.venv/bin/pip" install --upgrade pip -q
fi

REQ_BUNDLE="$ROOT/requirements-pi-v1.txt"
[[ -f "$REQ_BUNDLE" ]] || REQ_BUNDLE="$ROOT/requirements-bundle.txt"

if [[ -d "$WHEELS" ]] && compgen -G "$WHEELS/*.whl" >/dev/null; then
  echo "==> pip offline from vendor/wheels..."
  if ! $PREBUILT; then
    timeout "${PIP_TIMEOUT:-300}" "$ROOT/.venv/bin/pip" install -q --no-index --find-links "$WHEELS" \
      -r "$REQ_BUNDLE" 2>/dev/null || \
    "$ROOT/.venv/bin/pip" install -q --find-links "$WHEELS" -r "$REQ_BUNDLE"
  fi
  "$ROOT/.venv/bin/pip" install -q --no-index --find-links "$WHEELS" \
    -r "$ROOT/requirements-pi.txt" 2>/dev/null || \
  "$ROOT/.venv/bin/pip" install -q --find-links "$WHEELS" -r "$ROOT/requirements-pi.txt" || true
else
  echo "==> pip from PyPI (no wheels on SD)..."
  "$ROOT/.venv/bin/pip" install -q mido python-rtmidi python-osc PyYAML Pillow gpiozero spidev RPi.GPIO || true
fi

mkdir -p "$ROOT/state"
date -Iseconds > "$DEPS_STAMP"

sudo mkdir -p /etc/pi-ambient-synth
if [[ -f "$ROOT/deploy/pi-audio-mode-fluidsynth.conf" ]]; then
  sudo cp "$ROOT/deploy/pi-audio-mode-fluidsynth.conf" /etc/pi-ambient-synth/audio-mode.conf
else
  echo "AUDIO_MODE=fluidsynth" | sudo tee /etc/pi-ambient-synth/audio-mode.conf >/dev/null
fi

sudo touch /var/log/pi-ambient-synth-eink.log
sudo chown pi:pi /var/log/pi-ambient-synth-eink.log 2>/dev/null || true

if [[ -f "$ROOT/scripts/lib_disable_ghostroll.sh" ]]; then
  # shellcheck source=scripts/lib_disable_ghostroll.sh
  source "$ROOT/scripts/lib_disable_ghostroll.sh"
  disable_ghostroll_autostart || true
fi

if [[ -x "$ROOT/scripts/setup_pi_audio.sh" ]]; then
  bash "$ROOT/scripts/setup_pi_audio.sh" || true
fi

echo "==> install-v1-heavy complete"
exit 0
