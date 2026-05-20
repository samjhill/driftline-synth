"""Atomic patch state persistence."""

from __future__ import annotations

import json
import logging
import os
import tempfile
from pathlib import Path
from typing import Any

from patch_model import Patch

logger = logging.getLogger(__name__)


class StateStore:
    def __init__(self, state_path: Path, favorites_path: Path):
        self.state_path = Path(state_path)
        self.favorites_path = Path(favorites_path)
        self.state_path.parent.mkdir(parents=True, exist_ok=True)

    def _atomic_write(self, path: Path, data: dict[str, Any] | list[Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(data, f, indent=2)
            os.replace(tmp, path)
        except Exception:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise

    def load_current(self) -> Patch | None:
        if not self.state_path.exists():
            return None
        try:
            with open(self.state_path) as f:
                return Patch.from_dict(json.load(f))
        except (json.JSONDecodeError, TypeError, KeyError) as e:
            logger.warning("Corrupt state file %s: %s", self.state_path, e)
            return None

    def save_current(self, patch: Patch) -> None:
        self._atomic_write(self.state_path, patch.to_dict())
        logger.info("Saved patch: %s", patch.summary())

    def load_favorites(self) -> list[Patch]:
        if not self.favorites_path.exists():
            return []
        try:
            with open(self.favorites_path) as f:
                items = json.load(f)
            return [Patch.from_dict(item) for item in items]
        except (json.JSONDecodeError, TypeError) as e:
            logger.warning("Corrupt favorites: %s", e)
            return []

    def add_favorite(self, patch: Patch) -> None:
        favorites = self.load_favorites()
        if any(f.seed == patch.seed for f in favorites):
            logger.info("Patch already in favorites: seed=%s", patch.seed)
            return
        favorites.append(patch)
        self._atomic_write(self.favorites_path, [p.to_dict() for p in favorites])
        logger.info("Added favorite: %s", patch.summary())
