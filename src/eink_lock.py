"""Exclusive lock for Waveshare e-ink (one process at a time)."""

from __future__ import annotations

import fcntl
import os
import time
from contextlib import contextmanager
from pathlib import Path


def eink_lock_path() -> Path:
    return Path(
        os.environ.get(
            "EINK_LOCK_FILE",
            "/var/lib/pi-ambient-synth/eink.lock",
        )
    )


@contextmanager
def eink_exclusive_lock(timeout_seconds: float = 120.0):
    path = eink_lock_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as lockf:
        deadline = time.time() + timeout_seconds
        while True:
            try:
                fcntl.flock(lockf.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.time() >= deadline:
                    raise TimeoutError(
                        f"e-ink busy (lock held >{timeout_seconds:.0f}s)"
                    )
                time.sleep(0.25)
        try:
            yield
        finally:
            fcntl.flock(lockf.fileno(), fcntl.LOCK_UN)
