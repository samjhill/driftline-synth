#!/usr/bin/env bash
# PiSugar single-tap → queue patch reseed (pi-ambient-synth-midi consumes reseed.request).
set -euo pipefail

MARKER="${PI_AMBIENT_MARKER:-/var/lib/pi-ambient-synth}"
REQUEST="$MARKER/reseed.request"

mkdir -p "$MARKER"
# pisugar-server invokes this as root; MIDI bridge runs as pi.
ts="$(date -Iseconds)"
if [[ "$(id -u)" -eq 0 ]] && command -v runuser &>/dev/null && id pi &>/dev/null; then
  runuser -u pi -- bash -c "echo '$ts' > '$REQUEST'"
elif [[ "$(id -u)" -eq 0 ]] && id pi &>/dev/null; then
  install -o pi -g pi -m 644 /dev/null "$REQUEST" 2>/dev/null || true
  echo "$ts" | tee "$REQUEST" >/dev/null
  chown pi:pi "$REQUEST" 2>/dev/null || true
else
  echo "$ts" >"$REQUEST"
fi

logger -t pi-pisugar-button "queued reseed → $REQUEST" 2>/dev/null || true
