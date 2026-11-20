#!/usr/bin/env bash
# 정적 검사: shellcheck (style 이상, source 따라감) — 추적되는 sh/bash 스크립트 전부. zsh 파일은 shellcheck 가 지원하지 않아 뺀다.
set -euo pipefail
cd "$(dirname "$0")/.."
files=()
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case $f in *.sh) files+=("$f"); continue ;; esac
  head -1 "$f" | grep -qE '^#!.*[/ ](ba)?sh( |$)' && files+=("$f")
done < <(git ls-files)
for lib in git/hooks/_*.sh; do [ -f "$lib" ] && files+=("$lib"); done
mapfile -t files < <(printf '%s\n' "${files[@]}" | sort -u)
if command -v shellcheck >/dev/null; then sc=(shellcheck); else sc=(uvx -q --from shellcheck-py shellcheck); fi
"${sc[@]}" -x -S style "${files[@]}"
echo "shellcheck: ${#files[@]} files clean"
