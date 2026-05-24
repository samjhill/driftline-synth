#!/usr/bin/env bash
# Pre-download Pi (linux arm64) Python wheels on Mac — copied to SD for fast offline pip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHEELS="$ROOT/vendor/wheels"
STAMP="$WHEELS/.bundle_stamp"
PYVER="${PI_PYTHON_VERSION:-3.11}"
PIWHEELS="https://www.piwheels.org/simple"
PLATFORM="${PI_WHEEL_PLATFORM:-manylinux_2_17_aarch64}"

PIP=""
for c in pip3.11 pip3; do
  if command -v "$c" >/dev/null; then
    PIP="$c"
    break
  fi
done
[[ -n "$PIP" ]] || { echo "ERROR: pip3.11 or pip3 required (brew install python@3.11)"; exit 1; }

if [[ -f "$STAMP" ]] && [[ "${FORCE_BUNDLE:-0}" != "1" ]]; then
  echo "==> Wheels already bundled ($(head -1 "$STAMP")) — FORCE_BUNDLE=1 to refresh"
  exit 0
fi

echo "==> Downloading linux/arm64 wheels with $PIP (Python ${PYVER})..."
rm -rf "$WHEELS"
mkdir -p "$WHEELS"

V1_BUNDLE=0
if [[ "${BUNDLE_V1:-0}" == "1" ]] || [[ "${FACTORY_SD:-0}" == "1" ]] || [[ "${DEFAULT_AUDIO_MODE:-}" == "fluidsynth" ]]; then
  V1_BUNDLE=1
fi

# Pure-python (architecture-independent).
if [[ "$V1_BUNDLE" == "1" ]]; then
  "$PIP" download mido python-osc PyYAML gpiozero packaging setuptools \
    -d "$WHEELS" --extra-index-url "$PIWHEELS"
else
  "$PIP" download mido python-osc PyYAML gpiozero colorzero packaging setuptools \
    -d "$WHEELS" --extra-index-url "$PIWHEELS"
fi

# Binary packages for Raspberry Pi OS 64-bit (Bookworm / Python 3.11).
if [[ "$V1_BUNDLE" == "1" ]]; then
  aarch64_pkgs=(Pillow python-rtmidi spidev RPi.GPIO)
else
  aarch64_pkgs=(numpy Pillow PyYAML python-rtmidi spidev RPi.GPIO)
fi
for pkg in "${aarch64_pkgs[@]}"; do
  echo "    $pkg ..."
  "$PIP" download "$pkg" -d "$WHEELS" \
    --extra-index-url "$PIWHEELS" \
    --platform "$PLATFORM" \
    --python-version "$PYVER" \
    --only-binary=:all: \
    --no-deps 2>/dev/null || \
  "$PIP" download "$pkg" -d "$WHEELS" \
    --extra-index-url "$PIWHEELS" \
    --platform "$PLATFORM" \
    --python-version "$PYVER" \
    --no-deps 2>/dev/null || \
  echo "    WARN: no wheel for $pkg (Pi may build from source)"
done

# Drop any macOS/Windows wheels accidentally fetched.
find "$WHEELS" -maxdepth 1 \( -name '*macosx*' -o -name '*win_*' -o -name '*win32*' \) -delete 2>/dev/null || true

count="$(find "$WHEELS" -maxdepth 1 -name '*.whl' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$count" -lt 6 ]]; then
  echo "ERROR: Too few linux wheels ($count). Try: brew install python@3.11 && FORCE_BUNDLE=1 $0"
  exit 1
fi

date -Iseconds > "$STAMP"
echo "${PLATFORM} py${PYVER} wheels=${count}" >> "$STAMP"
echo "==> Saved $count wheels to vendor/wheels ($(du -sh "$WHEELS" | cut -f1))"
echo "    Pi first-boot: pip install --no-index from vendor/wheels (skips PyPI)"
