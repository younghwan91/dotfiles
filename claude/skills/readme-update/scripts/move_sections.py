#!/usr/bin/env python3
"""README 의 긴 절을 글자 그대로 다른 문서로 옮긴다 — 상대 링크·그림 경로는 새 폴더에 맞춰 고친다.

    python3 move_sections.py --readme README.md --out docs/guide.md \\
        --start "## 1. 무엇을 하나" --end "## 후원" --title "프로젝트 가이드" [--dry-run]

--start 제목 줄부터 --end 제목 줄 바로 앞까지를 옮긴다(--end 를 안 주면 파일 끝까지). README 에서는 그 블록을 지운다 —
새 README 의 해당 자리는 사람이 다시 쓴다. 제목 글자가 그대로라 문서 안 #앵커는 그대로 맞는다.
링크: http(s)·mailto·# 은 그대로, 나머지 상대 경로는 새 파일 위치 기준으로 다시 계산한다.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

LINK = re.compile(r"(!?\[[^\]]*\])\(([^)\s]+)(\s+\"[^\"]*\")?\)")
HTML_SRC = re.compile(r"""((?:src|href|srcset)=["'])([^"']+)(["'])""")


def rebase(url: str, src_dir: Path, dst_dir: Path) -> str:
    if re.match(r"(?:[a-z][a-z0-9+.-]*:|#|/)", url, re.I):
        return url
    path, _, frag = url.partition("#")
    if not path:
        return url
    new = os.path.relpath(os.path.normpath(src_dir / path), dst_dir)
    if path.endswith("/") and not new.endswith("/"):
        new += "/"
    return new + ("#" + frag if frag else "")


def rewrite(text: str, src_dir: Path, dst_dir: Path) -> str:
    text = LINK.sub(lambda m: f"{m.group(1)}({rebase(m.group(2), src_dir, dst_dir)}{m.group(3) or ''})", text)
    return HTML_SRC.sub(lambda m: f"{m.group(1)}{rebase(m.group(2), src_dir, dst_dir)}{m.group(3)}", text)


def _slug(heading: str) -> str:
    h = re.sub(r"`|\*\*|\[|\]\([^)]*\)", "", heading)
    return re.sub(r"[^\w\- ]", "", h.strip().lower(), flags=re.U).replace(" ", "-")


def keep_anchors(block: str, back: str) -> str:
    """옮긴 글 안의 ``(#x)`` 중 옮긴 글에 없는 제목을 가리키는 것은 README 쪽(``back#x``)으로 바꾼다."""
    here = {_slug(m.group(1)) for m in re.finditer(r"^#{1,6} +(.+?) *#*$", block, re.M)}
    return re.sub(r"\]\(#([^)\s]+)\)", lambda m: m.group(0) if m.group(1) in here else f"]({back}#{m.group(1)})", block)


TOC_START, TOC_END = "<!-- toc -->", "<!-- /toc -->"


def is_korean(text: str) -> bool:
    return len(re.findall(r"[\uac00-\ud7a3]", text)) > 50


def toc(text: str) -> str:
    """새 문서의 ``##`` 제목으로 목차 — 앵커는 GitHub 방식."""
    items = [f"- [{h}](#{_slug(h)})" for h in re.findall(r"^## +(.+?) *#*$", text, re.M)]
    return f"{TOC_START}\n" + "\n".join(items) + f"\n{TOC_END}"


def with_toc(text: str) -> str:
    if TOC_START in text and TOC_END in text:
        a, rest = text.split(TOC_START, 1)
        return a + toc(text) + rest.split(TOC_END, 1)[1]
    return text


def find_heading(lines: list[str], heading: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if lines[i].rstrip("\n").startswith(heading):
            return i
    raise SystemExit(f"제목을 못 찾았다: {heading!r}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--readme", default="README.md")
    ap.add_argument("--out", required=True)
    ap.add_argument("--start", required=True, help="옮길 첫 제목 줄(앞부분 일치)")
    ap.add_argument("--end", help="여기서 멈춘다(이 줄은 README 에 남는다). 없으면 파일 끝까지")
    ap.add_argument("--title", default="Guide", help="새 문서의 # 제목(새 파일일 때만)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)

    readme, out = Path(a.readme), Path(a.out)
    lines = readme.read_text("utf-8").splitlines(keepends=True)
    i = find_heading(lines, a.start)
    j = find_heading(lines, a.end, i + 1) if a.end else len(lines)
    block = re.sub(r"(\n\s*(---|\*\*\*)\s*)+$", "", "".join(lines[i:j]).rstrip()) + "\n"   # 앞 절 끝의 가로줄은 딸려 가지 않게
    moved = rewrite(block, readme.parent.resolve(), out.parent.resolve())
    back = os.path.relpath(readme.resolve(), out.parent.resolve())
    moved = keep_anchors(moved, back)
    if a.dry_run:
        print(f"옮길 줄 {j - i}개: {lines[i].strip()!r} … {lines[j - 1].strip() if j > i else ''!r}")
        print(f"→ {out} (README 로 돌아가는 링크: {back})")
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.write_text(with_toc(out.read_text("utf-8").rstrip() + "\n\n" + moved), "utf-8")
    else:
        ko = is_korean("".join(lines))
        intro = f"처음이라면 [README]({back}) 부터." if ko else f"New here? Start with the [README]({back})."
        out.write_text(with_toc(f"# {a.title}\n\n{intro}\n\n{TOC_START}\n{TOC_END}\n\n{moved}"), "utf-8")
    readme.write_text("".join(lines[:i] + lines[j:]), "utf-8")
    print(f"옮겼다: {j - i}줄 → {out}. README {len(lines)} → {len(lines) - (j - i)}줄")
    return 0


if __name__ == "__main__":
    sys.exit(main())
