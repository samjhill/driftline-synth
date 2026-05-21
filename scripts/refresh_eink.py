#!/usr/bin/env python3
"""Force a full e-ink refresh (clears ghosting) and show network status."""

from __future__ import annotations

import os
import runpy
import sys
from pathlib import Path

os.environ["EINK_FORCE"] = "1"
target = Path(__file__).resolve().parent / "announce_network.py"
sys.exit(runpy.run_path(str(target), run_name="__main__") or 0)
