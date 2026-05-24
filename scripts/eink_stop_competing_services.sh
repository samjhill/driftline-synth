#!/usr/bin/env bash
# Stop units that race on the e-ink SPI/GPIO (audio still via pi-ambient-synth-midi).
set -euo pipefail
sudo systemctl stop pi-ambient-synth-audio-display.service \
  pi-ambient-synth-boot-display.service \
  pi-ambient-synth-network-announce.service 2>/dev/null || true
sudo systemctl disable pi-ambient-synth-audio-display.service 2>/dev/null || true
rm -f /tmp/pi-ambient-synth-eink.lock
echo "E-ink competitors stopped; lock cleared"
