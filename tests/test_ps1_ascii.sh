#!/usr/bin/env bash
# .ps1 은 ASCII 만 — Windows PowerShell 5.1 은 BOM 없는 파일을 ANSI(시스템 코드페이지)로 읽어 비ASCII 글자를 깨뜨린다.
# (install.ps1 은 5.1 로도 돌린다.) BOM 을 붙이는 대신 ASCII 로 둔다: BOM 은 다른 도구에서 말썽이다.
set -euo pipefail
cd "$(dirname "$0")/.."
bad=0
while IFS= read -r f; do
  if grep -nP '[^\x00-\x7F]' "$f" >/dev/null; then
    echo "FAIL $f: 비ASCII 문자"; grep -nP '[^\x00-\x7F]' "$f" | head -3; bad=1
  fi
done < <(git ls-files '*.ps1')
[ $bad -eq 0 ] && echo "test_ps1_ascii: .ps1 은 ASCII"
exit $bad
