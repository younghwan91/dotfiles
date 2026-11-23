#!/usr/bin/env python3
"""마크다운 상대 링크·그림·#앵커가 실제로 있는가 — README 를 다시 짠 뒤 돌린다.

    python3 check_links.py README.md README.en.md docs/guide.md
    python3 check_links.py --baseline HEAD README.md docs/guide.md   # 내가 새로 깨뜨린 것만 실패로

깨진 것이 있으면 줄 번호와 함께 찍고 1 로 끝난다. http(s)·mailto 는 보지 않는다.
--baseline REV 를 주면 그 판의 같은 파일(없으면 그 판의 README.md)에서 이미 깨져 있던 대상은 "원래 깨짐" 으로 따로 찍고 실패로 세지 않는다.
앵커는 GitHub 방식으로 만든다: 소문자, 글자·숫자·공백·하이픈·밑줄만 남기고 공백은 하이픈.
"""
from __future__ import annotations

import re
import subprocess
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


def broken_targets(path: Path, text: str) -> set[str]:
    """깨진 대상을 레포 기준 경로로(줄 번호 없이) — 판끼리 견줄 때 쓴다."""
    out = set()
    for line in check(path, text):
        url = line.rsplit(" ", 1)[-1]
        target, _, frag = url.partition("#")
        base = (path.parent / target).resolve() if target else path.resolve()
        out.add(f"{base}#{frag}" if frag else str(base))
    return out


def old_text(rev: str, path: Path) -> tuple[str, Path]:
    """그 판의 같은 파일, 없으면(새로 만든 가이드) 그 판의 README — 링크는 원래 있던 자리 기준으로 푼다."""
    for cand in (path, Path("README.md")):
        p = subprocess.run(["git", "show", f"{rev}:{cand.as_posix()}"], capture_output=True, text=True)
        if p.returncode == 0:
            return p.stdout, cand
    return "", path


def check(path: Path, text: str | None = None) -> list[str]:
    bad = []
    text = path.read_text("utf-8") if text is None else text
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
    rev = None
    if argv[:1] == ["--baseline"] and len(argv) > 1:
        rev, argv = argv[1], argv[2:]
    if not argv:
        print(__doc__)
        return 2
    new, old = [], []
    for p in map(Path, argv):
        bad = check(p)
        was = broken_targets(*reversed(old_text(rev, p))) if rev else set()
        for b in bad:
            url = b.rsplit(" ", 1)[-1]
            target, _, frag = url.partition("#")
            key = (p.parent / target).resolve() if target else p.resolve()
            key = f"{key}#{frag}" if frag else str(key)
            (old if key in was else new).append(b)
    for b in old:
        print(f"원래 깨짐  {b}")
    for b in new:
        print(f"새로 깨짐  {b}" if rev else b)
    if not new:
        print(f"새로 깨진 링크·그림·앵커 없음 ({len(argv)}개 파일, 원래 깨진 것 {len(old)}건)" if rev
              else f"링크·그림·앵커 모두 있다 ({len(argv)}개 파일)")
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
