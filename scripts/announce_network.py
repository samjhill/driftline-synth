#!/usr/bin/env python3
"""Show LAN IP on e-ink and write network-address files."""

from __future__ import annotations

import argparse
import logging
import os
import subprocess
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
from network_info import network_snapshot, save_network_info


def _setup_eink_logging() -> None:
    log_path = os.environ.get("EINK_LOG", "/var/log/pi-ambient-synth-eink.log")
    handlers: list[logging.Handler] = [logging.StreamHandler()]
    try:
        path = Path(log_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(path, mode="a", encoding="utf-8"))
    except OSError:
        pass
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s %(message)s",
        handlers=handlers,
        force=True,
    )


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
    # stderr only — deploy captures stdout from resolve_target_sha (must not mix with SHA).
    print(f"Network: {ip}  ({host}.local)  monitor {url}", file=sys.stderr)

    if args.no_eink or not config.get("eink", {}).get("enabled", True):
        return 0

    detail = url.replace("http://", "")[:28]
    root = Path(__file__).resolve().parent.parent
    sys.path.insert(0, str(root / "src"))
    _setup_eink_logging()
    try:
        from eink_queue import enqueue_status

        if enqueue_status("network", ip, host, detail) is None:
            logging.warning("e-ink network status enqueue failed")
            return 1
        logging.info("Network queued for e-ink: %s (%s)", ip, host)
        return 0
    except Exception as e:
        logging.warning("e-ink queue unavailable: %s", e)
        return 0


if __name__ == "__main__":
    sys.exit(main())
