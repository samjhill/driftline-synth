"""LAN address discovery for e-ink display and monitor UI."""

from __future__ import annotations

import json
import socket
import subprocess
from pathlib import Path
from typing import Any


def get_hostname() -> str:
    return socket.gethostname().split(".")[0] or "raspberrypi"


def get_all_ipv4() -> list[str]:
    ips: list[str] = []
    try:
        out = subprocess.check_output(
            ["hostname", "-I"],
            text=True,
            timeout=5,
        ).strip()
        ips = [p for p in out.split() if p and not p.startswith("169.254.")]
    except (subprocess.SubprocessError, FileNotFoundError):
        pass
    if not ips:
        try:
            for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
                addr = info[4][0]
                if not addr.startswith("127.") and addr not in ips:
                    ips.append(addr)
        except OSError:
            pass
    return ips


def get_primary_ipv4() -> str | None:
    ips = get_all_ipv4()
    if ips:
        return ips[0]
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(2.0)
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        sock.close()
        return ip
    except OSError:
        return None


def network_snapshot(monitor_port: int = 8080) -> dict[str, Any]:
    hostname = get_hostname()
    primary = get_primary_ipv4()
    all_ips = get_all_ipv4()
    mdns = f"{hostname}.local"
    monitor_url = f"http://{primary}:{monitor_port}/" if primary else None
    ssh_hint = f"ssh pi@{mdns}" if primary else None
    return {
        "hostname": hostname,
        "primary_ip": primary,
        "all_ips": all_ips,
        "mdns": mdns,
        "monitor_port": monitor_port,
        "monitor_url": monitor_url,
        "ssh_hint": ssh_hint,
    }


def save_network_info(
    snapshot: dict[str, Any],
    marker_dir: Path | str = "/var/lib/pi-ambient-synth",
    boot_log_dir: Path | str | None = None,
) -> Path:
    marker = Path(marker_dir)
    try:
        marker.mkdir(parents=True, exist_ok=True)
        path = marker / "network.json"
        path.write_text(json.dumps(snapshot, indent=2) + "\n", encoding="utf-8")
    except PermissionError as e:
        raise PermissionError(
            f"Cannot write {marker / 'network.json'} — "
            f"run: sudo chown -R pi:pi {marker}"
        ) from e

    lines = [
        f"hostname={snapshot.get('hostname', '')}",
        f"ip={snapshot.get('primary_ip', '')}",
        f"monitor={snapshot.get('monitor_url', '')}",
        f"ssh={snapshot.get('ssh_hint', '')}",
    ]
    address_text = "\n".join(lines) + "\n"
    (marker / "network-address.txt").write_text(address_text, encoding="utf-8")

    if boot_log_dir:
        boot_dir = Path(boot_log_dir)
        try:
            boot_dir.mkdir(parents=True, exist_ok=True)
            (boot_dir / "network-address.txt").write_text(address_text, encoding="utf-8")
        except OSError:
            # Boot partition is often read-only after imaging; marker copy is enough.
            pass
    return path
