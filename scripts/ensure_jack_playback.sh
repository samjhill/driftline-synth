#!/usr/bin/env bash
# Connect SuperCollider JACK outputs → system playback (Pi 3.5 mm jack).
# Retries until scsynth ports are visible and linked (no stale success markers).
set -euo pipefail

MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
LINKED_MARKER="$MARKER_DIR/jack-playback-linked"
RETRY_SEC="${JACK_CONNECT_RETRY_SEC:-10}"
LOG_TAG="pi-ambient-jack"

log() { echo "$(date -Iseconds) [$LOG_TAG] $*"; }

command -v jack_lsp >/dev/null 2>&1 || { log "FAIL: jack_lsp missing"; exit 1; }
command -v jack_connect >/dev/null 2>&1 || { log "FAIL: jack_connect missing"; exit 1; }
pgrep -x jackd >/dev/null || { log "FAIL: jackd not running"; exit 1; }
pgrep -x scsynth >/dev/null || { log "FAIL: scsynth not running"; exit 1; }

rm -f "$LINKED_MARKER" 2>/dev/null || true

# Inherit jackd's session (SSH/timer clients cannot see the server otherwise).
_jpid="$(pgrep -x jackd 2>/dev/null | head -1 || true)"
if [[ -n "$_jpid" ]] && [[ -r "/proc/$_jpid/environ" ]]; then
  while IFS= read -r -d '' _e; do
    case "$_e" in
      JACK_*|DBUS_*|XDG_RUNTIME_DIR=*|HOME=*|USER=*|TMPDIR=*)
        export "$_e"
        ;;
    esac
  done <"/proc/$_jpid/environ"
fi
unset _jpid _e

jack_playback_linked() {
  jack_lsp -c 2>/dev/null | grep -q 'SuperCollider:out_1' \
    && jack_lsp -c 2>/dev/null | grep -A1 '^system:playback_1$' | grep -q 'SuperCollider:out_1'
}

deadline=$((SECONDS + RETRY_SEC))
out1="" out2=""
while (( SECONDS < deadline )); do
  out1="$(jack_lsp 2>/dev/null | grep -E 'SuperCollider:out_1$' | head -1 || true)"
  out2="$(jack_lsp 2>/dev/null | grep -E 'SuperCollider:out_2$' | head -1 || true)"
  if [[ -n "$out1" ]]; then
    break
  fi
  sleep 0.25
done

if [[ -z "$out1" ]]; then
  log "FAIL: SuperCollider JACK output ports not visible after ${RETRY_SEC}s"
  log "jack_lsp ports:"
  jack_lsp 2>&1 | head -30 || true
  exit 1
fi

if jack_playback_linked; then
  mkdir -p "$MARKER_DIR"
  date -Iseconds >"$LINKED_MARKER"
  log "OK: playback already linked"
  jack_lsp -c 2>/dev/null | grep -E 'SuperCollider|playback' | head -12 || true
  exit 0
fi

[[ -n "$out1" ]] && jack_connect "$out1" system:playback_1 2>/dev/null || true
[[ -n "$out2" ]] && jack_connect "$out2" system:playback_2 2>/dev/null || true
[[ -n "$out1" ]] && jack_connect "$out1" system:playback_2 2>/dev/null || true
[[ -n "$out2" ]] && jack_connect "$out2" system:playback_1 2>/dev/null || true

sleep 0.2
if jack_playback_linked; then
  mkdir -p "$MARKER_DIR"
  date -Iseconds >"$LINKED_MARKER"
  log "OK: connected SuperCollider:out → system:playback"
  log "jack_lsp -c (playback):"
  jack_lsp -c 2>/dev/null | grep -E 'SuperCollider|playback' | head -14 || true
  exit 0
fi

log "FAIL: could not link SuperCollider:out to system:playback"
log "jack_lsp -c:"
jack_lsp -c 2>&1 | head -30 || true
exit 1
