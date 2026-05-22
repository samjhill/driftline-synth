#!/usr/bin/env bash
# Route KeyStep only through pi-ambient-synth-midi → Flues-Synth.
# Flues auto-connects to KeyStep (MPE ch 15); disconnect so bridge notes use ch 1.
set -euo pipefail

log() { echo "$(date -Iseconds) [aconnect-flues] $*"; }

command -v aconnect >/dev/null || { log "SKIP: aconnect missing"; exit 0; }
pgrep -x flues-synth >/dev/null || { log "SKIP: flues-synth not running"; exit 0; }

list="$(aconnect -l 2>/dev/null || true)"
if [[ -z "$list" ]]; then
  log "WARN: aconnect -l empty"
  exit 0
fi

dst="$(printf '%s\n' "$list" | awk '
  /client [0-9]+:.*[Ff]lues/ { client=$2; gsub(":", "", client); print client ":0"; exit }
')"
bridge="$(printf '%s\n' "$list" | awk '
  /client [0-9]+:.*RtMidiOut/ { client=$2; gsub(":", "", client); print client ":0"; exit }
')"
keystep="$(printf '%s\n' "$list" | awk '
  /client [0-9]+:.*[Kk]ey[Ss]tep/ { client=$2; gsub(":", "", client); print client ":0"; exit }
')"

if [[ -z "$dst" ]]; then
  log "WARN: Flues MIDI In not found"
  printf '%s\n' "$list" | head -25 || true
  exit 0
fi

# Flues subscribes directly to KeyStep (bypasses bridge channel remap). Disconnect it.
if [[ -n "$keystep" && "$keystep" != "$dst" ]]; then
  if aconnect -d "$keystep" "$dst" 2>/dev/null; then
    log "disconnected KeyStep $keystep → Flues $dst (use bridge path only)"
  fi
fi

if [[ -z "$bridge" ]]; then
  log "bridge uses Flues MIDI In directly (no RtMidiOut yet)"
  exit 0
fi

# Disconnect anything except the bridge from Flues (Midi Through, etc.).
while IFS= read -r src; do
  [[ -z "$src" || "$src" == "$bridge" ]] && continue
  if aconnect -d "$src" "$dst" 2>/dev/null; then
    log "disconnected $src → $dst"
  fi
done < <(
  printf '%s\n' "$list" | awk -v dst="$dst" -v bridge="$bridge" '
    $0 ~ /^[[:space:]]*Connected From:/ {
      for (i = 3; i <= NF; i++) {
        gsub(/,/, "", $i)
        if ($i ~ /^[0-9]+:0$/ && $i != dst && $i != bridge) print $i
      }
    }
  '
)

connected=0
for _ in 1 2 3 4 5; do
  list="$(aconnect -l 2>/dev/null || true)"
  if printf '%s\n' "$list" | grep -qE "(Connecting To:|Connected From:).*${dst}" \
    && printf '%s\n' "$list" | awk -v b="$bridge" -v d="$dst" '
      $0 ~ b { show=1 }
      show && ($0 ~ "Connecting To:" || $0 ~ "Connected From:") && $0 ~ d { found=1 }
      END { exit found ? 0 : 1 }
    '; then
    log "already connected $bridge → $dst"
    connected=1
    break
  fi
  if aconnect "$bridge" "$dst" 2>/dev/null; then
    log "connected $bridge → $dst"
    connected=1
    break
  fi
  sleep 0.6
done
if [[ "$connected" -ne 1 ]]; then
  log "WARN: could not connect $bridge → $dst (bridge may write Flues MIDI In via mido)"
fi
