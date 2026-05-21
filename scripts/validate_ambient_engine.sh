#!/usr/bin/env bash
# Validate synth/ambient_engine.scd before deploying to the Pi.
#   ./scripts/validate_ambient_engine.sh          # static checks only (no SuperCollider)
#   ./scripts/validate_ambient_engine.sh --sclang # also run sclang smoke test (needs sclang)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCD="${ROOT}/synth/ambient_engine.scd"
RUN_SCLANG=false
if [[ "${1:-}" == "--sclang" ]]; then
  RUN_SCLANG=true
elif [[ "${1:-}" == "--sclang-mac" ]]; then
  RUN_SCLANG=true
  SCLANG_MAC=1
fi

echo "==> Static checks: $SCD"
python3 "$ROOT/scripts/validate_ambient_engine.py" "$SCD"

if ! $RUN_SCLANG; then
  echo "OK (static). Run with --sclang after: brew install --cask supercollider"
  exit 0
fi

if [[ "$(uname -s)" == "Darwin" && -x "/Applications/SuperCollider.app/Contents/MacOS/sclang" ]]; then
  export PATH="/Applications/SuperCollider.app/Contents/MacOS:$PATH"
fi
if ! command -v sclang &>/dev/null; then
  echo "ERROR: sclang not found. Install SuperCollider, e.g.:" >&2
  echo "  brew install --cask supercollider" >&2
  echo "  sudo apt install supercollider   # Debian/Ubuntu" >&2
  exit 1
fi

# macOS cask has sclang only; s.boot often hangs without the IDE. Use Linux/CI for full smoke test.
if [[ "$(uname -s)" == "Darwin" && "${SCLANG_MAC:-}" != "1" ]]; then
  echo "SKIP: sclang smoke test on macOS (use static checks, or: ./scripts/validate_ambient_engine.sh --sclang-mac)"
  echo "      Full audio smoke test runs in GitHub Actions (ubuntu + apt supercollider)."
  exit 0
fi

echo "==> sclang smoke test (SC_ENGINE_TEST=1, timeout 120s)"

if [[ "$(uname -s)" == "Darwin" ]]; then
  export PATH="/Applications/SuperCollider.app/Contents/MacOS:${PATH}"
  unset QT_QPA_PLATFORM
else
  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
  unset DISPLAY
fi
export SC_ENGINE_TEST=1
export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-}"

SCLANG_BIN="$(command -v sclang)"
LOG="$(mktemp)"
cleanup() { rm -f "$LOG"; }
trap cleanup EXIT

set +e
if command -v timeout &>/dev/null; then
  timeout 120s "$SCLANG_BIN" "$SCD" </dev/null >"$LOG" 2>&1
  status=$?
elif command -v gtimeout &>/dev/null; then
  gtimeout 120s "$SCLANG_BIN" "$SCD" </dev/null >"$LOG" 2>&1
  status=$?
else
  # macOS: perl alarm (no coreutils timeout by default)
  perl -e 'alarm shift; exec @ARGV' 120 "$SCLANG_BIN" "$SCD" </dev/null >"$LOG" 2>&1
  status=$?
fi
set -e

if grep -qE 'ERROR:|Command line parse failed|syntax error' "$LOG"; then
  echo "FAIL: sclang reported errors:" >&2
  tail -40 "$LOG" >&2
  exit 1
fi

if ! grep -q 'Pi Ambient Synth ENGINE_TEST ok' "$LOG"; then
  echo "FAIL: sclang did not reach ENGINE_TEST ok (exit $status):" >&2
  tail -40 "$LOG" >&2
  exit 1
fi

echo "OK (static + sclang smoke test)"
grep -E 'engine script loading|Booting|scsynth running|ENGINE_TEST ok' "$LOG" | tail -8
