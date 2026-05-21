#!/usr/bin/env bash
# Install Waveshare e-Paper Python lib into vendor/waveshare (required for e-ink).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/vendor/waveshare"
LIB_REL="RaspberryPi_JetsonNano/python/lib"
REPO="${WAVESHARE_REPO:-https://github.com/waveshare/e-Paper.git}"

if [[ -f "$TARGET/waveshare_epd/epd2in13_V4.py" ]]; then
  exit 0
fi

mkdir -p "$ROOT/vendor"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "==> Fetching Waveshare e-Paper driver..."
if command -v git &>/dev/null; then
  git clone --depth 1 "$REPO" "$tmpdir/e-Paper"
elif command -v curl &>/dev/null; then
  curl -fsSL "${REPO%.git}/archive/refs/heads/master.tar.gz" | tar -xz -C "$tmpdir"
  mv "$tmpdir"/e-Paper-* "$tmpdir/e-Paper"
else
  echo "ERROR: need git or curl to fetch Waveshare driver" >&2
  exit 1
fi

if [[ ! -d "$tmpdir/e-Paper/$LIB_REL/waveshare_epd" ]]; then
  echo "ERROR: unexpected e-Paper layout (missing $LIB_REL)" >&2
  exit 1
fi

rm -rf "$TARGET"
cp -a "$tmpdir/e-Paper/$LIB_REL" "$TARGET"
echo "==> Waveshare driver ready at $TARGET"
