#!/usr/bin/env python3
"""Deprecated CLI — forwards to scripts/eink_display.py (official driver only)."""
from __future__ import annotations

import sys
from pathlib import Path

# Re-exec as eink_display with mapped args
_display = Path(__file__).resolve().parent / "eink_display.py"
_legacy = {
    "boot": ["firstboot-post"],
    "post": ["firstboot-post"],
    "post-light": ["firstboot-post"],
    "post_light": ["firstboot-post"],
    "status": ["progress"],
    "wifi-failed": ["wifi-failed"],
    "install-failed": ["install-failed"],
    "ssh-ready": ["ssh-ready"],
    "ssh": ["ssh-ready"],
    "audio-ready": ["progress", "AUDIO", "OK"],
    "emergency": ["minimal"],
}

cmd = (sys.argv[1] if len(sys.argv) > 1 else "firstboot-post").lower()
if cmd == "status" and len(sys.argv) >= 3:
    mapped = ["progress", sys.argv[2], *(sys.argv[3:4] if len(sys.argv) > 3 else [])]
elif cmd in ("ssh-ready", "ssh") and len(sys.argv) >= 3:
    mapped = ["ssh-ready", sys.argv[2]]
elif cmd == "wifi-failed":
    mapped = ["wifi-failed", *sys.argv[2:]]
else:
    mapped = _legacy.get(cmd, [cmd, *sys.argv[2:]])

sys.argv = [str(_display), *mapped]
with open(_display) as f:
    code = compile(f.read(), str(_display), "exec")
    globs = {"__name__": "__main__"}
    exec(code, globs)  # noqa: S102
