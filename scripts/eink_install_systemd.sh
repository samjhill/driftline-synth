#!/usr/bin/env bash
# Enable single e-ink service; mask legacy display units that raced on GPIO.
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"

legacy=(
  pi-ambient-synth-eink-prepare.service
  pi-ambient-synth-eink-boot.service
  pi-ambient-synth-boot-display.service
  pi-ambient-synth-network-announce.service
  pi-ambient-synth-eink-patch.service
  pi-ambient-synth-audio-display.service
)

for u in "${legacy[@]}"; do
  sudo systemctl stop "$u" 2>/dev/null || true
  sudo systemctl disable "$u" 2>/dev/null || true
  sudo systemctl mask "$u" 2>/dev/null || true
done

sudo cp "$ROOT/systemd/pi-ambient-synth-eink.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable pi-ambient-synth-eink.service
sudo systemctl restart pi-ambient-synth-eink.service 2>/dev/null || \
  sudo systemctl start pi-ambient-synth-eink.service 2>/dev/null || true

echo "E-ink: pi-ambient-synth-eink.service enabled; legacy display units masked."
