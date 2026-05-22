#!/usr/bin/env bash
# Headless SuperCollider engine for systemd (no X11 / Qt xcb).
set -euo pipefail

ROOT="${PI_AMBIENT_ROOT:-/home/pi/pi-ambient-synth}"
# V1 default: minimal warm-pad engine. Set PI_LEGACY_ENGINE=1 for ambient_engine.scd.
if [[ "${PI_LEGACY_ENGINE:-}" == "1" ]]; then
  SCD="${ROOT}/synth/ambient_engine.scd"
else
  SCD="${ROOT}/synth/minimal_ambient_engine.scd"
fi
READY_MARKER="${PI_SC_READY_MARKER:-/var/lib/pi-ambient-synth/sc-engine-ready}"
JACK_LINKED_MARKER="${PI_JACK_LINKED_MARKER:-/var/lib/pi-ambient-synth/jack-playback-linked}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"

export HOME="${HOME:-/home/pi}"
export QT_QPA_PLATFORM=offscreen
unset DISPLAY
export SC_JACK_DEFAULT_INPUTS="${SC_JACK_DEFAULT_INPUTS:-}"
export SC_JACK_DEFAULT_OUTPUTS="${SC_JACK_DEFAULT_OUTPUTS:-system:playback_1,system:playback_2}"
# External jackd from start_scsynth_alsa.sh; do not let scsynth spawn jackdmp.
export JACK_NO_AUDIO_RESERVATION="${JACK_NO_AUDIO_RESERVATION:-1}"
export JACK_NO_START_SERVER="${JACK_NO_START_SERVER:-1}"
# ALSA device name from `aplay -L` (e.g. plughw:0,0). Empty makes scsynth try JACK.
export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-plughw:0,0}"
export SC_HEADLESS_ALSA="${SC_HEADLESS_ALSA:-1}"
export PI_NO_STARTUP_CHIME="${PI_NO_STARTUP_CHIME:-1}"
rm -f "$READY_MARKER" "$JACK_LINKED_MARKER" 2>/dev/null || true
pkill -x sclang 2>/dev/null || true
sleep 0.5
"$ROOT/scripts/start_scsynth_alsa.sh" || exit 1
# Inline JACK link only (no ensure_jack_playback.sh loop in minimal path).
link_jack_playback() {
  local out1 out2
  command -v jack_connect >/dev/null || return 0
  out1="$(jack_lsp 2>/dev/null | grep -E 'SuperCollider:out_1$' | head -1 || true)"
  out2="$(jack_lsp 2>/dev/null | grep -E 'SuperCollider:out_2$' | head -1 || true)"
  [[ -n "$out1" ]] && jack_connect "$out1" system:playback_1 2>/dev/null || true
  [[ -n "$out1" ]] && jack_connect "$out1" system:playback_2 2>/dev/null || true
  [[ -n "$out2" ]] && jack_connect "$out2" system:playback_2 2>/dev/null || true
}
link_jack_playback || true
if [[ "${PI_LEGACY_ENGINE:-}" == "1" ]] && [[ -x "$ROOT/scripts/ensure_jack_playback.sh" ]]; then
  JACK_CONNECT_RETRY_SEC=12 "$ROOT/scripts/ensure_jack_playback.sh" || true
  (
    for delay in 8 15 22 30 40 55 75; do
      sleep "$delay"
      "$ROOT/scripts/ensure_jack_playback.sh" || true
    done
    while true; do
      sleep 25
      "$ROOT/scripts/ensure_jack_playback.sh" || true
    done
  ) &
fi

# Run script as argument (-l is for libraries, not .scd files; breaks headless systemd).
# Line-buffered stdout so systemd journal shows Booting/scsynth lines promptly.
exec stdbuf -oL -eL /usr/bin/sclang -l "$ROOT/synth/pi_bind_port.scd" "$SCD" </dev/null
