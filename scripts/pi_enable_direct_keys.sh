#!/usr/bin/env bash
# Enable reliable KeyStep → headphone audio on Pi (direct ALSA, no JACK).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
CONF="/etc/pi-ambient-synth/audio-mode.conf"

sudo mkdir -p /etc/pi-ambient-synth
if [[ -f "$INSTALL_DIR/deploy/pi-audio-mode.conf" ]]; then
  sudo cp "$INSTALL_DIR/deploy/pi-audio-mode.conf" "$CONF"
else
  echo "AUDIO_MODE=direct_keys" | sudo tee "$CONF" >/dev/null
fi

echo "==> direct_keys mode enabled ($CONF)"
echo "==> stopping SuperCollider/JACK (frees headphone jack for aplay)"
sudo systemctl stop supercollider.service pi-ambient-synth.service 2>/dev/null || true
pkill -x jackd scsynth sclang 2>/dev/null || true
sleep 1

sudo cp "$INSTALL_DIR/systemd/pi-ambient-synth-midi.service" /etc/systemd/system/ 2>/dev/null || true
sudo mkdir -p /etc/systemd/system/pi-ambient-synth-midi.service.d
if [[ -f "$INSTALL_DIR/deploy/systemd/pi-ambient-synth-midi.direct-keys.conf" ]]; then
  sudo cp "$INSTALL_DIR/deploy/systemd/pi-ambient-synth-midi.direct-keys.conf" \
    /etc/systemd/system/pi-ambient-synth-midi.service.d/direct-keys.conf
else
  echo "WARN: missing deploy/systemd/pi-ambient-synth-midi.direct-keys.conf" >&2
fi
sudo systemctl daemon-reload
sudo systemctl enable pi-ambient-synth-midi.service pi-ambient-synth-monitor.service
sudo systemctl restart pi-ambient-synth-midi.service pi-ambient-synth-monitor.service

sleep 2
systemctl is-active pi-ambient-synth-midi.service
cat /var/lib/pi-ambient-synth/midi-status.json 2>/dev/null || true
echo "==> Play KeyStep keys now (USB to Pi, 3.5 mm jack)."
