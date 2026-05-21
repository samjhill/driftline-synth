#!/usr/bin/env bash
# Connect SuperCollider JACK outputs → system playback (Pi headphone jack).
# SC_JACK_DEFAULT_OUTPUTS is not reliable after sclang attach; run after engine boot and periodically.
set -euo pipefail

command -v jack_lsp >/dev/null 2>&1 || exit 0
command -v jack_connect >/dev/null 2>&1 || exit 0
pgrep -x jackd >/dev/null || exit 0
pgrep -x scsynth >/dev/null || exit 0

jack_playback_linked() {
  jack_lsp -c 2>/dev/null | grep -q 'SuperCollider:out_1' \
    && jack_lsp -c 2>/dev/null | grep -A1 '^system:playback_1$' | grep -q 'SuperCollider:out_1'
}

if jack_playback_linked; then
  exit 0
fi

out1="$(jack_lsp 2>/dev/null | grep -E 'SuperCollider:out_1$' | head -1 || true)"
out2="$(jack_lsp 2>/dev/null | grep -E 'SuperCollider:out_2$' | head -1 || true)"
# Standard stereo links
[[ -n "$out1" ]] && jack_connect "$out1" system:playback_1 2>/dev/null || true
[[ -n "$out2" ]] && jack_connect "$out2" system:playback_2 2>/dev/null || true
# Pi mono headphone / TRS wiring: also cross-feed so a dead channel still hears keys.
[[ -n "$out1" ]] && jack_connect "$out1" system:playback_2 2>/dev/null || true
[[ -n "$out2" ]] && jack_connect "$out2" system:playback_1 2>/dev/null || true

if jack_playback_linked; then
  logger -t pi-ambient-jack "Connected SuperCollider:out → system:playback"
  exit 0
fi

logger -t pi-ambient-jack "WARN: JACK playback link missing (no sound to headphones)"
exit 1
