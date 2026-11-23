#!/usr/bin/env bash
# README 를 가리키는 곳 찾기 — 절을 옮긴 뒤 새 자리로 바꿔야 할 링크·문구·검사.
#   bash find_readme_refs.sh [레포 경로]
set -uo pipefail
cd "${1:-.}" || exit 2
files() { git ls-files 2>/dev/null || find . -type f -not -path './.git/*'; }
show() { echo "== $1"; files | grep -v -E '(^|/)(node_modules|\.venv|dist|build)/' | xargs grep -n -I -E "$2" 2>/dev/null | cut -c1-200 | head -60; echo; }
show "README 앵커 링크(README.md#…)"            'README(\.[a-zA-Z-]+)?\.md#'
show "글로 가리키는 절(README §N, README 의 … 절)" 'README ?§|README의 |README 의 [^ ]+ 절|see the README|README section'
# 코드·검사만 본다(문서의 하위 폴더 README 링크는 오탐이었다) — 루트 README 를 이름으로 여는 곳.
echo "== README 를 읽는 코드·검사"
files | grep -v -E '\.(md|mdx|rst|txt)$' | grep -v -E '(^|/)(node_modules|\.venv|dist|build)/' \
  | xargs grep -n -I -E '(^|[^/A-Za-z0-9_.-])README(\.[a-zA-Z-]+)?\.md|open\(.README|read_text\(.*README|README = ' 2>/dev/null | cut -c1-200 | head -60; echo
show "README 에서 절을 잘라 읽는 검사(제목 문자열)"   '_section\(README|README\.index\(|README\.split\(|"## [^"]+" *in README'
