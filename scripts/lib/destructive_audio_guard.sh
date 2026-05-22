# shellcheck shell=bash
# Refuse scripts that stop production synth services unless explicitly opted in.

require_destructive_audio_test() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--destructive-audio-test" ]]; then
      return 0
    fi
  done
  echo "REFUSED: this script stops supercollider/pi-ambient-synth for ALSA/speaker-test." >&2
  echo "  It is not safe for normal monitor or KeyStep operation." >&2
  echo "  To run anyway: $0 --destructive-audio-test" >&2
  exit 1
}
