#!/usr/bin/env python3
"""Static checks for synth/ambient_engine.scd (no SuperCollider required)."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def _strip_comments_and_strings(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = j + 2 if j >= 0 else n
            continue
        ch = text[i]
        if ch in "\"'":
            quote = ch
            i += 1
            while i < n:
                if text[i] == "\\" and i + 1 < n:
                    i += 2
                    continue
                if text[i] == quote:
                    i += 1
                    break
                i += 1
            out.append(" ")
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def validate(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    errors: list[str] = []
    stripped = _strip_comments_and_strings(text)
    lines = text.splitlines()

    if not text.lstrip().startswith("//"):
        pass  # optional header comment
    body = stripped.strip()
    if not body.startswith("("):
        errors.append("file must start with a top-level ( ... ) block")
    if body.rstrip()[-1:] != ")":
        errors.append("file must end with closing ) for top-level block")

    paren = sum(1 if c == "(" else -1 if c == ")" else 0 for c in stripped)
    if paren != 0:
        errors.append(f"unbalanced parentheses in code (net {paren:+d})")

    brace = 0
    for c in stripped:
        if c == "{":
            brace += 1
        elif c == "}":
            brace -= 1
    if brace != 0:
        errors.append(f"unbalanced braces in code (net {brace:+d})")

    depth = 0
    initial_vars_done = False
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if depth == 0:
            if stripped.startswith("var "):
                if initial_vars_done:
                    errors.append(
                        f"line {i}: var must be at top of ( ) block — not after other statements"
                    )
            elif stripped not in ("(", ")"):
                initial_vars_done = True
        depth += stripped.count("{") - stripped.count("}")

    for i, line in enumerate(lines, 1):
        if re.search(r"\band\s+\{", line) and "and:" not in line:
            errors.append(f"line {i}: use 'and:' not 'and {{' for short-circuit AND")
        if re.search(r"\.and\(\{", line):
            errors.append(
                f"line {i}: use 'expr and: {{ ... }}' not '{{ expr }}.and({{ ... }})' (Non Boolean in test)"
            )
        if re.search(r"msg\[\d+\]\s*\?\s*msg\[\d+\]\s*:", line):
            errors.append(f"line {i}: JS ternary invalid in SC — use msg[n] ?? default")
        if re.search(r"\bTWhiteNoise\.", line):
            errors.append(
                f"line {i}: TWhiteNoise missing on Pi SC 3.13 — use LFNoise0.kr(...).range(...)"
            )
        if re.search(r"\.booted\b", line):
            errors.append(
                f"line {i}: Server.booted is not in SC 3.13 — use s.serverRunning"
            )

    # Block before infinite loop must close if(s.serverRunning) with });
    for idx, line in enumerate(lines):
        if line.strip() == "while { true } { 1.wait };" or line.strip().startswith(
            "if(getenv(\"SC_ENGINE_TEST\")"
        ):
            prev = lines[idx - 1].strip() if idx > 0 else ""
            if prev == "};":
                errors.append(
                    f"line {idx}: server block closes with '}};' — should be '}});'"
                )
            break

    banned = [
        (r"\?\s*msg\[\d+\]\s*:", "JS-style ternary with msg[...]"),
    ]
    for pat, msg in banned:
        for i, line in enumerate(lines, 1):
            if re.search(pat, line):
                errors.append(f"line {i}: {msg}")

    return errors


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "synth/ambient_engine.scd")
    if not path.is_file():
        print(f"ERROR: not found: {path}", file=sys.stderr)
        return 1
    errors = validate(path)
    if errors:
        print(f"FAIL: {path}", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print(f"OK: {path} (static)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
