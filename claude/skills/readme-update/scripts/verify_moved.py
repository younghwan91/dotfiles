#!/usr/bin/env python3
"""README 를 다시 짠 뒤 옛 README 의 글이 어딘가에 남았는가 — 옮긴 것은 남고, 지운 것만 드러난다.

    python3 verify_moved.py --before old_README.md --after README.md docs/
    python3 verify_moved.py --before <(git show HEAD:README.md) --after README.md README.en.md docs/

옛 README 의 비어 있지 않은 줄(앞뒤 공백·글머리표 기호를 떼고, 링크 경로는 무시)을 새 README 와 --after 로 준 파일·폴더의
.md 에서 찾는다. 못 찾은 줄을 찍는다 — 의도한 고쳐 쓰기면 그대로 두고, 아니면 되살린다. 못 찾은 줄이 있으면 1.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def norm(line: str) -> str:
    s = re.sub(r"\]\([^)]*\)", "]", line)                 # 링크 경로는 옮기며 바뀐다
    s = re.sub(r"""(?:src|href|srcset)=["'][^"']*["']""", "", s)
    s = re.sub(r"^\s*(?:[-*+]|\d+\.)\s+", "", s)
    return " ".join(s.split())


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--before", required=True, help="옛 README(파일 또는 <(git show ...))")
    ap.add_argument("--after", nargs="+", required=True, help="새 README 와 옮겨 간 문서·폴더")
    a = ap.parse_args(argv)
    old = [ln for ln in Path(a.before).read_text("utf-8").splitlines() if norm(ln) and norm(ln) not in ("---", "```")]
    pool = []
    for p in map(Path, a.after):
        for f in ([p] if p.is_file() else sorted(p.rglob("*.md"))):
            pool.append(" ".join(norm(ln) for ln in f.read_text("utf-8").splitlines()))
    hay = "\n".join(pool)
    missing = [ln for ln in old if norm(ln) not in hay]
    for ln in missing:
        print(f"없음: {ln.strip()[:160]}")
    print(f"옛 줄 {len(old)}개 중 {len(old) - len(missing)}개가 남았다, {len(missing)}개는 없다")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
