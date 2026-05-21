#!/usr/bin/env bash
# Enable Flues-Synth on Pi (replaces SuperCollider for KeyStep voices).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
CONF="/etc/pi-ambient-synth/audio-mode.conf"

sudo mkdir -p /etc/pi-ambient-synth
if [[ -f "$INSTALL_DIR/deploy/pi-audio-mode-flues.conf" ]]; then
  sudo cp "$INSTALL_DIR/deploy/pi-audio-mode-flues.conf" "$CONF"
else
  echo "AUDIO_MODE=flues" | sudo tee "$CONF" >/dev/null
fi

sudo rm -f /etc/systemd/system/pi-ambient-synth-midi.service.d/direct-keys.conf \
  /etc/systemd/system/pi-ambient-synth-midi.service.d/ambient-hybrid.conf 2>/dev/null || true
sudo systemctl stop pi-ambient-alsa-drone.service supercollider.service 2>/dev/null || true
sudo systemctl disable pi-ambient-alsa-drone.service 2>/dev/null || true

if [[ -x "$INSTALL_DIR/scripts/install_flues_synth.sh" ]]; then
  INSTALL_DIR="$INSTALL_DIR" "$INSTALL_DIR/scripts/install_flues_synth.sh"
fi

# shellcheck source=scripts/lib/audio_stack.sh
source "$INSTALL_DIR/scripts/lib/audio_stack.sh"
install_flues_systemd_units "$INSTALL_DIR"
sudo systemctl disable supercollider.service 2>/dev/null || true
sudo systemctl enable pi-flues-synth.service 2>/dev/null || true

export PI_MIDI_BACKEND=flues
if [[ -x "$INSTALL_DIR/scripts/restart_synth_services.sh" ]]; then
  PI_SKIP_DEPLOY_TIMER=1 PI_MIDI_BACKEND=flues "$INSTALL_DIR/scripts/restart_synth_services.sh"
else
  sudo systemctl restart pi-flues-synth.service pi-ambient-synth-midi.service
fi

sleep 2
[[ -x "$INSTALL_DIR/scripts/connect_midi_to_flues.sh" ]] && "$INSTALL_DIR/scripts/connect_midi_to_flues.sh" || true
echo "==> Flues-Synth enabled (KeyStep → Flues directly). SHIFT+PLAY reseed: use monitor Reseed until MIDI bridge is re-enabled."
