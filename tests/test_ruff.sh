#!/usr/bin/env bash
# 정적 검사: ruff — 추적되는 .py 와 python shebang 스크립트(bin/*, git/hooks/*) 전부. 설정은 ruff.toml.
set -euo pipefail
cd "$(dirname "$0")/.."
files=()
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case $f in *.py) files+=("$f"); continue ;; esac
  head -1 "$f" | grep -q '^#!.*python' && files+=("$f")
done < <(git ls-files)
if command -v ruff >/dev/null; then r=(ruff); elif command -v uvx >/dev/null; then r=(uvx -q ruff); else r=(pipx run ruff); fi
"${r[@]}" check "${files[@]}"
echo "ruff: ${#files[@]} files clean"
