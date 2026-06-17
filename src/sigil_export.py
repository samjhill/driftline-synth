"""Export patch sigil PNGs to state/sigils/."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from patch_model import Patch
from visual_generator import VisualGenerator


def export_sigil(patch: Patch, visual: VisualGenerator, base_dir: Path) -> Path:
    base_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    safe_name = "".join(c if c.isalnum() or c in "-_" else "_" for c in patch.name)[:24]
    path = base_dir / f"{stamp}_{patch.seed}_{safe_name}.png"
    img = visual.render_patch(patch)
    img.save(path)
    return path
