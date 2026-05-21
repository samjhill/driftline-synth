#!/usr/bin/env bash
# Enable full SuperCollider ambient engine on Pi headphone jack (native ALSA scsynth).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
CONF="/etc/pi-ambient-synth/audio-mode.conf"
DROPIN_DIR="/etc/systemd/system/pi-ambient-synth-midi.service.d"
DROPIN="$DROPIN_DIR/direct-keys.conf"

sudo mkdir -p /etc/pi-ambient-synth
if [[ -f "$INSTALL_DIR/deploy/pi-audio-mode-ambient.conf" ]]; then
  sudo cp "$INSTALL_DIR/deploy/pi-audio-mode-ambient.conf" "$CONF"
else
  echo "AUDIO_MODE=ambient" | sudo tee "$CONF" >/dev/null
fi

sudo rm -f "$DROPIN" /etc/systemd/system/pi-ambient-synth-midi.service.d/ambient-hybrid.conf 2>/dev/null || true
sudo systemctl stop pi-ambient-alsa-drone.service 2>/dev/null || true
sudo systemctl disable pi-ambient-alsa-drone.service 2>/dev/null || true

# shellcheck source=scripts/lib/audio_stack.sh
source "$INSTALL_DIR/scripts/lib/audio_stack.sh"
install_sc_systemd_units "$INSTALL_DIR"

sudo mkdir -p /etc/systemd/system/supercollider.service.d
sudo tee /etc/systemd/system/supercollider.service.d/audio.conf >/dev/null <<'EOF'
[Service]
LimitMEMLOCK=infinity
Environment=JACK_NO_START_SERVER=1
Environment=JACK_NO_AUDIO_RESERVATION=1
Environment=SC_HEADLESS_ALSA=1
Environment=SC_AUDIO_DEVICE=plughw:0,0
Environment=SC_JACK_DEVICE=plughw:0,0
Environment=SC_JACK_PERIOD=4096
Environment=SC_JACK_NPERIODS=3
Environment=PI_SKIP_TEXTURE_DRONE=1
EOF

sudo cp "$INSTALL_DIR/systemd/pi-ambient-synth-midi.service" /etc/systemd/system/
sudo cp "$INSTALL_DIR/systemd/pi-ambient-synth.service" /etc/systemd/system/ 2>/dev/null || true
sudo mkdir -p /etc/systemd/system/pi-ambient-synth.service.d
sudo rm -f /etc/systemd/system/pi-ambient-synth.service.d/flues.conf 2>/dev/null || true
if [[ -f "$INSTALL_DIR/deploy/systemd/pi-ambient-synth.supercollider.conf" ]]; then
  sudo cp "$INSTALL_DIR/deploy/systemd/pi-ambient-synth.supercollider.conf" \
    /etc/systemd/system/pi-ambient-synth.service.d/supercollider.conf
fi
sudo systemctl enable supercollider.service 2>/dev/null || true
sudo systemctl daemon-reload

echo "==> ambient mode enabled ($CONF); restarting synth stack"
if [[ -x "$INSTALL_DIR/scripts/restart_synth_services.sh" ]]; then
  PI_SKIP_DEPLOY_TIMER=1 "$INSTALL_DIR/scripts/restart_synth_services.sh"
else
  sudo systemctl restart supercollider.service
  sleep 8
  sudo systemctl restart pi-ambient-synth-midi.service pi-ambient-synth-monitor.service 2>/dev/null || true
fi

sleep 2
if [[ -x "$INSTALL_DIR/scripts/prove_ambient_engine_pi.sh" ]]; then
  "$INSTALL_DIR/scripts/prove_ambient_engine_pi.sh" || true
fi
echo "==> KeyStep → OSC → SuperCollider voices (no constant drone, no aplay blips). Play keys on 3.5 mm jack."
