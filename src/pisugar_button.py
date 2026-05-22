"""Configure PiSugar programmable button via pisugar-server socket API."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from pisugar_battery import query_pisugar

logger = logging.getLogger(__name__)

ButtonKind = str  # single | double | long


def _pisugar_cfg(config: dict[str, Any]) -> dict[str, Any]:
    return config.get("pisugar", {})


def get_button_shell(kind: ButtonKind, config: dict[str, Any]) -> str | None:
    data = query_pisugar(f"get button_shell {kind}", config)
    raw = data.get(f"button_shell")
    if raw is None:
        return None
    # Response key may be "button_shell" with value "single /path/..." or split lines.
    if isinstance(raw, str):
        parts = raw.split(maxsplit=1)
        if len(parts) == 2 and parts[0] == kind:
            return parts[1].strip()
        if raw.startswith(kind):
            return raw[len(kind) :].strip()
        return raw.strip() or None
    return None


def is_button_enabled(kind: ButtonKind, config: dict[str, Any]) -> bool | None:
    data = query_pisugar(f"get button_enable {kind}", config)
    for key, val in data.items():
        if key == "button_enable" and isinstance(val, bool):
            return val
        if isinstance(val, str) and kind in val:
            return "true" in val.lower()
    return None


def configure_button_shell(
    kind: ButtonKind,
    script_path: str | Path,
    *,
    config: dict[str, Any],
    enable: bool = True,
) -> bool:
    """Assign shell script to PiSugar tap (single/double/long). Returns True if server accepted."""
    path = str(Path(script_path).resolve())
    cmds = [f"set_button_shell {kind} {path}"]
    if enable:
        cmds.append(f"set_button_enable {kind} 1")
    ok = True
    for cmd in cmds:
        data = query_pisugar(cmd, config)
        if not data:
            logger.warning("PiSugar command %r returned no ack", cmd)
            ok = False
        else:
            logger.info("PiSugar: %s → %s", cmd, data)
    return ok


def setup_reseed_button(
    install_root: str | Path,
    config: dict[str, Any],
) -> bool:
    """Wire PiSugar single-tap to pi_pisugar_button_reseed.sh."""
    cfg = _pisugar_cfg(config)
    if not cfg.get("enabled", False):
        logger.info("PiSugar disabled in config — skip button setup")
        return False
    if not cfg.get("reseed_on_button", True):
        logger.info("pisugar.reseed_on_button=false — skip")
        return False

    root = Path(install_root)
    script = root / "scripts" / "pi_pisugar_button_reseed.sh"
    if not script.is_file():
        logger.error("Missing %s", script)
        return False

    kind = str(cfg.get("reseed_button_kind", "single"))
    return configure_button_shell(kind, script, config=config, enable=True)
