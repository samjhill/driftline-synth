"""Read PiSugar 2 / 2 Pro battery state via pisugar-server socket API."""

from __future__ import annotations

import logging
import re
import socket
from dataclasses import dataclass
from typing import Any

logger = logging.getLogger(__name__)

_VALUE_RE = re.compile(r"^([\w_]+)\s*:\s*(.+)$")


@dataclass(frozen=True)
class BatterySnapshot:
    percent: int | None
    voltage_v: float | None
    charging: bool | None
    plugged: bool | None
    available: bool
    label: str

    @property
    def display_percent(self) -> int | None:
        if self.percent is None:
            return None
        return max(0, min(100, int(self.percent)))


def _pisugar_cfg(config: dict[str, Any]) -> dict[str, Any]:
    return config.get("pisugar", {})


def _parse_bool(raw: str) -> bool | None:
    val = raw.strip().lower()
    if val in ("true", "1", "yes"):
        return True
    if val in ("false", "0", "no"):
        return False
    return None


def _parse_value(key: str, raw: str) -> int | float | bool | str | None:
    raw = raw.strip()
    if key == "battery":
        try:
            return int(float(raw))
        except ValueError:
            return None
    if key == "battery_v":
        try:
            return float(raw)
        except ValueError:
            return None
    if key.startswith("battery_") or key.endswith("_charging"):
        return _parse_bool(raw)
    return raw


def parse_pisugar_line(line: str) -> tuple[str, Any] | None:
    m = _VALUE_RE.match(line.strip())
    if not m:
        return None
    key, raw = m.group(1), m.group(2)
    return key, _parse_value(key, raw)


def _send_command(host: str, port: int, command: str, timeout: float) -> list[str]:
    payload = (command.strip() + "\n").encode()
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.sendall(payload)
        sock.shutdown(socket.SHUT_WR)
        lines: list[str] = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            lines.extend(chunk.decode(errors="replace").splitlines())
        return lines


def _send_command_uds(path: str, command: str, timeout: float) -> list[str]:
    payload = (command.strip() + "\n").encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(path)
        sock.sendall(payload)
        sock.shutdown(socket.SHUT_WR)
        lines: list[str] = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            lines.extend(chunk.decode(errors="replace").splitlines())
        return lines


def query_pisugar(command: str, config: dict[str, Any]) -> dict[str, Any]:
    """Run one pisugar-server command; return parsed key/value pairs."""
    cfg = _pisugar_cfg(config)
    timeout = float(cfg.get("command_timeout_seconds", 2.0))
    errors: list[str] = []

    sock_path = cfg.get("socket_path", "/tmp/pisugar-server.sock")
    try:
        lines = _send_command_uds(sock_path, command, timeout)
        parsed = {}
        for line in lines:
            item = parse_pisugar_line(line)
            if item:
                parsed[item[0]] = item[1]
        if parsed:
            return parsed
    except OSError as e:
        errors.append(f"uds:{e}")

    host = cfg.get("tcp_host", "127.0.0.1")
    port = int(cfg.get("tcp_port", 8423))
    try:
        lines = _send_command(host, port, command, timeout)
        parsed = {}
        for line in lines:
            item = parse_pisugar_line(line)
            if item:
                parsed[item[0]] = item[1]
        return parsed
    except OSError as e:
        errors.append(f"tcp:{e}")

    if errors:
        logger.debug("PiSugar query %r failed: %s", command, "; ".join(errors))
    return {}


def read_battery_snapshot(config: dict[str, Any]) -> BatterySnapshot:
    cfg = _pisugar_cfg(config)
    if not cfg.get("enabled", False):
        return BatterySnapshot(
            percent=None,
            voltage_v=None,
            charging=None,
            plugged=None,
            available=False,
            label="",
        )

    data = query_pisugar("get battery", config)
    percent = data.get("battery")
    if isinstance(percent, (int, float)):
        percent = int(percent)
    else:
        percent = None

    voltage = data.get("battery_v")
    if not isinstance(voltage, (int, float)):
        voltage = None
    else:
        voltage = float(voltage)

    plugged_raw = query_pisugar("get battery_power_plugged", config).get(
        "battery_power_plugged"
    )
    charging_raw = query_pisugar("get battery_charging", config).get(
        "battery_charging"
    )
    allow_raw = query_pisugar("get battery_allow_charging", config).get(
        "battery_allow_charging"
    )

    plugged = plugged_raw if isinstance(plugged_raw, bool) else None
    charging = charging_raw if isinstance(charging_raw, bool) else None
    if charging is None and plugged is not None:
        if plugged and isinstance(allow_raw, bool):
            charging = allow_raw
        elif plugged:
            charging = True

    available = percent is not None
    label = ""
    if available:
        label = f"{percent}%"
        if charging:
            label += " ⚡"
        if isinstance(voltage, float):
            label += f"  {voltage:.2f}V"

    return BatterySnapshot(
        percent=percent,
        voltage_v=voltage,
        charging=charging,
        plugged=plugged,
        available=available,
        label=label,
    )
