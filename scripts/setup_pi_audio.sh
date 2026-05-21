#!/usr/bin/env bash
# Pi headphone jack: ALSA default, unmute, stop JACK/Pulse grabbing the card.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CARD="${ALSA_CARD:-0}"
ALSA_DEV="${ALSA_DEV:-plughw:0,0}"

echo "==> Pi audio setup (headphone / analog jack)"

if command -v raspi-config &>/dev/null; then
  echo "    Forcing analog headphone jack (raspi-config)"
  sudo raspi-config nonint do_audio 1 2>/dev/null || true
fi

# Headless Pi: PulseAudio/PipeWire "default" often fails with error -524.
for svc in pipewire pipewire-pulse wireplumber pulseaudio; do
  if systemctl is-active "$svc" &>/dev/null; then
    echo "    Stopping $svc (use direct ALSA for SuperCollider)"
    sudo systemctl stop "$svc" 2>/dev/null || true
    sudo systemctl disable "$svc" 2>/dev/null || true
  fi
done

if systemctl is-active jackd2 &>/dev/null; then
  echo "    Stopping jackd2"
  sudo systemctl stop jackd2 2>/dev/null || true
fi
sudo systemctl disable jackd2 2>/dev/null || true

if [[ -f "$ROOT/deploy/asound.conf.pi-headphones" ]]; then
  echo "    Installing /etc/asound.conf (default -> hw:0,0 headphones)"
  sudo cp "$ROOT/deploy/asound.conf.pi-headphones" /etc/asound.conf
else
  sudo tee /etc/asound.conf >/dev/null <<'EOF'
pcm.!default {
    type plug
    slave.pcm "hw:0,0"
}
ctl.!default {
    type hw
    card 0
}
EOF
fi

for ctrl in PCM Master Headphone Speaker Playback; do
  sudo amixer -c "$CARD" sset "$ctrl" unmute 2>/dev/null || true
done
sudo amixer -c "$CARD" sset PCM 90% 2>/dev/null || true
sudo amixer -c "$CARD" sset Headphone 90% 2>/dev/null || true

echo "==> Playback devices (aplay -l):"
aplay -l 2>/dev/null || true
echo "==> ALSA default (aplay -L, first lines):"
aplay -L 2>/dev/null | head -15 || true

if systemctl is-active supercollider.service &>/dev/null; then
  echo "    Stopping supercollider for speaker-test (frees ALSA device)"
  sudo systemctl stop supercollider.service 2>/dev/null || true
fi

CHILL_TEST="$ROOT/scripts/play_headphone_test.py"
echo "==> Headphone playback test on $ALSA_DEV (gentle stereo pan tone, ~6 s)"
if [[ -f "$CHILL_TEST" ]]; then
  if python3 "$CHILL_TEST" -D "$ALSA_DEV" -r 44100 -d 6; then
    :
  else
    echo "    WARN: chill test failed — falling back to speaker-test pink noise"
    speaker-test -D "$ALSA_DEV" -r 44100 -t pink -c 2 -l 1 || true
  fi
else
  echo "    (play_headphone_test.py missing — using speaker-test pink noise)"
  speaker-test -D "$ALSA_DEV" -r 44100 -t pink -c 2 -l 1 || true
fi

echo ""
echo "SuperCollider should use: SC_AUDIO_DEVICE=$ALSA_DEV"
echo "  sudo systemctl restart supercollider pi-ambient-synth"
