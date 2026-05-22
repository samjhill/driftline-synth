# Shared Pi audio teardown + supercollider unit install (used by verify, deploy, install).
# shellcheck shell=bash

stop_audio_stack() {
  local port="${SC_SYNTH_PORT:-57110}"
  pkill -x scsynth 2>/dev/null || true
  pkill -x jackd 2>/dev/null || true
  pkill -9 -x scsynth 2>/dev/null || true
  pkill -9 -x jackd 2>/dev/null || true
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${port}/udp" 2>/dev/null || true
  fi
  sleep 1.0
  rm -f /dev/shm/jack-* /dev/shm/jackdmp* /dev/shm/sem.jack* 2>/dev/null || true
}

free_alsa() {
  for svc in pipewire pipewire-pulse wireplumber pulseaudio jackd2; do
    sudo systemctl stop "$svc" 2>/dev/null || true
  done
  pkill -x sclang flues-synth 2>/dev/null || true
  stop_audio_stack
  sleep 1.0
}

install_flues_systemd_units() {
  local root="${1:-/home/pi/pi-ambient-synth}"
  if [[ -f "$root/systemd/pi-ambient-synth.service" ]]; then
    sudo cp "$root/systemd/pi-ambient-synth.service" /etc/systemd/system/pi-ambient-synth.service
  fi
  if [[ -f "$root/systemd/pi-flues-synth.service" ]]; then
    sudo cp "$root/systemd/pi-flues-synth.service" /etc/systemd/system/
    sudo systemctl enable pi-flues-synth.service 2>/dev/null || true
  fi
  if [[ -f "$root/systemd/pi-ambient-synth-midi.service" ]]; then
    sudo cp "$root/systemd/pi-ambient-synth-midi.service" /etc/systemd/system/
    sudo systemctl enable pi-ambient-synth-midi.service 2>/dev/null || true
  fi
  sudo mkdir -p /etc/systemd/system/pi-ambient-synth-midi.service.d
  if [[ -f "$root/deploy/systemd/pi-ambient-synth-midi.flues.conf" ]]; then
    sudo cp "$root/deploy/systemd/pi-ambient-synth-midi.flues.conf" \
      /etc/systemd/system/pi-ambient-synth-midi.service.d/flues.conf
  fi
  if [[ -f "$root/deploy/systemd/pi-ambient-synth.flues.conf" ]]; then
    sudo mkdir -p /etc/systemd/system/pi-ambient-synth.service.d
    sudo cp "$root/deploy/systemd/pi-ambient-synth.flues.conf" \
      /etc/systemd/system/pi-ambient-synth.service.d/flues.conf
  fi
  sudo systemctl daemon-reload
}

install_sc_systemd_units() {
  local root="${1:-/home/pi/pi-ambient-synth}"
  sudo cp "$root/systemd/supercollider.service" /etc/systemd/system/supercollider.service
  if [[ -f "$root/systemd/pi-ambient-synth.service" ]]; then
    sudo cp "$root/systemd/pi-ambient-synth.service" /etc/systemd/system/pi-ambient-synth.service
  fi
  if [[ -f "$root/systemd/pi-ambient-synth-midi.service" ]]; then
    sudo cp "$root/systemd/pi-ambient-synth-midi.service" /etc/systemd/system/
    sudo systemctl enable pi-ambient-synth-midi.service 2>/dev/null || true
  fi
  if [[ -f "$root/systemd/pi-ambient-alsa-drone.service" ]]; then
    sudo cp "$root/systemd/pi-ambient-alsa-drone.service" /etc/systemd/system/
  fi
  sudo mkdir -p /etc/systemd/system/supercollider.service.d
  sudo tee /etc/systemd/system/supercollider.service.d/audio.conf >/dev/null <<EOF
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
Environment=PI_SIMPLE_KEYBOARD=1
Environment=PI_NO_STARTUP_CHIME=1
Environment=SC_JACK_DEFAULT_OUTPUTS=system:playback_1,system:playback_2
EOF
  if [[ -f "$root/systemd/pi-ambient-boot-validate.service" ]]; then
    sudo cp "$root/systemd/pi-ambient-boot-validate.service" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable pi-ambient-boot-validate.service 2>/dev/null || true
  fi
  sudo rm -f /etc/systemd/system/pi-ambient-synth.service.d/flues.conf \
    /etc/systemd/system/pi-ambient-synth-midi.service.d/flues.conf 2>/dev/null || true
  sudo systemctl disable pi-flues-synth.service 2>/dev/null || true
  if [[ -f "$root/deploy/systemd/pi-ambient-synth.supercollider.conf" ]]; then
    sudo mkdir -p /etc/systemd/system/pi-ambient-synth.service.d
    sudo cp "$root/deploy/systemd/pi-ambient-synth.supercollider.conf" \
      /etc/systemd/system/pi-ambient-synth.service.d/supercollider.conf
  fi
  sudo systemctl daemon-reload
}
