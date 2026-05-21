#!/usr/bin/env bash
# Pi headphone jack: unmute ALSA, prefer analog out, stop JACK grabbing the card.
set -euo pipefail

echo "==> Pi audio setup (headphone / analog jack)"

if command -v raspi-config &>/dev/null; then
  echo "    Forcing analog headphone jack (raspi-config)"
  sudo raspi-config nonint do_audio 1 2>/dev/null || true
fi

# Stop JACK so SuperCollider can use ALSA directly (see supercollider.service env).
if systemctl is-active jackd2 &>/dev/null; then
  echo "    Stopping jackd2 (conflicts with headless SuperCollider)"
  sudo systemctl stop jackd2 2>/dev/null || true
fi
sudo systemctl disable jackd2 2>/dev/null || true

CARD="${ALSA_CARD:-0}"
for ctrl in PCM Master Headphone Speaker Playback; do
  sudo amixer -c "$CARD" sset "$ctrl" unmute 2>/dev/null || true
done
sudo amixer -c "$CARD" sset PCM 90% 2>/dev/null || true
sudo amixer -c "$CARD" sset Headphone 90% 2>/dev/null || true

echo "==> Playback devices (aplay -l):"
aplay -l 2>/dev/null || true

echo ""
echo "Quick test (you should hear pink noise ~3s on the headphone jack):"
echo "  speaker-test -t wav -c 2 -l 1"
echo ""
echo "If that works but the synth is silent, restart SuperCollider:"
echo "  sudo systemctl restart supercollider pi-ambient-synth"
