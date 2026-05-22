# Shared helpers for Pi headphone hardware isolation (ALSA → JACK → SC).
# shellcheck shell=bash

audio_iso_log() { echo "$(date -Iseconds) [audio-iso] $*"; }

audio_iso_stop_project_services() {
  local unit
  for unit in pi-ambient-synth pi-ambient-synth-midi pi-ambient-synth-monitor supercollider; do
    if systemctl is-active --quiet "${unit}.service" 2>/dev/null; then
      if sudo -n systemctl stop "${unit}.service" 2>/dev/null; then
        audio_iso_log "stopped ${unit}.service"
      else
        audio_iso_log "ERROR: cannot stop ${unit}.service (need sudo)"
        return 1
      fi
    fi
  done
  sleep 2
  for unit in supercollider pi-ambient-synth pi-ambient-synth-midi; do
    if systemctl is-active --quiet "${unit}.service" 2>/dev/null; then
      audio_iso_log "ERROR: ${unit}.service still active"
      return 1
    fi
  done
  return 0
}

audio_iso_kill_audio_processes() {
  pkill -x sclang 2>/dev/null || true
  pkill -x scsynth 2>/dev/null || true
  pkill -x jackd 2>/dev/null || true
  pkill -9 -x scsynth 2>/dev/null || true
  pkill -9 -x jackd 2>/dev/null || true
  pkill -9 -x sclang 2>/dev/null || true
  sleep 1
  rm -f /dev/shm/jack-* /dev/shm/jackdmp* /dev/shm/sem.jack* 2>/dev/null || true
}

audio_iso_force_headphone_mixer() {
  if command -v raspi-config >/dev/null 2>&1; then
    sudo raspi-config nonint do_audio 1 2>/dev/null || true
  fi
  amixer -c 0 set PCM 95% unmute 2>/dev/null || true
  amixer -c 0 set Headphone 95% unmute 2>/dev/null || true
  amixer -c 0 scontents 2>/dev/null || true
}

audio_iso_marker_dir() {
  echo "${MARKER_DIR:-/var/lib/pi-ambient-synth}"
}
