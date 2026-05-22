"""Persisted patch genre + reseed scope (monitor / MIDI bridge)."""

from __future__ import annotations

import json
import logging
import os
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from patch_genres import DEFAULT_GENRE, GENRES, VALID_RESEED_SCOPES

logger = logging.getLogger(__name__)


@dataclass
class PatchPrefs:
    genre: str = DEFAULT_GENRE
    reseed_scope: str = "genre"  # genre | all

    def normalized(self) -> PatchPrefs:
        genre = self.genre if self.genre in GENRES else DEFAULT_GENRE
        scope = self.reseed_scope if self.reseed_scope in VALID_RESEED_SCOPES else "genre"
        return PatchPrefs(genre=genre, reseed_scope=scope)

    def to_dict(self) -> dict[str, str]:
        n = self.normalized()
        return {"genre": n.genre, "reseed_scope": n.reseed_scope}


def prefs_path(config: dict[str, Any]) -> Path:
    app = config.get("app", {})
    marker = Path(app.get("marker_dir", "/var/lib/pi-ambient-synth"))
    return marker / "patch-prefs.json"


def default_prefs(config: dict[str, Any]) -> PatchPrefs:
    patch_cfg = config.get("patch", {})
    return PatchPrefs(
        genre=str(patch_cfg.get("default_genre", DEFAULT_GENRE)),
        reseed_scope=str(patch_cfg.get("default_reseed_scope", "genre")),
    ).normalized()


def load_patch_prefs(config: dict[str, Any]) -> PatchPrefs:
    path = prefs_path(config)
    if not path.is_file():
        return default_prefs(config)
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return PatchPrefs(
            genre=str(data.get("genre", DEFAULT_GENRE)),
            reseed_scope=str(data.get("reseed_scope", "genre")),
        ).normalized()
    except (json.JSONDecodeError, TypeError, OSError) as e:
        logger.warning("Corrupt patch prefs %s: %s", path, e)
        return default_prefs(config)


def save_patch_prefs(config: dict[str, Any], prefs: PatchPrefs) -> PatchPrefs:
    path = prefs_path(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = prefs.normalized()
    fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(normalized.to_dict(), f, indent=2)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    logger.info("Saved patch prefs: %s", normalized.to_dict())
    return normalized
