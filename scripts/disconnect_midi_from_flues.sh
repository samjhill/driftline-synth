#!/usr/bin/env bash
# Ambient mode: ensure KeyStep is not wired directly to Flues (only bridge → OSC).
set -euo pipefail

log() { echo "$(date -Iseconds) [aconnect-ambient] $*"; }

command -v aconnect >/dev/null || { log "SKIP: aconnect missing"; exit 0; }

list="$(aconnect -l 2>/dev/null || true)"
[[ -n "$list" ]] || { log "SKIP: aconnect -l empty"; exit 0; }

flues="$(printf '%s\n' "$list" | awk '
  /client [0-9]+:.*[Ff]lues/ { client=$2; gsub(":", "", client); print client ":0"; exit }
')"
keystep="$(printf '%s\n' "$list" | awk '
  /client [0-9]+:.*[Kk]ey[Ss]tep/ { client=$2; gsub(":", "", client); print client ":0"; exit }
')"

if pgrep -x flues-synth >/dev/null 2>&1; then
  pkill -x flues-synth 2>/dev/null || true
  sleep 0.3
  log "stopped flues-synth (must not hold plughw:0,0 with jackd)"
fi

if [[ -z "$flues" ]]; then
  exit 0
fi

if [[ -n "$keystep" ]]; then
  if aconnect -d "$keystep" "$flues" 2>/dev/null; then
    log "disconnected KeyStep $keystep → Flues $flues"
  fi
fi

while IFS= read -r src; do
  [[ -z "$src" || "$src" == "$flues" ]] && continue
  if aconnect -d "$src" "$flues" 2>/dev/null; then
    log "disconnected $src → Flues $flues"
  fi
done < <(
  printf '%s\n' "$list" | awk -v dst="$flues" '
    $0 ~ /^[[:space:]]*Connected From:/ {
      for (i = 3; i <= NF; i++) {
        gsub(/,/, "", $i)
        if ($i ~ /^[0-9]+:0$/ && $i != dst) print $i
      }
    }
  '
)
