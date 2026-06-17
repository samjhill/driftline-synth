#!/usr/bin/env python3
"""Show LAN IP on e-ink and write network-address files."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _src_dir() -> Path:
    for candidate in (
        Path(__file__).resolve().parent.parent / "src",
        Path("/home/pi/pi-ambient-synth/src"),
    ):
        if candidate.is_dir():
            return candidate
    return Path(__file__).resolve().parent.parent / "src"


sys.path.insert(0, str(_src_dir()))

from config_loader import load_config
from eink_display import EInkDisplay
from network_info import network_snapshot, save_network_info
from status_display import StatusDisplay


def find_boot_log_dir() -> Path | None:
    for base in (
        Path("/boot/firmware/pi-ambient-synth"),
        Path("/boot/pi-ambient-synth"),
    ):
        if base.is_dir():
            return base / "boot-logs"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Announce Pi network address")
    parser.add_argument("--config", type=Path, default=None)
    parser.add_argument("--no-eink", action="store_true")
    args = parser.parse_args()

    config = load_config(args.config)
    monitor = config.get("monitor", {})
    port = int(monitor.get("port", 8080))
    snap = network_snapshot(monitor_port=port)

    marker = Path(config.get("app", {}).get("marker_dir", "/var/lib/pi-ambient-synth"))
    save_network_info(snap, marker_dir=marker, boot_log_dir=find_boot_log_dir())

    ip = snap.get("primary_ip") or "no IP yet"
    host = snap.get("hostname", "pi")
    url = snap.get("monitor_url") or f"port {port}"
    print(f"Network: {ip}  ({host}.local)  monitor {url}")

    if args.no_eink or not config.get("eink", {}).get("enabled", True):
        return 0

    display = EInkDisplay(config)
    if not display.init():
        return 0

    renderer = StatusDisplay(config)
    detail = url.replace("http://", "")[:28]
    img = renderer.render("network", ip, host, detail)
    try:
        display.show_image(img, full_refresh=True)
    finally:
        display.release()
    return 0


if __name__ == "__main__":
    sys.exit(main())
