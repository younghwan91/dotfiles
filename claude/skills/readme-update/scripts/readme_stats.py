#!/usr/bin/env python3
"""README 모양 재기 — 줄·## 절·그림·배지·코드 블록·<details> 수. 트렌딩 표(references/patterns.md)와 같은 열이다.

    python3 readme_stats.py README.md [README.en.md ...]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def stats(text: str) -> dict:
    lines = text.splitlines()
    return {
        "lines": len(lines),
        "h2": sum(1 for ln in lines if ln.startswith("## ")),
        "images": len(re.findall(r"!\[|<img\b", text)),
        "badges": text.count("shields.io") + text.count("/badge.svg"),
        "code_blocks": sum(1 for ln in lines if ln.strip().startswith("```")) // 2,
        "details": text.count("<details"),
    }


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    print(f"{'file':<28} {'lines':>6} {'##':>4} {'imgs':>5} {'badges':>6} {'code':>5} {'details':>7}")
    for p in argv:
        s = stats(Path(p).read_text("utf-8"))
        print(f"{p:<28} {s['lines']:>6} {s['h2']:>4} {s['images']:>5} {s['badges']:>6} {s['code_blocks']:>5} {s['details']:>7}")
        for ln in Path(p).read_text("utf-8").splitlines():
            if ln.startswith("## "):
                print(f"    {ln}")
    print("\n목표(트렌딩, 2026-11): 80~150줄, 그림·기능 표·설치 변형이 있으면 250줄까지. 250줄을 넘으면 더 옮긴다. ## 6~10개.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
