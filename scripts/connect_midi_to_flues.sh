#!/usr/bin/env bash
# Link KeyStep (via pi-ambient-synth-midi rtmidi port) → Flues-Synth ALSA MIDI input.
set -euo pipefail

log() { echo "$(date -Iseconds) [aconnect-flues] $*"; }

command -v aconnect >/dev/null || { log "SKIP: aconnect missing"; exit 0; }
pgrep -x flues-synth >/dev/null || { log "SKIP: flues-synth not running"; exit 0; }

# Prefer KeyStep / bridge client as source; Flues as destination.
src="$(aconnect -l 2>/dev/null | awk '
  /client [0-9]+:.*(KeyStep|Ambient|rtmidi|Midi Through)/ { client=$2; gsub(":", "", client); port=client; in_client=1; next }
  in_client && /0 / { print client ":0"; in_client=0 }
' | head -1)"
dst="$(aconnect -l 2>/dev/null | awk '
  /client [0-9]+:.*[Ff]lues/ { client=$2; gsub(":", "", client); print client ":0"; exit }
')"

if [[ -z "$dst" ]]; then
  dst="$(aconnect -l 2>/dev/null | grep -i flues | head -1 | sed -n 's/.*\([0-9][0-9]*\):.*/\1:0/p')"
fi

if [[ -z "$src" || -z "$dst" ]]; then
  log "WARN: could not find MIDI ports (src=${src:-?} dst=${dst:-?})"
  aconnect -l 2>/dev/null | head -30 || true
  exit 0
fi

if aconnect -l 2>/dev/null | grep -q "${src}.*${dst}"; then
  log "already connected $src → $dst"
  exit 0
fi

aconnect "$src" "$dst" 2>/dev/null && log "connected $src → $dst" || log "WARN: aconnect failed $src → $dst"
