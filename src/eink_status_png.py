"""Write e-ink status PNG for pi_eink_waveshare213v4 (ingest-style watch loop)."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

DEFAULT_STATUS_PNG = Path("/var/lib/pi-ambient-synth/eink-status.png")


def status_png_path() -> Path:
    raw = os.environ.get("PI_EINK_STATUS_IMAGE_PATH", "").strip()
    if raw:
        return Path(raw)
    return DEFAULT_STATUS_PNG


def _atomic_save_png(img, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".png.tmp")
    img.save(tmp, format="PNG")
    tmp.replace(path)


def render_status_image(
    config: dict[str, Any],
    *,
    phase: str,
    title: str,
    subtitle: str = "",
    detail: str = "",
    battery=None,
) -> "Image.Image":
    from status_display import StatusDisplay

    renderer = StatusDisplay(config)
    return renderer.render(
        phase, title, subtitle, detail, battery=battery
    )


def write_status_png(
    config: dict[str, Any],
    *,
    phase: str,
    title: str,
    subtitle: str = "",
    detail: str = "",
    path: Path | None = None,
) -> Path | None:
    """Render status screen and atomically update the watched PNG."""
    try:
        from PIL import Image  # noqa: F401

        dest = path or status_png_path()
        img = render_status_image(
            config, phase=phase, title=title, subtitle=subtitle, detail=detail
        )
        _atomic_save_png(img, dest)
        return dest
    except OSError:
        return None


def write_patch_png(
    config: dict[str, Any],
    *,
    name: str = "",
    subtitle: str = "",
    detail: str = "",
    from_state: bool = False,
    path: Path | None = None,
) -> Path | None:
    """Render current patch (or explicit fields) to the watched PNG."""
    title = name
    sub = subtitle
    det = detail
    summary = title or "patch"

    if from_state or not title:
        try:
            from patch_generator import PatchGenerator
            from state_store import StateStore

            app = config.get("app", {})
            store = StateStore(
                Path(app.get("state_path", "./state/current_patch.json")),
                Path(app.get("favorites_path", "./state/favorites.json")),
            )
            patch = store.load_current()
            if not patch:
                patch = PatchGenerator(config).generate()
            title = patch.name[:28]
            sub = patch.scale_name[:28]
            det = f"seed {patch.seed}"
            summary = patch.summary()
        except Exception:
            title = title or "Ambient"
            sub = sub or ""

    dest = write_status_png(
        config,
        phase="playing",
        title=title,
        subtitle=sub,
        detail=det,
        path=path,
    )
    if dest is not None:
        try:
            from eink_status import write_eink_status

            write_eink_status("OK", patch_summary=summary)
        except Exception:
            pass
    return dest
