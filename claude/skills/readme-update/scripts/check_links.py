#!/usr/bin/env python3
"""마크다운 상대 링크·그림·#앵커가 실제로 있는가 — README 를 다시 짠 뒤 돌린다.

    python3 check_links.py README.md README.en.md docs/guide.md

깨진 것이 있으면 줄 번호와 함께 찍고 1 로 끝난다. http(s)·mailto 는 보지 않는다.
앵커는 GitHub 방식으로 만든다: 소문자, 글자·숫자·공백·하이픈·밑줄만 남기고 공백은 하이픈.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HTML = re.compile(r"""(?:src|href|srcset)=["']([^"']+)["']""")
FENCE = re.compile(r"^```.*?^```", re.S | re.M)


def slug(heading: str) -> str:
    h = re.sub(r"[^\w\- ]", "", heading.strip().lower(), flags=re.U)
    return h.replace(" ", "-")


def anchors(path: Path) -> set[str]:
    text = FENCE.sub("", path.read_text("utf-8"))
    seen: dict[str, int] = {}
    out = set()
    for m in re.finditer(r"^#{1,6} +(.+?) *#*$", text, re.M):
        s = slug(re.sub(r"`|\*\*|\[|\]\([^)]*\)", "", m.group(1)))
        n = seen.get(s, 0)
        out.add(s if n == 0 else f"{s}-{n}")
        seen[s] = n + 1
    return out


def check(path: Path) -> list[str]:
    bad = []
    text = path.read_text("utf-8")
    body = FENCE.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    for no, line in enumerate(body.splitlines(), 1):
        for url in [*LINK.findall(line), *HTML.findall(line)]:
            if re.match(r"(?:[a-z][a-z0-9+.-]*:|//)", url, re.I):
                continue
            target, _, frag = url.partition("#")
            dest = path if not target else (path.parent / target)
            if target and not dest.exists():
                bad.append(f"{path}:{no}: 없는 경로 {url}")
                continue
            if frag and dest.suffix == ".md" and dest.is_file() and frag not in anchors(dest):
                bad.append(f"{path}:{no}: 없는 앵커 {url}")
    return bad


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    bad = [b for p in argv for b in check(Path(p))]
    print("\n".join(bad) if bad else f"링크·그림·앵커 모두 있다 ({len(argv)}개 파일)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
