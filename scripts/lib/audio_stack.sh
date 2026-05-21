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
  pkill -x sclang 2>/dev/null || true
  stop_audio_stack
  sleep 1.0
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
Environment=SC_SCLANG_OWNS_AUDIO=1
Environment=SC_AUDIO_DEVICE=plughw:0,0
Environment=PI_SKIP_TEXTURE_DRONE=1
EOF
  sudo systemctl daemon-reload
}
