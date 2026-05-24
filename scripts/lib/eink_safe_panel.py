#!/usr/bin/env python3
"""DEPRECATED — do not use. Canonical path: src/eink_official_driver.py."""
from __future__ import annotations

import warnings

warnings.warn(
    "eink_safe_panel is deprecated; use src.eink_official_driver",
    DeprecationWarning,
    stacklevel=2,
)


def _dead(*_args, **_kwargs):
    raise RuntimeError(
        "eink_safe_panel is removed from the active path; "
        "use src/eink_official_driver.py via scripts/eink_display.py"
    )


post_boot_sequence = _dead
post_light_sequence = _dead
show_status = _dead
wifi_heartbeat = _dead
show_failure = _dead
emergency_pattern = _dead
vendor_root = _dead
