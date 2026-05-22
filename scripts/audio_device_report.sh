#!/usr/bin/env bash
# Step 2: enumerate Pi audio devices and routing (read-only).
set -euo pipefail

echo "========== AUDIO_DEVICE_REPORT =========="
echo "date: $(date -Iseconds)"
echo "host: $(hostname 2>/dev/null || echo unknown)"
echo ""

section() { echo ""; echo "----- $* -----"; }

section "aplay -l"
aplay -l 2>&1 || echo "(aplay -l failed)"

section "aplay -L"
aplay -L 2>&1 || echo "(aplay -L failed)"

section "amixer -c 0 scontents"
amixer -c 0 scontents 2>&1 || echo "(amixer failed)"

section "pactl info"
if command -v pactl >/dev/null 2>&1; then
  pactl info 2>&1 || true
else
  echo "pactl not installed"
fi

section "systemctl audio daemons"
for unit in jackd jackd2 pipewire pipewire-pulse pulseaudio; do
  if systemctl list-unit-files "${unit}.service" &>/dev/null 2>&1; then
    systemctl status "${unit}.service" --no-pager 2>&1 | head -8 || true
    echo ""
  fi
done

section "vcgencmd audio"
if command -v vcgencmd >/dev/null 2>&1; then
  vcgencmd get_config int 2>/dev/null | grep -i audio || echo "(no audio keys in config)"
else
  echo "vcgencmd not available"
fi

section "raspi-config audio"
if command -v raspi-config >/dev/null 2>&1; then
  echo -n "get_audio: "
  raspi-config nonint get_audio 2>/dev/null || echo "(unknown)"
else
  echo "raspi-config not available"
fi

section "processes (jack/sc/pulse)"
pgrep -a jackd 2>/dev/null || echo "no jackd"
pgrep -a scsynth 2>/dev/null || echo "no scsynth"
pgrep -a sclang 2>/dev/null || echo "no sclang"
pgrep -a pulseaudio 2>/dev/null || echo "no pulseaudio"
pgrep -a pipewire 2>/dev/null || echo "no pipewire"

section "known-good JACK marker (if Step 3 passed)"
MARKER="/var/lib/pi-ambient-synth/jack-known-good.env"
if [[ -f "$MARKER" ]]; then
  cat "$MARKER"
else
  echo "(not written yet — run jack_headphone_smoke_test.sh after ALSA passes)"
fi

echo ""
echo "========== END AUDIO_DEVICE_REPORT =========="
