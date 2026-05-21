#!/usr/bin/env bash
# Install Flues-Synth binary for Raspberry Pi (aarch64 prebuilt or local build).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
BIN_DIR="$INSTALL_DIR/bin"
FLUES_BIN="$BIN_DIR/flues-synth"
VERSION="${FLUES_VERSION:-v0.1.0}"
ARCH="$(uname -m)"
TARBALL="flues-synth-${VERSION}-aarch64.tar.gz"
URL="https://github.com/danja/flues/releases/download/${VERSION}/${TARBALL}"

log() { echo "$(date -Iseconds) [install-flues] $*"; }

mkdir -p "$BIN_DIR"

if [[ -x "$FLUES_BIN" ]]; then
  log "already installed: $FLUES_BIN"
  exit 0
fi

if [[ "$ARCH" != "aarch64" ]]; then
  log "WARN: not aarch64 ($ARCH) — skip prebuilt; build on Pi or copy binary to $FLUES_BIN"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
log "download $URL"
curl -fsSL "$URL" -o "$TMP/$TARBALL"
tar -xzf "$TMP/$TARBALL" -C "$TMP"
# Release layout: flues-synth/flues-synth or builddir/flues-synth
SRC="$(find "$TMP" -type f -name flues-synth -perm -111 2>/dev/null | head -1)"
[[ -n "$SRC" ]] || { log "FAIL: flues-synth binary not in tarball"; exit 1; }
install -m 755 "$SRC" "$FLUES_BIN"
log "installed $FLUES_BIN"
