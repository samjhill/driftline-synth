#!/usr/bin/env python3
"""CLI: enqueue e-ink commands for pi-ambient-synth-eink.service (no GPIO access)."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from eink_queue import enqueue, enqueue_patch, enqueue_startup, enqueue_status


def main() -> int:
    p = argparse.ArgumentParser(description="Enqueue e-ink display command")
    p.add_argument("--json", type=str, help='Raw JSON message, e.g. \'{"type":"patch"}\'')
    sub = p.add_subparsers(dest="cmd")

    sub.add_parser("startup", help="Startup splash")
    sp = sub.add_parser("status", help="Status screen")
    sp.add_argument("phase")
    sp.add_argument("title")
    sp.add_argument("subtitle", nargs="?", default="")
    sp.add_argument("detail", nargs="?", default="")

    pp = sub.add_parser("patch", help="Patch name screen")
    pp.add_argument("--from-state", action="store_true", help="Read current_patch.json")
    pp.add_argument("name", nargs="?", default="")
    pp.add_argument("subtitle", nargs="?", default="")
    pp.add_argument("detail", nargs="?", default="")

    args = p.parse_args()
    path = None
    if args.json:
        path = enqueue(json.loads(args.json))
    elif args.cmd == "startup":
        path = enqueue_startup()
    elif args.cmd == "status":
        path = enqueue_status(args.phase, args.title, args.subtitle, args.detail)
    elif args.cmd == "patch":
        path = enqueue_patch(
            name=args.name,
            subtitle=args.subtitle,
            detail=args.detail,
            from_state=args.from_state,
        )
    else:
        p.print_help()
        return 1

    if path is None:
        print("enqueue failed", file=sys.stderr)
        return 1
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
