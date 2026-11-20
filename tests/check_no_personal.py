#!/usr/bin/env python3
"""공개 레포의 추적 파일 전부에 개인 정보가 없는지 검사한다.

패턴: <personal>/leak-patterns.txt (DOTFILES_PERSONAL, 기본 personal/ — 비공개 레포라 없으면 건너뜀) + IPv4 주소.
위반은 `path:line: pattern` 으로 출력하고 하나라도 있으면 exit 1.
"""
import os
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
pat_file = pathlib.Path(os.environ.get("DOTFILES_PERSONAL", root / "personal")) / "leak-patterns.txt"
patterns = []
if pat_file.exists():
    for line in pat_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            patterns.append(re.compile(line, re.I))
IP = re.compile(r"(?<![\d.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![\d.])")


def ip_hits(text):
    for m in IP.finditer(text):
        o = [int(x) for x in m.groups()]
        if max(o) > 255 or o[0] in (0, 127, 255):
            continue
        yield m.group(0)


files = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, text=True, check=True).stdout.split("\0")
bad = 0
for f in files:
    # LICENSE 의 저작권자 이름은 일부러 공개하는 정보다
    if not f or f.startswith("personal/") or f in ("LICENSE",):
        continue
    p = root / f
    if not p.is_file():
        continue
    try:
        raw = p.read_bytes()
    except OSError:
        continue
    # 바이너리(plist 등)도 검사한다 — iterm2.plist 안의 사용자 경로를 놓친 적이 있다
    text = raw.decode("utf-8", errors="replace") if b"\0" not in raw else raw.decode("latin-1").replace("\0", "\n")
    for n, line in enumerate(text.splitlines(), 1):
        hits = [r.pattern for r in patterns if r.search(line)] + list(ip_hits(line))
        for h in hits:
            print(f"{f}:{n}: {h}")
            bad += 1
print(f"check_no_personal: {bad} hit(s)" + ("" if patterns else " (no leak-patterns.txt — IP check only)"))
sys.exit(1 if bad else 0)
