#!/usr/bin/env python3
"""Print sample patches and validate ranges."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config
from patch_generator import PatchGenerator

config = load_config()
gen = PatchGenerator(config)

for seed in (1, 42, 99999):
    p = gen.generate(seed=seed)
    errs = PatchGenerator.validate_ranges(p)
    status = "OK" if not errs else f"ERRORS: {errs}"
    print(f"seed={seed}: {p.summary()} — {status}")
