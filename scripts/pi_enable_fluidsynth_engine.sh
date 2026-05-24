#!/usr/bin/env bash
# V1: KeyStep → pi_midi_bridge → FluidSynth → ALSA plughw:0,0 (no JACK, no SuperCollider).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
CONF="/etc/pi-ambient-synth/audio-mode.conf"

echo "==> install FluidSynth + GM soundfont"
sudo apt-get update -qq
sudo apt-get install -y fluidsynth fluid-soundfont-gm libfluidsynth3 || true
sudo apt-get install -y fluidsynth fluid-soundfont-gm 2>/dev/null || true

if ! command -v fluidsynth >/dev/null; then
  echo "ERROR: fluidsynth not installed" >&2
  exit 1
fi

sudo mkdir -p /etc/pi-ambient-synth
if [[ -f "$INSTALL_DIR/deploy/pi-audio-mode-fluidsynth.conf" ]]; then
  sudo cp "$INSTALL_DIR/deploy/pi-audio-mode-fluidsynth.conf" "$CONF"
else
  echo "AUDIO_MODE=fluidsynth" | sudo tee "$CONF" >/dev/null
fi

echo "==> stop SuperCollider / JACK / Flues"
sudo systemctl stop supercollider.service pi-ambient-synth.service pi-flues-synth.service \
  pi-ambient-alsa-drone.service pi-ambient-synth-midi.service 2>/dev/null || true
sudo systemctl disable supercollider.service pi-flues-synth.service pi-ambient-alsa-drone.service 2>/dev/null || true
sudo systemctl disable pi-ambient-synth-audio-display.service 2>/dev/null || true
sudo systemctl stop pi-ambient-synth-audio-display.service 2>/dev/null || true
sudo systemctl mask supercollider.service 2>/dev/null || true
sudo systemctl disable --now pi-ambient-jack-playback.timer pi-ambient-jack-playback.service 2>/dev/null || true
sudo systemctl disable pi-ambient-boot-validate.service 2>/dev/null || true
pkill -9 -x jackd scsynth sclang fluidsynth 2>/dev/null || true
sleep 1

sudo cp "$INSTALL_DIR/systemd/pi-ambient-synth-midi.service" /etc/systemd/system/ 2>/dev/null || true
sudo cp "$INSTALL_DIR/systemd/pi-ambient-synth.service" /etc/systemd/system/ 2>/dev/null || true
sudo mkdir -p /etc/systemd/system/pi-ambient-synth-midi.service.d \
  /etc/systemd/system/pi-ambient-synth.service.d
sudo rm -f /etc/systemd/system/pi-ambient-synth-midi.service.d/direct-keys.conf \
  /etc/systemd/system/pi-ambient-synth-midi.service.d/ambient-hybrid.conf \
  /etc/systemd/system/pi-ambient-synth-midi.service.d/flues.conf \
  /etc/systemd/system/pi-ambient-synth.service.d/flues.conf \
  /etc/systemd/system/pi-ambient-synth.service.d/supercollider.conf 2>/dev/null || true
if [[ -f "$INSTALL_DIR/deploy/systemd/pi-ambient-synth-midi.fluidsynth.conf" ]]; then
  sudo cp "$INSTALL_DIR/deploy/systemd/pi-ambient-synth-midi.fluidsynth.conf" \
    /etc/systemd/system/pi-ambient-synth-midi.service.d/fluidsynth.conf
fi
if [[ -f "$INSTALL_DIR/deploy/systemd/pi-ambient-synth.fluidsynth.conf" ]]; then
  sudo cp "$INSTALL_DIR/deploy/systemd/pi-ambient-synth.fluidsynth.conf" \
    /etc/systemd/system/pi-ambient-synth.service.d/fluidsynth.conf
fi

sudo systemctl daemon-reload
sudo systemctl enable pi-ambient-synth-midi.service pi-ambient-synth-monitor.service pi-ambient-synth.service
if [[ -x "$INSTALL_DIR/scripts/eink_install_systemd.sh" ]]; then
  bash "$INSTALL_DIR/scripts/eink_install_systemd.sh"
fi
sudo systemctl restart pi-ambient-synth.service pi-ambient-synth-midi.service pi-ambient-synth-monitor.service

sleep 2
systemctl is-active pi-ambient-synth-midi.service pi-ambient-synth.service
echo ""
echo "AUDIO_MODE=fluidsynth enabled."
echo "Prove audio first: INSTALL_DIR=$INSTALL_DIR $INSTALL_DIR/scripts/fluidsynth_headphone_demo.sh"
echo "Then play KeyStep — reseed changes GM program; e-ink updates on reseed only."
